use crate::backoff::Backoff;
use crate::state::{AppState, PrintState, Temps};
use std::io;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncBufRead, AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio::time::{interval, sleep};
use tracing::{debug, info, trace, warn};

const POLL_INTERVAL: Duration = Duration::from_secs(5);
/// Temperature autoreport arrives every two seconds, so silence means a dead link.
const SILENCE_LIMIT: Duration = Duration::from_secs(30);

#[derive(Debug)]
pub enum Command {
    Pause,
    Resume,
    Cancel,
    Home(Vec<char>),
    Jog(Vec<(char, f64)>),
}

impl Command {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Pause => "pause",
            Self::Resume => "resume",
            Self::Cancel => "cancel",
            Self::Home(_) => "home",
            Self::Jog(_) => "jog",
        }
    }

    fn gcode(&self) -> Vec<String> {
        match self {
            Self::Pause => vec!["M601".into()],
            Self::Resume => vec!["M602".into()],
            Self::Cancel => vec!["M603".into()],
            Self::Home(axes) if axes.is_empty() => vec!["G28".into()],
            Self::Home(axes) => {
                let list: Vec<String> = axes.iter().map(char::to_string).collect();
                vec![format!("G28 {}", list.join(" "))]
            }
            Self::Jog(moves) => {
                let list: Vec<String> = moves.iter().map(|(a, v)| format!("{a}{v}")).collect();
                vec![
                    "G91".into(),
                    format!("G1 {} F3000", list.join(" ")),
                    "G90".into(),
                ]
            }
        }
    }
}

#[derive(Debug, PartialEq)]
pub enum M27 {
    Printing { done: u64, total: u64 },
    NotPrinting,
    Paused,
}

pub fn parse_temps(line: &str) -> Option<Temps> {
    let mut tool = None;
    let mut bed = None;
    let mut tokens = line.split_whitespace().peekable();
    while let Some(token) = tokens.next() {
        let slot = if token.starts_with("T:") {
            &mut tool
        } else if token.starts_with("B:") {
            &mut bed
        } else {
            continue;
        };
        let rest = &token[2..];
        // The target is usually a separate token but tolerate "21.7/0.0".
        let (actual, target) = match rest.split_once('/') {
            Some((a, t)) => (a.to_string(), Some(t.to_string())),
            None => {
                let target = tokens
                    .next_if(|t| t.starts_with('/'))
                    .map(|t| t[1..].to_string());
                (rest.to_string(), target)
            }
        };
        let actual: f64 = actual.parse().ok()?;
        let target: f64 = target.and_then(|t| t.parse().ok()).unwrap_or(0.0);
        *slot = Some((actual, target));
    }
    let (tool_actual, tool_target) = tool?;
    let (bed_actual, bed_target) = bed?;
    Some(Temps {
        tool_actual,
        tool_target,
        bed_actual,
        bed_target,
    })
}

pub fn parse_m27(line: &str) -> Option<M27> {
    if line.to_ascii_lowercase().contains("paused") {
        return Some(M27::Paused);
    }
    if line.contains("Not SD printing") {
        return Some(M27::NotPrinting);
    }
    let rest = line.split("SD printing byte").nth(1)?;
    let (done, total) = rest.trim().split_once('/')?;
    Some(M27::Printing {
        done: done.trim().parse().ok()?,
        total: total.split_whitespace().next()?.parse().ok()?,
    })
}

/// Extracts a human readable firmware description from an M115 reply.
pub fn parse_m115(line: &str) -> Option<String> {
    if !line.starts_with("FIRMWARE_NAME:") {
        return None;
    }
    let mut fields: Vec<(String, String)> = Vec::new();
    for word in line.split(' ') {
        let key = word.split_once(':').filter(|(k, _)| {
            !k.is_empty() && k.chars().all(|c| c.is_ascii_uppercase() || c == '_')
        });
        match (key, fields.last_mut()) {
            (Some((k, v)), _) => fields.push((k.to_string(), v.to_string())),
            (None, Some((_, v))) => {
                v.push(' ');
                v.push_str(word);
            }
            (None, None) => {}
        }
    }
    let get = |name: &str| {
        fields
            .iter()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.clone())
    };
    let firmware = get("FIRMWARE_NAME")?;
    Some(match get("MACHINE_TYPE") {
        Some(machine) => format!("{firmware} ({machine})"),
        None => firmware,
    })
}

fn apply_m27(state: &AppState, m27: M27) {
    match m27 {
        M27::Printing { done, total } => {
            state.update(|s| s.pause_requested = false);
            let completion = if total == 0 {
                0.0
            } else {
                100.0 * done as f64 / total as f64
            };
            state.set_print_state(PrintState::Printing, Some(completion), Some(done));
        }
        M27::Paused => state.set_print_state(PrintState::Paused, None, None),
        M27::NotPrinting => {
            let paused = state.update(|s| s.pause_requested);
            let new = if paused {
                PrintState::Paused
            } else {
                PrintState::Idle
            };
            state.set_print_state(new, None, None);
        }
    }
}

fn handle_line(state: &AppState, line: &str) {
    if let Some(firmware) = parse_m115(line) {
        state.update(|s| s.firmware = Some(firmware));
        return;
    }
    if let Some(temps) = parse_temps(line) {
        state.update(|s| s.temps = Some(temps));
        // A temperature line never carries M27 state, whether autoreport or "ok T:" reply,
        // so parsing stops here.
        return;
    }
    if let Some(m27) = parse_m27(line) {
        apply_m27(state, m27);
        return;
    }
    if line == "ok" {
        trace!("printer: ok");
        return;
    }
    debug!("printer: unhandled line: {line}");
}

async fn send(wr: &mut tokio::net::tcp::OwnedWriteHalf, line: &str) -> io::Result<()> {
    wr.write_all(format!("{line}\n").as_bytes()).await
}

async fn run_command(
    wr: &mut tokio::net::tcp::OwnedWriteHalf,
    state: &AppState,
    cmd: Command,
) -> io::Result<()> {
    match cmd {
        Command::Pause => {
            state.update(|s| s.pause_requested = s.print_state == PrintState::Printing)
        }
        Command::Resume | Command::Cancel => state.update(|s| s.pause_requested = false),
        _ => {}
    }
    for line in cmd.gcode() {
        send(wr, &line).await?;
    }
    // Refresh the print state right away instead of waiting for the next poll.
    send(wr, "M27").await
}

/// Firmware lines are short, so anything longer is line noise and must not grow the buffer.
const MAX_LINE: usize = 1024;

/// Splits the serial stream into lines without ever holding more than `MAX_LINE` bytes.
struct LineReader<R> {
    rd: R,
    buf: Vec<u8>,
    discarding: bool,
}

impl<R: AsyncBufRead + Unpin> LineReader<R> {
    fn new(rd: R) -> Self {
        Self {
            rd,
            buf: Vec::new(),
            discarding: false,
        }
    }

    /// Returns None at end of stream. An over-long line is skipped and a
    /// non-UTF-8 byte is replaced, so neither can end the session. All state
    /// lives in the struct, which keeps this safe to cancel in a select.
    async fn next_line(&mut self) -> io::Result<Option<String>> {
        loop {
            let available = self.rd.fill_buf().await?;
            if available.is_empty() {
                return Ok(None);
            }
            let end = available.iter().position(|&b| b == b'\n');
            let chunk = &available[..end.unwrap_or(available.len())];
            if !self.discarding {
                self.buf.extend_from_slice(chunk);
                if self.buf.len() > MAX_LINE {
                    debug!("printer: dropping a line over {MAX_LINE} bytes");
                    self.buf.clear();
                    self.discarding = true;
                }
            }
            let consumed = end.map_or(available.len(), |i| i + 1);
            self.rd.consume(consumed);
            if end.is_none() {
                continue;
            }
            if std::mem::take(&mut self.discarding) {
                continue;
            }
            let line = String::from_utf8_lossy(&self.buf).into_owned();
            self.buf.clear();
            return Ok(Some(line));
        }
    }
}

async fn session(
    stream: TcpStream,
    state: &AppState,
    rx: &mut mpsc::Receiver<Command>,
    link_up: &mut bool,
) -> io::Result<String> {
    let (rd, mut wr) = stream.into_split();
    let mut lines = LineReader::new(BufReader::new(rd));
    // Commands queued while the link was down are stale, drop them.
    while rx.try_recv().is_ok() {}
    // A leading newline flushes any partial line left in the firmware buffer.
    wr.write_all(b"\nM115\nM155 S2\n").await?;
    // ser2net accepts the connection even when the printer is off, so only a
    // line from the firmware proves the link is up.
    let mut poll = interval(POLL_INTERVAL);
    let mut last_rx = Instant::now();
    loop {
        tokio::select! {
            line = lines.next_line() => {
                let Some(line) = line? else { return Ok("closed by peer".into()) };
                if !*link_up {
                    info!("printer connected");
                    state.set_printer_connected();
                    *link_up = true;
                }
                last_rx = Instant::now();
                let line = line.trim();
                if line == "start" {
                    info!("printer reset detected, re-enabling temperature autoreport");
                    send(&mut wr, "M155 S2").await?;
                    continue;
                }
                handle_line(state, line);
            }
            cmd = rx.recv() => {
                let Some(cmd) = cmd else { return Ok("command channel closed".into()) };
                run_command(&mut wr, state, cmd).await?;
            }
            _ = poll.tick() => {
                if last_rx.elapsed() > SILENCE_LIMIT {
                    return Ok(format!("no data for {} s", SILENCE_LIMIT.as_secs()));
                }
                send(&mut wr, "M27").await?;
            }
        }
    }
}

pub async fn run(addr: String, state: Arc<AppState>, mut rx: mpsc::Receiver<Command>) {
    let mut backoff = Backoff::new();
    // Each outage logs one line: the failure at startup, the disconnect after
    // that. The flag never resets because every later outage begins with a
    // logged disconnect, and the retries that follow it stay quiet.
    let mut failure_logged = false;
    loop {
        match TcpStream::connect(&addr).await {
            Ok(stream) => {
                backoff.reset();
                let mut link_up = false;
                let reason = match session(stream, &state, &mut rx, &mut link_up).await {
                    Ok(reason) => reason,
                    Err(e) => e.to_string(),
                };
                state.set_printer_offline();
                // ser2net accepts while the printer is off, so a session without a
                // firmware line is a failed connect and must not log every attempt.
                if link_up {
                    warn!("printer disconnected: {reason}");
                    failure_logged = true;
                } else if !failure_logged {
                    warn!("printer link to {addr} failed: {reason}");
                    failure_logged = true;
                }
            }
            Err(e) => {
                if !failure_logged {
                    warn!("printer connection to {addr} failed: {e}");
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
    fn temps_with_ok_prefix() {
        let t =
            parse_temps("ok T:21.7 /0.0 B:21.8 /0.0 T0:21.7 /0.0 @:0 B@:0 P:0.0 A:33.0").unwrap();
        assert_eq!(
            t,
            Temps {
                tool_actual: 21.7,
                tool_target: 0.0,
                bed_actual: 21.8,
                bed_target: 0.0
            }
        );
    }

    #[test]
    fn temps_autoreport_with_targets() {
        let t = parse_temps("T:215.3 /215.0 B:60.1 /60.0 T0:215.3 /215.0 @:30 B@:12").unwrap();
        assert_eq!(t.tool_actual, 215.3);
        assert_eq!(t.tool_target, 215.0);
        assert_eq!(t.bed_target, 60.0);
    }

    #[test]
    fn temps_rejects_other_lines() {
        assert!(parse_temps("ok").is_none());
        assert!(parse_temps("Not SD printing").is_none());
        assert!(parse_temps("T0:21.7 /0.0").is_none());
    }

    #[test]
    fn m27_variants() {
        assert_eq!(parse_m27("Not SD printing"), Some(M27::NotPrinting));
        assert_eq!(
            parse_m27("SD printing byte 1234/5678"),
            Some(M27::Printing {
                done: 1234,
                total: 5678
            })
        );
        assert_eq!(parse_m27("// action:Paused"), Some(M27::Paused));
        assert_eq!(parse_m27("ok"), None);
    }

    #[test]
    fn m115_firmware() {
        let line = "FIRMWARE_NAME:Prusa-Firmware 3.14.1+7500 based on Marlin FIRMWARE_URL:https://github.com/prusa3d/Prusa-Firmware PROTOCOL_VERSION:1.0 MACHINE_TYPE:Prusa i3 MK3S EXTRUDER_COUNT:1 UUID:00000000-0000-0000-0000-000000000000";
        assert_eq!(
            parse_m115(line).unwrap(),
            "Prusa-Firmware 3.14.1+7500 based on Marlin (Prusa i3 MK3S)"
        );
        assert!(parse_m115("ok").is_none());
    }

    #[tokio::test]
    async fn long_and_garbled_lines_do_not_end_the_stream() {
        let mut input = b"ok\n".to_vec();
        input.extend(vec![b'x'; MAX_LINE + 10]);
        input.extend(b"\nT:1\xff\nlast");
        let mut lines = LineReader::new(&input[..]);
        assert_eq!(lines.next_line().await.unwrap().as_deref(), Some("ok"));
        assert_eq!(
            lines.next_line().await.unwrap().as_deref(),
            Some("T:1\u{fffd}")
        );
        assert_eq!(lines.next_line().await.unwrap(), None);
    }

    #[test]
    fn gcode_for_commands() {
        assert_eq!(Command::Home(vec![]).gcode(), ["G28"]);
        assert_eq!(Command::Home(vec!['X', 'Y']).gcode(), ["G28 X Y"]);
        assert_eq!(
            Command::Jog(vec![('X', 10.0)]).gcode(),
            ["G91", "G1 X10 F3000", "G90"]
        );
    }
}
