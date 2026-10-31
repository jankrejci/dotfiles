use crate::backoff::{Backoff, STABLE_AFTER};
use crate::printer::Command;
use crate::state::{unix_now, AppState, Inner, PrintState};
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::collections::VecDeque;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use tokio::time::{interval, sleep, timeout};
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::http::HeaderValue;
use tokio_tungstenite::tungstenite::Message;
use tracing::{debug, info, warn};

const PING_INTERVAL: Duration = Duration::from_secs(30);
/// The server answers every ping, so a longer silence means a dead socket.
const SILENCE_LIMIT: Duration = Duration::from_secs(90);
const STATUS_INTERVAL: Duration = Duration::from_secs(5);
const SETTINGS_INTERVAL: Duration = Duration::from_secs(300);
const BOOST_MESSAGES: u32 = 20;
const REF_MEMORY: usize = 25;
/// Obico jogs in small steps, so a larger value is a bug or abuse and could crash the head.
const MAX_JOG_MM: f64 = 50.0;
/// A stalled handshake or send must not freeze the loop that also answers pings.
const IO_TIMEOUT: Duration = Duration::from_secs(10);

pub struct Config {
    pub url: String,
    pub token_file: PathBuf,
    /// Whether a video stream exists, since Obico must not be told about a webcam that is missing.
    pub has_video: bool,
}

pub fn read_token(path: &PathBuf) -> Result<String, String> {
    let raw = std::fs::read_to_string(path)
        .map_err(|e| format!("cannot read token file {}: {e}", path.display()))?;
    let token = raw.trim().to_string();
    if token.is_empty() {
        return Err(format!("token file {} is empty", path.display()));
    }
    Ok(token)
}

fn ws_url(base: &str) -> String {
    let base = base.trim_end_matches('/');
    let swapped = if let Some(rest) = base.strip_prefix("https://") {
        format!("wss://{rest}")
    } else if let Some(rest) = base.strip_prefix("http://") {
        format!("ws://{rest}")
    } else {
        base.to_string()
    };
    format!("{swapped}/ws/dev/")
}

fn settings(has_video: bool) -> Value {
    let host = std::fs::read_to_string("/proc/sys/kernel/hostname")
        .map(|h| h.trim().to_string())
        .unwrap_or_else(|_| "prusa-obico".into());
    let webcams = if has_video {
        json!([{
            "name": "prusa",
            "is_primary_camera": true,
            "is_nozzle_camera": false,
            "stream_mode": "h264_copy",
            "stream_id": 1,
            "data_channel_available": false,
            "flipV": false,
            "flipH": false,
            "rotation": 0,
            "streamRatio": "4:3"
        }])
    } else {
        json!([])
    };
    json!({
        "agent": {"name": "octoprint_obico", "version": "2.7.0"},
        "octoprint_version": "1.11.7",
        "platform_uname": ["Linux", host, "", "", std::env::consts::ARCH, "", "prusa-obico"],
        "installed_plugins": ["obico"],
        "temperature": {},
        "webcams": webcams
    })
}

/// Obico wraps the raw Janus request in a string field of its agent message.
fn janus_payload(msg: &Value) -> Option<&str> {
    msg.get("janus").and_then(Value::as_str)
}

/// Obico expects every Janus reply as a string field, not as nested JSON.
fn janus_frame(raw: &str) -> Value {
    json!({"janus": raw})
}

pub fn build_status(s: &Inner, with_settings: bool, has_video: bool) -> Value {
    let (text, operational, printing, paused) = match s.print_state {
        PrintState::Offline => ("Offline", false, false, false),
        PrintState::Idle => ("Operational", true, false, false),
        PrintState::Printing => ("Printing", true, true, false),
        PrintState::Paused => ("Paused", true, false, true),
    };
    let active = printing || paused;
    let flags = json!({
        "operational": operational,
        "printing": printing,
        "cancelling": false,
        "pausing": false,
        "resuming": false,
        "finishing": false,
        "closedOrError": s.print_state == PrintState::Offline,
        "error": false,
        "paused": paused,
        "ready": operational && !active,
        "sdReady": true
    });
    let file = if active {
        json!({"name": "SD print", "path": null, "origin": "sdcard", "size": null, "date": null})
    } else {
        json!({"name": null, "path": null, "origin": null, "size": null, "date": null})
    };
    let temperatures = match s.temps {
        Some(t) => json!({
            "tool0": {"actual": t.tool_actual, "target": t.tool_target},
            "bed": {"actual": t.bed_actual, "target": t.bed_target}
        }),
        None => json!({}),
    };
    let mut msg = json!({
        "current_print_ts": s.current_print_ts,
        "status": {
            "state": {"text": text, "flags": flags},
            "job": {
                "file": file,
                "estimatedPrintTime": null,
                "lastPrintTime": null,
                "filament": {"length": null, "volume": null},
                "user": null
            },
            "progress": {
                "completion": if active { json!(s.completion) } else { Value::Null },
                "filepos": if active { json!(s.filepos) } else { Value::Null },
                "printTime": null,
                "printTimeLeft": null,
                "printTimeLeftOrigin": null
            },
            "currentZ": null,
            "temperatures": temperatures,
            "_ts": unix_now(),
            "currentLayerHeight": null,
            "display_status": {"message": null}
        }
    });
    if with_settings {
        msg["settings"] = settings(has_video);
    }
    msg
}

fn axes_from(value: &Value) -> Vec<char> {
    let Some(list) = value.as_array() else {
        return Vec::new();
    };
    list.iter()
        .filter_map(|v| v.as_str())
        .filter_map(|s| s.chars().next())
        .map(|c| c.to_ascii_uppercase())
        // Only motion axes are allowed so no stray G-code can be injected.
        .filter(|c| matches!(c, 'X' | 'Y' | 'Z'))
        .collect()
}

fn jog_from(value: &Value) -> Vec<(char, f64)> {
    let Some(map) = value.as_object() else {
        return Vec::new();
    };
    map.iter()
        .filter_map(|(k, v)| {
            let axis = k.chars().next()?.to_ascii_uppercase();
            let amount = v.as_f64().filter(|a| a.is_finite())?;
            matches!(axis, 'X' | 'Y' | 'Z').then_some((axis, amount.clamp(-MAX_JOG_MM, MAX_JOG_MM)))
        })
        .collect()
}

pub struct Session {
    state: Arc<AppState>,
    commands: mpsc::Sender<Command>,
    janus: mpsc::Sender<String>,
    boost: u32,
    seen_refs: VecDeque<String>,
}

impl Session {
    async fn dispatch(&mut self, cmd: Command) -> Result<(), String> {
        let print_state = self.state.snapshot().print_state;
        if print_state == PrintState::Offline {
            return Err("printer offline".into());
        }
        // Obico can deliver stale commands and M601 on Prusa firmware parks the
        // head even when idle, so a command only passes in a state it makes sense in.
        // Homing or jogging a paused print would ruin the resume.
        match (&cmd, print_state) {
            (Command::Pause, PrintState::Printing) => {}
            (Command::Pause, _) => return Err("not printing".into()),
            (Command::Resume, PrintState::Paused) => {}
            (Command::Resume, _) => return Err("not paused".into()),
            (Command::Cancel, PrintState::Printing | PrintState::Paused) => {}
            (Command::Cancel, _) => return Err("not printing".into()),
            (Command::Home(_) | Command::Jog(_), PrintState::Idle) => {}
            (Command::Home(_) | Command::Jog(_), _) => return Err("printer busy".into()),
        }
        info!("command from Obico: {}", cmd.name());
        self.state.record_command(cmd.name());
        self.boost = BOOST_MESSAGES;
        // A full queue means the printer task stalled, and waiting here would also stall the pings.
        self.commands
            .try_send(cmd)
            .map_err(|_| "command queue full".to_string())
    }

    async fn handle_commands(&mut self, list: &Value) {
        let Some(list) = list.as_array() else { return };
        for item in list {
            let cmd = match item.get("cmd").and_then(Value::as_str) {
                Some("pause") => Command::Pause,
                Some("resume") => Command::Resume,
                Some("cancel") => Command::Cancel,
                other => {
                    debug!("ignoring server command {other:?}");
                    continue;
                }
            };
            if let Err(e) = self.dispatch(cmd).await {
                warn!("server command dropped: {e}");
            }
        }
    }

    /// Returns the reply to send, or None when the message has no ref.
    async fn handle_passthru(&mut self, p: &Value) -> Option<Value> {
        let target = p.get("target").and_then(Value::as_str).unwrap_or("");
        let func = p.get("func").and_then(Value::as_str).unwrap_or("");
        let args = p
            .get("args")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let reference = p.get("ref").and_then(Value::as_str).map(str::to_string);
        if let Some(r) = &reference {
            if self.seen_refs.contains(r) {
                debug!("duplicate passthru ref {r}");
                return None;
            }
            self.seen_refs.push_back(r.clone());
            if self.seen_refs.len() > REF_MEMORY {
                self.seen_refs.pop_front();
            }
        }
        self.boost = BOOST_MESSAGES;
        let arg0 = args.first().cloned().unwrap_or(Value::Null);
        let outcome: Result<Value, String> = match (target, func) {
            ("_printer", "pause_print") => self.dispatch(Command::Pause).await.map(|_| Value::Null),
            ("_printer", "resume_print") => {
                self.dispatch(Command::Resume).await.map(|_| Value::Null)
            }
            ("_printer", "cancel_print") => {
                self.dispatch(Command::Cancel).await.map(|_| Value::Null)
            }
            ("_printer", "home") => self
                .dispatch(Command::Home(axes_from(&arg0)))
                .await
                .map(|_| Value::Null),
            ("_printer", "jog") => {
                let moves = jog_from(&arg0);
                if moves.is_empty() {
                    Err("no valid axes".into())
                } else {
                    self.dispatch(Command::Jog(moves))
                        .await
                        .map(|_| Value::Null)
                }
            }
            ("gcode_hooks", "toggle_terminal_feed") => Ok(json!(false)),
            _ => Err(format!("unsupported: {target}.{func}")),
        };
        let reference = reference?;
        Some(match outcome {
            Ok(ret) => json!({"passthru": {"ref": reference, "ret": ret}}),
            Err(error) => json!({"passthru": {"ref": reference, "error": error}}),
        })
    }

    async fn handle_text(&mut self, text: &str) -> Vec<Value> {
        let Ok(msg) = serde_json::from_str::<Value>(text) else {
            debug!("non-JSON text frame from Obico");
            return Vec::new();
        };
        if let Some(remote) = msg.get("remote_status") {
            if let Some(viewing) = remote.get("viewing").and_then(Value::as_bool) {
                self.state.update(|s| s.viewing = viewing);
            }
        }
        if let Some(raw) = janus_payload(&msg) {
            // Signaling is only useful fresh, so a full queue drops the newest message.
            if self.janus.try_send(raw.to_string()).is_err() {
                debug!("dropping Janus signaling, queue full or Janus down");
            }
        }
        if let Some(list) = msg.get("commands") {
            self.handle_commands(list).await;
        }
        let mut replies = Vec::new();
        if let Some(p) = msg.get("passthru") {
            replies.extend(self.handle_passthru(p).await);
        }
        replies
    }
}

type Socket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn send(ws: &mut Socket, message: Message) -> Result<(), String> {
    timeout(IO_TIMEOUT, ws.send(message))
        .await
        .map_err(|_| "send timed out".to_string())?
        .map_err(|e| e.to_string())
}

async fn send_json(ws: &mut Socket, value: &Value) -> Result<(), String> {
    send(ws, Message::Text(value.to_string().into())).await
}

async fn connection(
    cfg: &Config,
    state: &Arc<AppState>,
    commands: &mpsc::Sender<Command>,
    janus_tx: &mpsc::Sender<String>,
    janus_rx: &mut mpsc::Receiver<String>,
    on_connected: impl FnOnce(),
) -> Result<String, String> {
    let token = read_token(&cfg.token_file)?;
    let mut request = ws_url(&cfg.url)
        .into_client_request()
        .map_err(|e| e.to_string())?;
    let mut auth = HeaderValue::from_str(&format!("bearer {token}")).map_err(|e| e.to_string())?;
    auth.set_sensitive(true);
    request.headers_mut().insert("authorization", auth);
    let (mut ws, _) = timeout(IO_TIMEOUT, tokio_tungstenite::connect_async(request))
        .await
        .map_err(|_| "connect timed out".to_string())?
        .map_err(|e| e.to_string())?;
    on_connected();
    state.update(|s| s.obico_connected = true);
    // Janus replies from before this connection belong to sessions Obico has forgotten.
    while janus_rx.try_recv().is_ok() {}

    let mut session = Session {
        state: state.clone(),
        commands: commands.clone(),
        janus: janus_tx.clone(),
        boost: 0,
        seen_refs: VecDeque::new(),
    };
    let mut ping = interval(PING_INTERVAL);
    let mut tick = interval(Duration::from_secs(1));
    let mut last_rx = Instant::now();
    let mut last_status: Option<Instant> = None;
    let mut last_settings: Option<Instant> = None;
    let mut janus_was_up = false;
    let result = loop {
        let mut send_now = false;
        tokio::select! {
            frame = ws.next() => {
                let frame = match frame {
                    None => break Ok("closed by peer".to_string()),
                    Some(Err(e)) => break Err(e.to_string()),
                    Some(Ok(f)) => f,
                };
                last_rx = Instant::now();
                match frame {
                    Message::Text(text) => {
                        let mut failed = None;
                        for reply in session.handle_text(text.as_str()).await {
                            if let Err(e) = send_json(&mut ws, &reply).await {
                                failed = Some(e);
                                break;
                            }
                        }
                        if let Some(e) = failed {
                            break Err(e);
                        }
                        // Report the effect of a command quickly.
                        send_now = session.boost == BOOST_MESSAGES;
                    }
                    Message::Close(frame) => break Ok(format!("closed by server: {frame:?}")),
                    // Binary frames carry BSON that this agent does not need.
                    _ => {}
                }
            }
            _ = ping.tick() => {
                if last_rx.elapsed() > SILENCE_LIMIT {
                    break Ok(format!("no data for {} s", SILENCE_LIMIT.as_secs()));
                }
                if let Err(e) = send(&mut ws, Message::Ping(Default::default())).await {
                    break Err(e);
                }
            }
            raw = janus_rx.recv() => {
                let Some(raw) = raw else { break Err("Janus channel closed".to_string()) };
                if let Err(e) = send_json(&mut ws, &janus_frame(&raw)).await {
                    break Err(e);
                }
            }
            _ = state.changed.notified() => send_now = true,
            _ = tick.tick() => {
                if session.boost > 0 {
                    session.boost -= 1;
                    send_now = true;
                } else {
                    send_now = last_status.map_or(true, |t| t.elapsed() >= STATUS_INTERVAL);
                }
            }
        }
        if !send_now {
            continue;
        }
        let snapshot = state.snapshot();
        // Obico only learns about the webcam from settings, so resend them once Janus is up.
        if snapshot.janus_connected && !janus_was_up {
            last_settings = None;
        }
        janus_was_up = snapshot.janus_connected;
        let with_settings = last_settings.map_or(true, |t| t.elapsed() >= SETTINGS_INTERVAL);
        let status = build_status(&snapshot, with_settings, cfg.has_video);
        if let Err(e) = send_json(&mut ws, &status).await {
            break Err(e);
        }
        last_status = Some(Instant::now());
        if with_settings {
            last_settings = last_status;
        }
        state.update(|s| s.status_messages += 1);
    };
    // Without Obico nobody watches, so the stream and the snapshot boost must stop.
    state.update(|s| {
        s.obico_connected = false;
        s.viewing = false;
    });
    result
}

pub async fn run(
    cfg: Config,
    state: Arc<AppState>,
    commands: mpsc::Sender<Command>,
    janus_tx: mpsc::Sender<String>,
    mut janus_rx: mpsc::Receiver<String>,
) {
    let mut backoff = Backoff::new();
    // Each outage logs one line: the failure at startup, the disconnect after
    // that. The flag never resets because every later outage begins with a
    // logged disconnect, and the retries that follow it stay quiet.
    let mut failure_logged = false;
    loop {
        let mut connected_at = None;
        let outcome = connection(&cfg, &state, &commands, &janus_tx, &mut janus_rx, || {
            connected_at = Some(Instant::now());
            info!("Obico connected");
        })
        .await;
        let connected = connected_at.is_some();
        if connected_at.is_some_and(|at| at.elapsed() >= STABLE_AFTER) {
            backoff.reset();
        }
        match outcome {
            Ok(reason) | Err(reason) if connected => {
                warn!("Obico disconnected: {reason}");
                failure_logged = true;
            }
            Ok(reason) | Err(reason) => {
                if !failure_logged {
                    warn!("Obico connection failed: {reason}");
                    failure_logged = true;
                }
            }
        }
        sleep(backoff.next_delay()).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_advertise_h264_webcam() {
        let cam = &settings(true)["webcams"][0];
        assert_eq!(cam["stream_mode"], "h264_copy");
        assert_eq!(cam["stream_id"], 1);
        assert_eq!(cam["streamRatio"], "4:3");
    }

    #[test]
    fn settings_without_video_have_no_webcam() {
        assert_eq!(settings(false)["webcams"], json!([]));
    }

    #[test]
    fn jog_distance_is_clamped() {
        let mut moves = jog_from(&json!({"x": 500.0, "y": -500.0, "z": 1.5, "e": 5.0}));
        moves.sort_by_key(|m| m.0);
        assert_eq!(moves, [('X', 50.0), ('Y', -50.0), ('Z', 1.5)]);
    }

    #[test]
    fn janus_frame_keeps_raw_string() {
        let raw = r#"{"janus":"ack","transaction":"abc"}"#;
        let wrapped = janus_frame(raw);
        assert_eq!(wrapped, json!({"janus": raw}));
        assert_eq!(wrapped["janus"].as_str(), Some(raw));
    }

    #[test]
    fn janus_payload_needs_a_string() {
        let raw = r#"{"janus":"create","transaction":"abc"}"#;
        assert_eq!(janus_payload(&json!({"janus": raw})), Some(raw));
        assert_eq!(janus_payload(&json!({"janus": {"janus": "create"}})), None);
        assert_eq!(janus_payload(&json!({"commands": []})), None);
    }
}
