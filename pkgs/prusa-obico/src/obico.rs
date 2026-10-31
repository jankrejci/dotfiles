use crate::printer::{Command, TerminalLine, MAX_GCODE_LINE};
use crate::reconnect::{self, Ended, Link};
use crate::state::{unix_now, AppState, Inner, PrintState};
use crate::ws::{Keepalive, Ws};
use anyhow::{anyhow, bail, Context, Result};
use serde_json::{json, Value};
use std::collections::VecDeque;
use std::convert::Infallible;
use std::str::FromStr;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use tokio::time::interval;
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
/// Each line of a command waits for the ok of the previous one, so a long list would hold the
/// serial link for minutes while Pause and Cancel queue up behind it.
const MAX_GCODE_LINES: usize = 32;

/// Builds a home command from the axis list of an Obico request. Unknown axes are dropped, and
/// an empty list homes everything. A request that is no list, or whose axes are all unknown,
/// is refused, because homing everything for a garbled request would surprise the sender.
fn parse_home(axes: &Value) -> Result<Command> {
    let list = axes.as_array().context("axes must be a list")?;
    if list.is_empty() {
        return Ok(Command::Home(Vec::new()));
    }
    let axes: Vec<char> = list
        .iter()
        .filter_map(|v| v.as_str())
        // The value is the axis letter and nothing else, so "zebra" is no axis.
        .filter_map(|s| {
            let mut chars = s.chars();
            chars.next().filter(|_| chars.next().is_none())
        })
        .map(|c| c.to_ascii_uppercase())
        // The axis letter is formatted into G-code, so only motion axes may pass.
        .filter(|c| matches!(c, 'X' | 'Y' | 'Z'))
        .collect();
    if axes.is_empty() {
        bail!("no valid axes");
    }
    Ok(Command::Home(axes))
}

/// Builds a G-code command from the first argument of a `commands` request, which holds
/// the lines as one newline separated string or as a list of strings. The lines pass verbatim
/// like in OctoPrint, but a control character or an over-long line could break the framing
/// of the serial protocol, so those are refused. A line that starts with a semicolon is a
/// comment and is dropped, because it would hold the flow while it waits for an ok and a
/// Pause or Cancel queues behind it. A comment after a command stays.
fn parse_gcode(arg: &Value) -> Result<Command> {
    let text = match arg {
        Value::String(s) => s.clone(),
        Value::Array(list) => list
            .iter()
            .filter_map(Value::as_str)
            .collect::<Vec<_>>()
            .join("\n"),
        _ => bail!("no G-code given"),
    };
    let lines: Vec<String> = text
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with(';'))
        .map(str::to_string)
        .collect();
    if lines.is_empty() {
        bail!("no G-code given");
    }
    if lines.len() > MAX_GCODE_LINES {
        bail!("G-code over {MAX_GCODE_LINES} lines");
    }
    for line in &lines {
        if line.chars().any(char::is_control) {
            bail!("G-code contains a control character");
        }
        if line.len() > MAX_GCODE_LINE {
            bail!("G-code line over {MAX_GCODE_LINE} bytes");
        }
    }
    Ok(Command::Gcode(lines))
}

/// Builds a jog command from the axis map of an Obico request, clamping each distance.
fn parse_jog(axes: &Value) -> Result<Command> {
    let mut moves = Vec::new();
    for (k, v) in axes.as_object().into_iter().flatten() {
        // The key is the axis letter and nothing else, so "xy" or "x1" is no axis.
        let mut chars = k.chars();
        let (Some(axis), None) = (chars.next(), chars.next()) else {
            continue;
        };
        let axis = axis.to_ascii_uppercase();
        let Some(amount) = v.as_f64().filter(|a| a.is_finite()) else {
            continue;
        };
        if !matches!(axis, 'X' | 'Y' | 'Z') {
            continue;
        }
        if moves.iter().any(|(a, _)| *a == axis) {
            bail!("axis {axis} given twice");
        }
        // The bridge knows neither whether the axes are homed nor how far the nozzle is
        // from the bed, so a downward move could crash the nozzle into the plate.
        if axis == 'Z' && amount < 0.0 {
            bail!("moving Z down is not allowed");
        }
        moves.push((axis, amount.clamp(-MAX_JOG_MM, MAX_JOG_MM)));
    }
    if moves.is_empty() {
        bail!("no valid axes");
    }
    Ok(Command::Jog(moves))
}

/// The base URL of the Obico server, from which the websocket and the HTTP endpoints derive.
/// Parsing never fails, because a wrong URL shows up as a connect error with the URL in the log.
#[derive(Clone, Debug)]
pub struct ObicoUrl(String);

impl FromStr for ObicoUrl {
    type Err = Infallible;

    fn from_str(url: &str) -> Result<Self, Infallible> {
        Ok(Self(url.trim_end_matches('/').to_string()))
    }
}

impl ObicoUrl {
    /// The agent websocket, with the scheme swapped to its websocket counterpart.
    fn ws(&self) -> String {
        let base = &self.0;
        if let Some(rest) = base.strip_prefix("https://") {
            return format!("wss://{rest}/ws/dev/");
        }
        if let Some(rest) = base.strip_prefix("http://") {
            return format!("ws://{rest}/ws/dev/");
        }
        format!("{base}/ws/dev/")
    }

    /// An HTTP endpoint below the base URL, `path` starting with a slash.
    pub fn endpoint(&self, path: &str) -> String {
        format!("{}{path}", self.0)
    }
}

pub struct Config {
    pub url: ObicoUrl,
    pub token: Arc<str>,
    /// Whether a video stream exists, since Obico must not be told about a webcam that is missing.
    pub has_video: bool,
}

impl Config {
    fn settings(&self) -> Value {
        let host = std::fs::read_to_string("/proc/sys/kernel/hostname")
            .map(|h| h.trim().to_string())
            .unwrap_or_else(|_| "prusa-obico".into());
        let webcams = if self.has_video {
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

    /// Builds the status message, with the settings attached when Obico should learn them again.
    fn status_message(&self, s: &Inner, with_settings: bool) -> Value {
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
        let temperatures = s.temps.map_or_else(|| json!({}), |t| json!(t));
        let mut msg = json!({
            // Obico marks no running print with -1.
            "current_print_ts": s.current_print_ts.unwrap_or(-1),
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
        if let (true, Some(map)) = (with_settings, msg.as_object_mut()) {
            map.insert("settings".into(), self.settings());
        }
        msg
    }
}

pub struct Session {
    state: Arc<AppState>,
    commands: mpsc::Sender<Command>,
    janus: mpsc::Sender<String>,
    boost: u32,
    seen_refs: VecDeque<String>,
}

impl Session {
    fn dispatch(&mut self, cmd: Command) -> Result<()> {
        let snapshot = self.state.read();
        let print_state = snapshot.print_state;
        if print_state == PrintState::Offline {
            bail!("printer offline");
        }
        // Obico can deliver stale commands and M601 on Prusa firmware parks the
        // head even when idle, so a command only passes in a state it makes sense in.
        // Homing or jogging a paused print would ruin the resume.
        // The print state only updates on the next M27 reply, so the request flags refuse a
        // second Pause or Cancel that arrives before that reply. The same delay lets Home and
        // Jog pass for up to one POLL_INTERVAL after a print is started from the printer menu,
        // because M27 polling is the only source of the print state.
        match (&cmd, print_state) {
            (Command::Pause, _) if snapshot.pause_requested() => {
                bail!("pause already requested")
            }
            (Command::Pause, PrintState::Printing) => {}
            (Command::Pause, _) => bail!("not printing"),
            (Command::Resume, PrintState::Paused) => {}
            (Command::Resume, _) => bail!("not paused"),
            (Command::Cancel, _) if snapshot.cancel_requested => {
                bail!("cancel already requested")
            }
            (Command::Cancel, PrintState::Printing | PrintState::Paused) => {}
            (Command::Cancel, _) => bail!("not printing"),
            // Raw G-code also passes while printing, because baby-stepping and the speed and flow
            // factors only make sense then. The bridge cannot judge arbitrary G-code anyway. A raw
            // M602 or M603 still ends up in the right flags, because the firmware answers each of
            // them with a host action line that the printer task tracks. A raw M601 on an idle
            // printer is the exception, because the paused line only counts while a print runs.
            (Command::Gcode(_), _) => {}
            (Command::Home(_) | Command::Jog(_), PrintState::Idle) => {}
            (Command::Home(_) | Command::Jog(_), _) => bail!("printer busy"),
        }
        info!("command from Obico: {}", cmd.name());
        self.state.record_command(cmd.name());
        self.boost = BOOST_MESSAGES;
        let is_pause = matches!(cmd, Command::Pause);
        let is_cancel = matches!(cmd, Command::Cancel);
        if is_pause {
            self.state.request_pause();
        }
        if is_cancel {
            self.state.request_cancel();
        }
        // A full queue means the printer task stalled, and waiting here would also stall the pings.
        self.commands.try_send(cmd).map_err(|_| {
            if is_pause {
                self.state.withdraw_pause();
            }
            if is_cancel {
                self.state.withdraw_cancel();
            }
            anyhow!("command queue full")
        })
    }

    fn handle_commands(&mut self, list: &Value) {
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
            if let Err(e) = self.dispatch(cmd) {
                warn!("server command dropped: {e}");
            }
        }
    }

    /// Returns the reply to send, or None when the message has no ref.
    fn handle_passthru(&mut self, p: &Value) -> Option<Value> {
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
        let outcome: Result<Value> = match (target, func) {
            ("_printer", "pause_print") => self.dispatch(Command::Pause).map(|_| Value::Null),
            ("_printer", "resume_print") => self.dispatch(Command::Resume).map(|_| Value::Null),
            ("_printer", "cancel_print") => self.dispatch(Command::Cancel).map(|_| Value::Null),
            ("_printer", "home") => parse_home(&arg0)
                .and_then(|cmd| self.dispatch(cmd))
                .map(|_| Value::Null),
            ("_printer", "jog") => parse_jog(&arg0)
                .and_then(|cmd| self.dispatch(cmd))
                .map(|_| Value::Null),
            ("_printer", "commands") => parse_gcode(&arg0)
                .and_then(|cmd| self.dispatch(cmd))
                .map(|_| Value::Null),
            ("gcode_hooks", "toggle_terminal_feed") => {
                // Only on and off change the flag, any other argument just asks for it.
                match arg0.as_str() {
                    Some("on") => self.state.set_terminal_feed(true),
                    Some("off") => self.state.set_terminal_feed(false),
                    _ => {}
                }
                Ok(json!(self.state.with(|s| s.terminal_feed)))
            }
            _ => {
                info!("unsupported passthru {target:?}.{func:?}");
                Err(anyhow!("unsupported: {target}.{func}"))
            }
        };
        let reference = reference?;
        Some(match outcome {
            Ok(ret) => json!({"passthru": {"ref": reference, "ret": ret}}),
            Err(error) => json!({"passthru": {"ref": reference, "error": error.to_string()}}),
        })
    }

    fn handle_text(&mut self, text: &str) -> Vec<Value> {
        let Ok(msg) = serde_json::from_str::<Value>(text) else {
            debug!("non-JSON text frame from Obico");
            return Vec::new();
        };
        if let Some(remote) = msg.get("remote_status") {
            if let Some(viewing) = remote.get("viewing").and_then(Value::as_bool) {
                self.state.set_viewing(viewing);
            }
        }
        if let Some(raw) = msg.get("janus").and_then(Value::as_str) {
            // Signaling is only useful fresh, so a full queue drops the newest message.
            if self.janus.try_send(raw.to_string()).is_err() {
                warn!("dropping Janus signaling, queue full or Janus down");
            }
        }
        if let Some(list) = msg.get("commands") {
            self.handle_commands(list);
        }
        let mut replies = Vec::new();
        if let Some(p) = msg.get("passthru") {
            replies.extend(self.handle_passthru(p));
        }
        replies
    }
}

/// Without Obico nobody watches, so the stream and the snapshot boost must stop. The terminal feed
/// also ends, because the terminal asks again when it opens in the next session and a stale flag
/// would mirror the serial traffic to whoever views next.
fn end_session(state: &AppState) {
    state.set_obico_connected(false);
    state.set_viewing(false);
    state.set_terminal_feed(false);
}

pub struct Obico {
    cfg: Config,
    state: Arc<AppState>,
    commands: mpsc::Sender<Command>,
    janus_tx: mpsc::Sender<String>,
    janus_rx: mpsc::Receiver<String>,
    terminal_rx: mpsc::Receiver<TerminalLine>,
}

impl Link for Obico {
    type Conn = Ws;
    const NAME: &'static str = "Obico";
    const STABLE_AFTER: Duration = reconnect::STABLE_AFTER;

    async fn connect(&mut self) -> Result<Ws> {
        let mut request = self
            .cfg
            .url
            .ws()
            .into_client_request()
            .context("invalid Obico URL")?;
        let mut auth = HeaderValue::from_str(&format!("bearer {}", self.cfg.token))
            .context("token is not a valid header value")?;
        auth.set_sensitive(true);
        request.headers_mut().insert("authorization", auth);
        Ws::connect(request).await
    }

    async fn session(&mut self, mut ws: Ws) -> Ended {
        info!("Obico connected");
        let connected_at = Instant::now();
        let state = &self.state;
        state.set_obico_connected(true);
        // Janus replies from before this connection belong to sessions Obico has forgotten.
        while self.janus_rx.try_recv().is_ok() {}
        while self.terminal_rx.try_recv().is_ok() {}

        let mut session = Session {
            state: state.clone(),
            commands: self.commands.clone(),
            janus: self.janus_tx.clone(),
            boost: 0,
            seen_refs: VecDeque::new(),
        };
        let mut changes = state.subscribe();
        let mut keepalive = Keepalive::new(PING_INTERVAL, SILENCE_LIMIT);
        let mut tick = interval(Duration::from_secs(1));
        let mut last_status: Option<Instant> = None;
        let mut last_settings: Option<Instant> = None;
        let mut janus_was_up = false;
        let reason = 'session: loop {
            let mut send_now = false;
            tokio::select! {
                frame = ws.next() => {
                    let frame = match frame {
                        None => break "closed by peer".to_string(),
                        Some(Err(e)) => break e.to_string(),
                        Some(Ok(f)) => f,
                    };
                    keepalive.received();
                    let text = match frame {
                        Message::Text(text) => text,
                        Message::Close(frame) => break 'session format!("closed by server: {frame:?}"),
                        // Binary frames carry BSON that this agent does not need.
                        _ => continue,
                    };
                    for reply in session.handle_text(text.as_str()) {
                        if let Err(e) = ws.send_json(&reply).await {
                            break 'session format!("{e:#}");
                        }
                    }
                    // Report the effect of a command quickly.
                    send_now = session.boost == BOOST_MESSAGES;
                }
                _ = keepalive.tick() => {
                    if let Err(reason) = keepalive.ping(&mut ws).await {
                        break reason;
                    }
                }
                raw = self.janus_rx.recv() => {
                    let Some(raw) = raw else { break "Janus channel closed".to_string() };
                    if let Err(e) = ws.send_json(&json!({"janus": raw})).await {
                        break format!("{e:#}");
                    }
                }
                line = self.terminal_rx.recv() => {
                    let Some(line) = line else { break "terminal channel closed".to_string() };
                    // The feed may have stopped while the line waited in the queue.
                    if !state.terminal_feed_wanted() {
                        continue;
                    }
                    let feed = json!({"passthru": {"terminal_feed": {"msg": line.msg, "_ts": line.ts}}});
                    if let Err(e) = ws.send_json(&feed).await {
                        break format!("{e:#}");
                    }
                }
                changed = changes.changed() => {
                    if changed.is_err() {
                        break "state closed".to_string();
                    }
                    send_now = true;
                }
                _ = tick.tick() => {
                    let boosted = session.boost > 0;
                    session.boost = session.boost.saturating_sub(1);
                    send_now = boosted
                        || last_status.is_none_or(|t| t.elapsed() >= STATUS_INTERVAL);
                }
            }
            if !send_now {
                continue;
            }
            let snapshot = state.read();
            // Obico only learns about the webcam from settings, so resend them once Janus is up.
            if snapshot.janus_connected && !janus_was_up {
                last_settings = None;
            }
            janus_was_up = snapshot.janus_connected;
            let with_settings = last_settings.is_none_or(|t| t.elapsed() >= SETTINGS_INTERVAL);
            let status = self.cfg.status_message(&snapshot, with_settings);
            if let Err(e) = ws.send_json(&status).await {
                break format!("{e:#}");
            }
            last_status = Some(Instant::now());
            if with_settings {
                last_settings = last_status;
            }
            state.count_status_message();
        };
        end_session(state);
        Ended {
            reason,
            up_for: Some(connected_at.elapsed()),
        }
    }
}

impl Obico {
    pub fn new(
        cfg: Config,
        state: Arc<AppState>,
        commands: mpsc::Sender<Command>,
        janus_tx: mpsc::Sender<String>,
        janus_rx: mpsc::Receiver<String>,
        terminal_rx: mpsc::Receiver<TerminalLine>,
    ) -> Self {
        Self {
            cfg,
            state,
            commands,
            janus_tx,
            janus_rx,
            terminal_rx,
        }
    }

    pub async fn run(self) {
        self.supervise().await
    }
}

#[cfg(test)]
#[path = "tests/obico.rs"]
mod tests;
