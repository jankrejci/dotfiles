use crate::marlin::{Firmware, HostAction, Temps, M27};
use crate::reconnect::{Ended, Link};
use crate::state::{AppState, Inner, PrintState};
use anyhow::{anyhow, Context, Result};
use std::collections::VecDeque;
use std::io;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::io::{AsyncBufRead, AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::tcp::OwnedWriteHalf;
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio::time::{interval, timeout};
use tracing::{debug, info, trace, warn};

const POLL_INTERVAL: Duration = Duration::from_secs(5);
/// A stalled connect or write must not freeze the loop that also reads firmware lines.
const IO_TIMEOUT: Duration = Duration::from_secs(10);
/// Temperature autoreport arrives every two seconds, so silence means a dead link.
const SILENCE_LIMIT: Duration = Duration::from_secs(30);
/// The firmware finishes its queued moves before it parks, so M27 can report printing for a while
/// after M601, but not for this long.
const PAUSE_CONFIRM_LIMIT: Duration = Duration::from_secs(120);

#[derive(Debug, PartialEq)]
pub enum Command {
    Pause,
    Resume,
    Cancel,
    Home(Vec<char>),
    Jog(Vec<(char, f64)>),
    /// Raw G-code lines that Obico forwards from its controls and terminal.
    Gcode(Vec<String>),
}

impl Command {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Pause => "pause",
            Self::Resume => "resume",
            Self::Cancel => "cancel",
            Self::Home(_) => "home",
            Self::Jog(_) => "jog",
            Self::Gcode(_) => "gcode",
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
            Self::Gcode(lines) => lines.clone(),
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

/// Applies a host action line of the Prusa firmware and returns whether the line was one.
fn apply_host_action(state: &AppState, line: &str) -> bool {
    let Ok(action) = line.parse::<HostAction>() else {
        return false;
    };
    match action {
        HostAction::Paused => state.request_pause_if_printing(),
        HostAction::Resumed => state.withdraw_pause(),
        HostAction::Cancel => state.withdraw_print_requests(),
    }
    true
}

fn apply_m27(m27: M27, state: &AppState) {
    let (done, total) = match m27 {
        M27::Printing { done, total } => (done, total),
        M27::Paused => {
            state.set_print_state(PrintState::Paused, None, None);
            return;
        }
        M27::NotPrinting => {
            if state.with(Inner::pause_requested) {
                state.set_print_state(PrintState::Paused, None, None);
            } else if state.confirm_idle() {
                state.set_print_state(PrintState::Idle, None, None);
            }
            return;
        }
    };
    // The first M27 after M601 can still report printing because the firmware has not
    // parked yet, so a reply while online must not clear the flag. Two cases do clear
    // it. A pause that already took effect and was then resumed from the printer menu
    // shows as Paused here. A reply while the state is still Offline is the first one
    // after a reconnect, and a print that reports printing right then is not paused,
    // which also covers an M601 that was lost when the link dropped.
    state.clear_pause_if_paused_or_offline();
    if state.expire_unconfirmed_pause(Instant::now(), PAUSE_CONFIRM_LIMIT) {
        warn!(
            "printer: still printing {} s after a pause request, the M601 got lost",
            PAUSE_CONFIRM_LIMIT.as_secs()
        );
    }
    let completion = if total == 0 {
        0.0
    } else {
        100.0 * done as f64 / total as f64
    };
    state.set_print_state(PrintState::Printing, Some(completion), Some(done));
}

/// The write half of the serial link. A write is bounded because it can hang for minutes on a
/// half-open TCP link.
struct Serial {
    wr: OwnedWriteHalf,
    terminal: Terminal,
}

impl Serial {
    async fn write(&mut self, bytes: &[u8]) -> io::Result<()> {
        timeout(IO_TIMEOUT, self.wr.write_all(bytes))
            .await
            .unwrap_or_else(|_| Err(io::ErrorKind::TimedOut.into()))
    }

    async fn send(&mut self, line: &str) -> io::Result<()> {
        self.terminal.mirror(line);
        self.write(format!("{line}\n").as_bytes()).await
    }
}

/// One line of serial traffic for the Obico terminal.
pub struct TerminalLine {
    pub msg: String,
    /// Unix time in seconds, which is what the Obico terminal expects.
    pub ts: f64,
}

/// Mirrors the serial traffic to the Obico terminal. Lines are only queued while the terminal
/// wants them, so the bounded channel cannot fill up otherwise, and a full channel drops the
/// line because a terminal that lags is not worth stalling the printer link for.
#[derive(Clone)]
struct Terminal {
    state: Arc<AppState>,
    tx: mpsc::Sender<TerminalLine>,
}

impl Terminal {
    /// Mirrors a line from the firmware. OctoPrint leaves out the "wait" idle messages.
    fn received(&self, line: &str) {
        if line.eq_ignore_ascii_case("wait") {
            return;
        }
        self.mirror(line);
    }

    fn mirror(&self, line: &str) {
        let line = line.trim();
        if line.is_empty() || !self.state.terminal_feed_wanted() {
            return;
        }
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0.0, |d| d.as_secs_f64());
        let _ = self.tx.try_send(TerminalLine {
            msg: line.to_string(),
            ts,
        });
    }
}

/// Lines of the firmware and of the ffmpeg log are short, so anything longer is line noise and must
/// not grow the buffer. A stream without a newline would otherwise be buffered without bound.
pub const MAX_LINE: usize = 1024;

/// The longest G-code line passed through to the firmware. The Prusa MK3 firmware has MAX_CMD_SIZE
/// of 96 but ends a line when 95 bytes are stored and drops the byte that follows, so a line past
/// 95 bytes is refused up front. The read buffer limit above is for lines read, not sent.
pub const MAX_GCODE_LINE: usize = 95;

/// Splits a byte stream into lines without ever holding more than `MAX_LINE` bytes.
pub(crate) struct LineReader<R> {
    rd: R,
    buf: Vec<u8>,
    discarding: bool,
}

impl<R: AsyncBufRead + Unpin> LineReader<R> {
    pub(crate) fn new(rd: R) -> Self {
        Self {
            rd,
            buf: Vec::new(),
            discarding: false,
        }
    }

    /// Returns None at end of stream. An over-long line is skipped and a
    /// non-UTF-8 byte is replaced, so neither can end the session. All state
    /// lives in the struct, which keeps this safe to cancel in a select.
    pub(crate) async fn next_line(&mut self) -> io::Result<Option<String>> {
        loop {
            let available = self.rd.fill_buf().await?;
            if available.is_empty() {
                return Ok(None);
            }
            let end = available.iter().position(|&b| b == b'\n');
            let chunk = available
                .get(..end.unwrap_or(available.len()))
                .unwrap_or_default();
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

/// What the bridge sends on every connect. The G90 that repairs a jog cut short by a lost link is
/// not part of it, see `restore_absolute_mode`.
const CONNECT_LINES: [&str; 2] = ["M115", "M155 S2"];

/// Lines that are queued behind each other must not overrun the firmware, so each one waits for the
/// ok of the previous. Homing blocks the ok until it finishes, which is why the limit is generous.
/// A wait for temperature blocks it for longer, but the firmware reports progress meanwhile and
/// each report restarts the limit, so it only counts a silence. A lost ok then costs one limit of
/// stalled commands and not a wedged bridge.
const OK_TIMEOUT: Duration = Duration::from_secs(60);

/// Whether the line is a progress report of M109 or M190, which the firmware prints while it blocks
/// on a temperature. M109 prints "T:x E:0 W:y" and M190 prints "T:x E:0 B:y", so the E field is
/// what they share and what the autoreport lacks.
fn is_temperature_wait(line: &str) -> bool {
    line.starts_with("T:") && line.contains(" E:")
}

/// Whether the firmware acknowledged the last line. Temperature replies carry the ok as prefix.
/// The ok has to be a word of its own, because M27 prints the name of the file first and a file
/// named okapi.gcode would otherwise ack the line early on every poll.
fn is_ok(line: &str) -> bool {
    line == "ok" || line.starts_with("ok ")
}

/// A line waiting for the serial link. A kept line survives an overdue ok.
struct Queued {
    line: String,
    keep: bool,
}

/// The lines waiting for the serial link, of which at most one is in flight. Every write goes
/// through here, the periodic M27 poll included, because the firmware acknowledges lines in order
/// and a second sender would make the oks impossible to attribute. A command stays behind the
/// earlier one until its ok arrives, which also keeps the printer task from taking new commands
/// while lines are pending.
struct Flow {
    pending: VecDeque<Queued>,
    /// Since when the line in flight waits for its ok.
    in_flight: Option<Instant>,
}

impl Flow {
    fn new() -> Self {
        Self {
            pending: VecDeque::new(),
            in_flight: None,
        }
    }

    fn push(&mut self, line: impl Into<String>) {
        self.pending.push_back(Queued {
            line: line.into(),
            keep: false,
        });
    }

    /// Queues a line that survives an overdue ok.
    fn push_kept(&mut self, line: impl Into<String>) {
        self.pending.push_back(Queued {
            line: line.into(),
            keep: true,
        });
    }

    /// Queues the lines that set up the connection, which must not be lost to a slow reply.
    fn push_connect(&mut self) {
        for line in CONNECT_LINES {
            self.push_kept(line);
        }
    }

    /// Queues the lines of a command. The trailing G90 of a jog is kept, because it is the only
    /// line that switches the firmware back from relative mode.
    fn push_command(&mut self, cmd: &Command) {
        for line in cmd.gcode() {
            if matches!(cmd, Command::Jog(_)) && line == "G90" {
                self.push_kept(line);
            } else {
                self.push(line);
            }
        }
    }

    fn busy(&self) -> bool {
        self.in_flight.is_some() || !self.pending.is_empty()
    }

    /// Returns the next line to write, unless one still waits for its ok.
    fn next(&mut self, now: Instant) -> Option<String> {
        if self.in_flight.is_some() {
            return None;
        }
        let queued = self.pending.pop_front()?;
        self.in_flight = Some(now);
        Some(queued.line)
    }

    fn acked(&mut self) {
        self.in_flight = None;
    }

    /// Restarts the wait for the ok of the line in flight, for a firmware that shows it is alive.
    fn extend(&mut self, now: Instant) {
        if let Some(since) = self.in_flight.as_mut() {
            *since = now;
        }
    }

    /// Drops the lines that are not kept when the ok is overdue and returns whether it did.
    fn expire(&mut self, now: Instant, limit: Duration) -> bool {
        let Some(since) = self.in_flight else {
            return false;
        };
        if now.duration_since(since) <= limit {
            return false;
        }
        // Lines marked as kept stay. A jog's G90 is the only thing that switches back from
        // relative mode, and the connect lines set up autoreport, so a slow reply must not lose
        // either. Other queued lines can go. An expiry also happens during a print and must not
        // send a stray G90 that nobody queued.
        self.pending.retain(|q| q.keep);
        self.in_flight = None;
        true
    }

    fn clear(&mut self) {
        self.pending.clear();
        self.in_flight = None;
    }
}

pub struct Printer {
    addr: String,
    state: Arc<AppState>,
    rx: mpsc::Receiver<Command>,
    terminal: Terminal,
}

impl Printer {
    pub fn new(
        addr: String,
        state: Arc<AppState>,
        rx: mpsc::Receiver<Command>,
        terminal: mpsc::Sender<TerminalLine>,
    ) -> Self {
        let terminal = Terminal {
            state: state.clone(),
            tx: terminal,
        };
        Self {
            addr,
            state,
            rx,
            terminal,
        }
    }

    pub async fn run(self) {
        self.supervise().await
    }

    fn handle_line(&self, flow: &mut Flow, line: &str) {
        if apply_host_action(&self.state, line) {
            // The print state stays Printing until the next M27, and a Pause in that window
            // would pass both gates and send M601 to an idle printer. Commands wait behind
            // the queued M27, so they see the fresh state.
            if line.parse::<HostAction>() == Ok(HostAction::Cancel) {
                flow.push("M27");
            }
            return;
        }
        if let Ok(firmware) = line.parse::<Firmware>() {
            self.state.set_firmware(firmware);
            return;
        }
        // The M190 report has T and B fields but no targets, so parsing it as temperatures would
        // zero the reported targets once a second until the next autoreport.
        if is_temperature_wait(line) {
            return;
        }
        if let Ok(temps) = line.parse::<Temps>() {
            self.state.set_temps(temps);
            // A temperature line never carries M27 state, whether autoreport or "ok T:" reply,
            // so parsing stops here.
            return;
        }
        if let Ok(m27) = line.parse::<M27>() {
            apply_m27(m27, &self.state);
            return;
        }
        if line == "ok" {
            trace!("printer: ok");
            return;
        }
        debug!("printer: unhandled line: {line}");
    }

    /// A link lost in the middle of a jog, after its G91, leaves the firmware in relative mode, so
    /// each session sends one G90. It waits until an M27 of this session reads as idle, because a
    /// reconnect can land inside a G91 section of a running print file, where a G90 would turn the
    /// later relative moves absolute and drive the nozzle into the print. Jogs only run while idle,
    /// so the repair is not late for them, and the flow holds back commands until the line leaves.
    fn restore_absolute_mode(&self, flow: &mut Flow, pending: &mut bool) {
        if !*pending || self.state.with(|s| s.print_state) != PrintState::Idle {
            return;
        }
        flow.push_kept("G90");
        *pending = false;
    }

    /// The reset also dropped whatever the firmware had not answered yet. A reset right after
    /// connect can swallow the M115 as well, so the whole connect sequence is queued again and not
    /// only the autoreport. The print state stays Printing until the next M27, and commands wait
    /// behind the queued one for the same reason as after a host cancel.
    fn handle_reset(&self, flow: &mut Flow) {
        self.state.withdraw_print_requests();
        flow.clear();
        flow.push_connect();
        flow.push("M27");
    }

    /// Updates the request flags and queues the lines of a command, followed by an M27 that
    /// refreshes the print state right away instead of waiting for the next poll. The dispatcher
    /// gated the command on the print state, but the flow can stay busy for a minute before the
    /// command leaves the queue, so the gate is checked again here. A Pause is dropped when the
    /// print ended or paused since, because an M601 on an idle printer would make the firmware
    /// report a pause that never happened. A Home or Jog is dropped unless the printer is idle,
    /// and a Resume unless it is paused, because either would act on a print that moved on. A
    /// Cancel is dropped when no print is running or paused, because an M603 would then cancel
    /// nothing and its request flag would stay set.
    fn accept_command(&self, flow: &mut Flow, cmd: Command) {
        if matches!(cmd, Command::Pause) && !self.state.confirm_pause() {
            debug!("printer: dropping a pause because no print is running");
            return;
        }
        let print_state = self.state.with(|s| s.print_state);
        if matches!(cmd, Command::Home(_) | Command::Jog(_)) && print_state != PrintState::Idle {
            debug!(
                "printer: dropping a {} because the printer is not idle",
                cmd.name()
            );
            return;
        }
        if matches!(cmd, Command::Resume) && print_state != PrintState::Paused {
            debug!("printer: dropping a resume because the print is not paused");
            return;
        }
        if matches!(cmd, Command::Cancel)
            && !matches!(print_state, PrintState::Printing | PrintState::Paused)
        {
            debug!("printer: dropping a cancel because no print is running");
            self.state.withdraw_cancel();
            return;
        }
        // The pause flag stays until the host action line of the firmware confirms the resume or
        // cancel. The print is still paused if the link dies first or M602 refuses to resume on a
        // thermal or fan error, and the action line arrives before the ok and the M27 behind it.
        flow.push_command(&cmd);
        flow.push("M27");
    }

    /// Talks to the printer until the link ends and returns why it did. `up_since` is set once
    /// the firmware has sent a line.
    async fn serve(
        &mut self,
        stream: TcpStream,
        up_since: &mut Option<Instant>,
    ) -> io::Result<String> {
        let (rd, wr) = stream.into_split();
        let mut serial = Serial {
            wr,
            terminal: self.terminal.clone(),
        };
        let mut lines = LineReader::new(BufReader::new(rd));
        // Commands queued while the link was down are stale and get dropped.
        while let Ok(cmd) = self.rx.try_recv() {
            if matches!(cmd, Command::Pause) {
                self.state.withdraw_pause();
            }
        }
        // A leading newline flushes any partial line left in the firmware buffer.
        serial.write(b"\n").await?;
        let mut flow = Flow::new();
        flow.push_connect();
        let mut absolute_mode_pending = true;
        // ser2net accepts the connection even when the printer is off, so only a
        // line from the firmware proves the link is up.
        let mut poll = interval(POLL_INTERVAL);
        let mut last_rx = Instant::now();
        loop {
            if let Some(line) = flow.next(Instant::now()) {
                serial.send(&line).await?;
            }
            tokio::select! {
                line = lines.next_line() => {
                    let Some(line) = line? else { return Ok("closed by peer".into()) };
                    if up_since.is_none() {
                        info!("printer connected");
                        self.state.set_printer_connected();
                        *up_since = Some(Instant::now());
                    }
                    last_rx = Instant::now();
                    let line = line.trim();
                    self.terminal.received(line);
                    // The ok check comes first because an ok can carry a temperature report.
                    if is_ok(line) {
                        flow.acked();
                    }
                    // A blocking temperature wait prints these reports instead of an ok, and it
                    // can outlast the ok limit.
                    if is_temperature_wait(line) {
                        flow.extend(Instant::now());
                    }
                    if line == "start" {
                        info!("printer reset detected, repeating the connect lines");
                        self.handle_reset(&mut flow);
                        continue;
                    }
                    self.handle_line(&mut flow, line);
                    self.restore_absolute_mode(&mut flow, &mut absolute_mode_pending);
                }
                // New commands wait while lines are pending, so the queue stays short and a
                // cancel does not overtake the lines of an earlier command.
                cmd = self.rx.recv(), if !flow.busy() => {
                    let Some(cmd) = cmd else { return Ok("command channel closed".into()) };
                    self.accept_command(&mut flow, cmd);
                }
                _ = poll.tick() => {
                    if last_rx.elapsed() > SILENCE_LIMIT {
                        return Ok(format!("no data for {} s", SILENCE_LIMIT.as_secs()));
                    }
                    if flow.expire(Instant::now(), OK_TIMEOUT) {
                        warn!("printer: no ok within {} s, dropping the queued lines", OK_TIMEOUT.as_secs());
                    }
                    // A pending command ends with its own M27, so the poll only fills idle time.
                    if !flow.busy() {
                        flow.push("M27");
                    }
                }
            }
        }
    }
}

impl Link for Printer {
    type Conn = TcpStream;
    const NAME: &'static str = "printer";
    // ser2net accepts while the printer is off, so only a session that got a firmware line
    // counts as a working link, and any such session resets the delay. Resetting after the
    // connect would keep the retries of a dead printer at the minimum delay.
    const STABLE_AFTER: Duration = Duration::ZERO;

    async fn connect(&mut self) -> Result<TcpStream> {
        timeout(IO_TIMEOUT, TcpStream::connect(&self.addr))
            .await
            .map_err(|_| anyhow!("connect timed out"))?
            .with_context(|| format!("cannot connect to {}", self.addr))
    }

    async fn session(&mut self, stream: TcpStream) -> Ended {
        let mut up_since = None;
        let reason = match self.serve(stream, &mut up_since).await {
            Ok(reason) => reason,
            Err(e) => e.to_string(),
        };
        self.state.set_printer_offline();
        Ended {
            reason,
            up_for: up_since.map(|at| at.elapsed()),
        }
    }
}

#[cfg(test)]
#[path = "tests/printer.rs"]
mod tests;
