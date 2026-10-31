use crate::marlin::{Firmware, Temps};
use serde::Serialize;
use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::watch;
use tracing::warn;

/// How many "Not SD printing" replies in a row end a running print, which at the five second poll
/// is about half a minute. Crash detection clears the SD printing flag while it homes X and Y and
/// only then resumes, so one such reply does not mean the print ended. The window is read from the
/// firmware source and not measured, so the value is a margin and not a known bound. The price is
/// that a print end reads as Printing for that long, and a Pause sent then reaches an idle printer.
const IDLE_CONFIRM_REPLIES: u32 = 6;

pub fn unix_now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PrintState {
    Offline,
    Idle,
    Printing,
    Paused,
}

impl PrintState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Offline => "offline",
            Self::Idle => "idle",
            Self::Printing => "printing",
            Self::Paused => "paused",
        }
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct SnapshotInfo {
    #[serde(rename = "timestamp")]
    pub at: i64,
    pub ok: bool,
    pub detail: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct LastCommand {
    pub cmd: String,
    pub timestamp: i64,
}

#[derive(Clone, Debug)]
pub struct Inner {
    pub(crate) printer_connected: bool,
    /// Latched when the serial link dropped during a print and cleared when the printer is back.
    /// Switching the printer off right after a print drops the link too, so only the bridge can
    /// tell a drop mid-print from a normal shutdown, and a later reading of the state cannot.
    pub(crate) link_lost_during_print: bool,
    pub(crate) firmware: Option<Firmware>,
    pub(crate) obico_connected: bool,
    pub(crate) print_state: PrintState,
    /// Private so that only the pause methods of `AppState` can change it, which keeps the marker
    /// file in step with the flag.
    pause_requested: bool,
    /// When the printer was last asked to pause, see `expire_unconfirmed_pause`. A flag restored
    /// from the marker file has none, and the first reply after the restart settles that one.
    pause_requested_at: Option<Instant>,
    /// Whether the requested pause reached the firmware or was already real. A "Not SD printing"
    /// reply only reads as paused after that, because the reply can also come from a running
    /// print, such as during crash detection homing. Reading it as paused before the M601 left
    /// the queue would make `confirm_pause` drop the M601, and the next printing reply would
    /// clear the flag of a pause that never happened.
    pause_sent: bool,
    /// "Not SD printing" replies since the last state change, see `IDLE_CONFIRM_REPLIES`.
    not_printing_replies: u32,
    /// Set when a cancel was sent. It is cleared when the printer reports idle, when the link
    /// drops, by `withdraw_print_requests` for a host cancel action or a printer reset, and by
    /// `withdraw_cancel` for a command that was refused or dropped.
    pub(crate) cancel_requested: bool,
    pub(crate) temps: Option<Temps>,
    pub(crate) completion: Option<f64>,
    pub(crate) filepos: Option<u64>,
    pub(crate) current_print_ts: Option<i64>,
    pub(crate) viewing: bool,
    /// Whether the Obico terminal asked for the serial traffic. It lives in memory only, like
    /// OctoPrint keeps it, and the terminal asks again when it opens.
    pub(crate) terminal_feed: bool,
    pub(crate) janus_connected: bool,
    pub(crate) stream_active: bool,
    pub(crate) last_snapshot: Option<SnapshotInfo>,
    pub(crate) last_snapshot_success: Option<i64>,
    pub(crate) snapshot_failures: u64,
    pub(crate) last_command: Option<LastCommand>,
    pub(crate) commands: BTreeMap<String, u64>,
    pub(crate) status_messages: u64,
}

impl Inner {
    pub fn pause_requested(&self) -> bool {
        self.pause_requested
    }

    /// Whether a requested pause reached the firmware, see `pause_sent`.
    pub fn pause_sent(&self) -> bool {
        self.pause_requested && self.pause_sent
    }
}

/// Everything the tasks share. Tasks that wait for a state change subscribe to the watch channel,
/// and writers wake them only for changes that a waiting task acts on.
pub struct AppState {
    inner: watch::Sender<Inner>,
    /// Marker file that carries `pause_requested` across a bridge restart. Absent when systemd
    /// provides no state directory.
    pause_file: Option<PathBuf>,
    pub started: Instant,
}

impl AppState {
    pub fn new(dir: Option<PathBuf>) -> Arc<Self> {
        let pause_file = dir.map(|d| d.join("pause_requested"));
        // A marker that cannot be checked counts as absent, but the log must say why a pause got
        // lost, so an error such as a permission problem does not pass silently.
        let pause_requested = pause_file.as_ref().is_some_and(|p| {
            p.try_exists().unwrap_or_else(|e| {
                warn!("cannot check the pause marker {}: {e}", p.display());
                false
            })
        });
        Arc::new(Self {
            pause_file,
            inner: watch::channel(Inner {
                printer_connected: false,
                link_lost_during_print: false,
                firmware: None,
                obico_connected: false,
                print_state: PrintState::Offline,
                pause_requested,
                pause_requested_at: None,
                // A restored marker belongs to a pause that was already sent before the restart.
                pause_sent: pause_requested,
                not_printing_replies: 0,
                cancel_requested: false,
                temps: None,
                completion: None,
                filepos: None,
                current_print_ts: None,
                viewing: false,
                terminal_feed: false,
                janus_connected: false,
                stream_active: false,
                last_snapshot: None,
                last_snapshot_success: None,
                snapshot_failures: 0,
                last_command: None,
                commands: BTreeMap::new(),
                status_messages: 0,
            })
            .0,
            started: Instant::now(),
        })
    }

    /// Returns a copy of the current state.
    pub fn read(&self) -> Inner {
        self.inner.borrow().clone()
    }

    pub fn subscribe(&self) -> watch::Receiver<Inner> {
        self.inner.subscribe()
    }

    /// Runs `f` on the current state without copying it, for reads of a single field.
    pub fn with<R>(&self, f: impl FnOnce(&Inner) -> R) -> R {
        f(&self.inner.borrow())
    }

    /// Mutates the state without waking watchers, for values that no task waits on.
    fn update_quiet(&self, f: impl FnOnce(&mut Inner)) {
        self.inner.send_if_modified(|s| {
            f(s);
            false
        });
    }

    /// Mutates the state and wakes watchers when `f` reports a change.
    fn update_notify(&self, f: impl FnOnce(&mut Inner) -> bool) {
        self.inner.send_if_modified(f);
    }

    /// The serial traffic only goes to Obico while its terminal asked for it and someone views.
    pub fn terminal_feed_wanted(&self) -> bool {
        let s = self.inner.borrow();
        s.terminal_feed && s.viewing
    }

    pub fn set_terminal_feed(&self, value: bool) {
        self.update_quiet(|s| s.terminal_feed = value);
    }

    pub fn set_viewing(&self, value: bool) {
        self.update_notify(|s| std::mem::replace(&mut s.viewing, value) != value);
    }

    pub fn set_obico_connected(&self, value: bool) {
        self.update_notify(|s| std::mem::replace(&mut s.obico_connected, value) != value);
    }

    pub fn set_janus_connected(&self, value: bool) {
        self.update_notify(|s| std::mem::replace(&mut s.janus_connected, value) != value);
    }

    /// Sets the pause flag and mirrors it to the marker file, so a bridge restart during a
    /// pause still tells the pause from idle. A printer that is power cycled while the bridge is
    /// down leaves the marker behind, because nobody sees its start line. A print resumed or
    /// cancelled from the printer menu while the link is down leaves the same marker, because
    /// the host action line is never seen. The idle printer then reads as paused until a cancel
    /// from Obico clears the marker.
    fn set_pause_requested(&self, value: bool) {
        self.update_quiet(|s| self.write_pause(s, value));
    }

    /// Marks a Pause as requested. The dispatcher calls this and not the printer task, because
    /// commands from one Obico message are dispatched back to back, before the printer task
    /// runs, and a second Pause in the same message must already see the flag.
    pub fn request_pause(&self) {
        self.set_pause_requested(true);
    }

    /// Marks a pause that the firmware announced, unless no print is running. An M601 on an idle
    /// printer also makes the firmware announce a pause, and that one must not turn idle into
    /// paused. The check and the write share one update, like in `confirm_pause`.
    pub fn request_pause_if_printing(&self) {
        self.update_quiet(|s| {
            if s.print_state == PrintState::Printing {
                self.write_pause(s, true);
                s.pause_sent = true;
            }
        });
    }

    /// Ends the pause request, for a resume the firmware announced, or a Pause that never reached
    /// the printer. A Pause counts as lost when the command queue was full, and when the queue was
    /// flushed after a link drop, so the flag set at dispatch time must not outlive it.
    pub fn withdraw_pause(&self) {
        self.set_pause_requested(false);
    }

    /// Sets the pause flag to whether a print is running. The printer task calls it when the
    /// Pause leaves the queue, because the print can have ended or paused in the meantime, and
    /// the state is read inside the same update that writes the flag. A print that paused in the
    /// meantime keeps the flag, because that pause is real and only this one is redundant. Returns
    /// whether the print was running, so the caller can skip an M601 that would pause nothing.
    pub fn confirm_pause(&self) -> bool {
        let mut printing = false;
        self.update_quiet(|s| {
            printing = s.print_state == PrintState::Printing;
            if s.print_state != PrintState::Paused {
                self.write_pause(s, printing);
            }
            // A kept flag is now either on its way to the firmware or a pause that is real.
            s.pause_sent = s.pause_requested;
            // The firmware only gets the M601 now, and the line can have waited behind others.
            if printing {
                s.pause_requested_at = Some(Instant::now());
            }
        });
        printing
    }

    /// Ends a pause that a running print ignored for longer than `limit` and returns whether it
    /// did. An M601 can get lost when an overdue ok drops the queue, and the flag would then refuse
    /// every later Pause and turn the end of the print into a pause that never happened. A print
    /// that ends within the limit still reads as paused, which only a cancel clears.
    pub fn expire_unconfirmed_pause(&self, now: Instant, limit: Duration) -> bool {
        let mut expired = false;
        self.update_quiet(|s| {
            let overdue = s
                .pause_requested_at
                .is_some_and(|at| now.duration_since(at) > limit);
            if s.pause_requested && overdue && s.print_state == PrintState::Printing {
                self.write_pause(s, false);
                expired = true;
            }
        });
        expired
    }

    /// Marks a Cancel as requested, set at dispatch time for the same reason as the pause flag.
    pub fn request_cancel(&self) {
        self.update_quiet(|s| s.cancel_requested = true);
    }

    pub fn withdraw_cancel(&self) {
        self.update_quiet(|s| s.cancel_requested = false);
    }

    /// Ends both requests, for the host action of a cancel and for a printer reset. A reset ends
    /// the print, so a remembered pause no longer applies. Both are proof that the print is over,
    /// so the next "Not SD printing" reply reads as idle without the wait of `confirm_idle`.
    pub fn withdraw_print_requests(&self) {
        self.withdraw_pause();
        self.withdraw_cancel();
        self.update_quiet(|s| s.not_printing_replies = IDLE_CONFIRM_REPLIES);
    }

    /// Counts a "Not SD printing" reply and returns whether it means idle. Only a running print
    /// has to wait, because a reply after a reconnect or in another state has nothing to hold on to.
    pub fn confirm_idle(&self) -> bool {
        let mut confirmed = true;
        self.update_quiet(|s| {
            if s.print_state != PrintState::Printing {
                return;
            }
            s.not_printing_replies = s.not_printing_replies.saturating_add(1);
            confirmed = s.not_printing_replies >= IDLE_CONFIRM_REPLIES;
        });
        confirmed
    }

    /// Clears the pause flag while the print state is Paused or Offline. The check and the clear
    /// share one update, so a pause that the dispatcher requests in between is not lost.
    pub fn clear_pause_if_paused_or_offline(&self) {
        self.update_quiet(|s| {
            if matches!(s.print_state, PrintState::Paused | PrintState::Offline) {
                self.write_pause(s, false);
            }
        });
    }

    fn write_pause(&self, s: &mut Inner, value: bool) {
        // The marker changes together with the flag inside one update, so two concurrent calls
        // cannot leave the file and the flag disagreeing. No fsync, because the flag only
        // matters across a bridge restart and the file lives in the page cache until then.
        // The blocking file call under the watch lock is accepted. It touches one empty file and
        // only when the flag changes, and moving it out of the update would lose the agreement
        // between file and flag.
        if std::mem::replace(&mut s.pause_requested, value) == value {
            return;
        }
        // A new request has not reached the firmware yet, and an ended one has nothing to send.
        s.pause_sent = false;
        s.pause_requested_at = value.then(Instant::now);
        let Some(path) = &self.pause_file else {
            return;
        };
        let result = if value {
            fs::write(path, b"")
        } else {
            fs::remove_file(path).or_else(|e| match e.kind() {
                io::ErrorKind::NotFound => Ok(()),
                _ => Err(e),
            })
        };
        if let Err(e) = result {
            warn!("cannot persist the pause flag to {}: {e}", path.display());
        }
    }

    pub fn set_printer_connected(&self) {
        // The print state stays Offline until the first M27 reply tells what the printer
        // is really doing, otherwise a running print would flash as Idle.
        self.update_notify(|s| !std::mem::replace(&mut s.printer_connected, true));
    }

    pub fn set_printer_offline(&self) {
        // The pause flag survives the drop. A paused SD print answers M27 with "Not SD
        // printing" on firmware 3.9.3 and with "SD print paused" from 3.10.1 on, so on older
        // firmware the flag is the only way to tell a pause from idle after the link returns.
        // A printer reset clears it separately.
        // A session that never saw a firmware line calls this on every retry, and it must
        // not wake the watchers for a status that did not change.
        self.update_notify(|s| {
            let was_online = s.printer_connected
                || s.print_state != PrintState::Offline
                || s.temps.is_some()
                || s.completion.is_some()
                || s.filepos.is_some();
            if matches!(s.print_state, PrintState::Printing | PrintState::Paused) {
                s.link_lost_during_print = true;
            }
            s.printer_connected = false;
            s.print_state = PrintState::Offline;
            s.cancel_requested = false;
            s.temps = None;
            s.completion = None;
            s.filepos = None;
            was_online
        });
    }

    /// Applies a new print state and keeps `current_print_ts` consistent with it.
    pub fn set_print_state(&self, new: PrintState, completion: Option<f64>, filepos: Option<u64>) {
        self.update_notify(|s| {
            let old = s.print_state;
            s.print_state = new;
            s.not_printing_replies = 0;
            // The latch ends only once a reply shows the printer state again. A second drop
            // before the first M27 reply finds the state Offline and could not latch anew.
            if new != PrintState::Offline {
                s.link_lost_during_print = false;
            }
            // A paused print reports no progress, so the last known values stay.
            if new != PrintState::Paused || completion.is_some() {
                s.completion = completion;
                s.filepos = filepos;
            }
            // The timestamp survives a printer link drop so Obico sees the same print after
            // a reconnect. A bridge restart still starts a new print in Obico because the
            // timestamp lives only in memory.
            if matches!(new, PrintState::Printing | PrintState::Paused)
                && s.current_print_ts.is_none()
            {
                s.current_print_ts = Some(unix_now());
            }
            if new == PrintState::Idle {
                s.current_print_ts = None;
                s.cancel_requested = false;
            }
            old != new
        });
    }

    pub fn record_command(&self, name: &str) {
        self.update_quiet(|s| {
            *s.commands.entry(name.to_string()).or_insert(0) += 1;
            s.last_command = Some(LastCommand {
                cmd: name.to_string(),
                timestamp: unix_now(),
            });
        });
    }

    pub fn set_firmware(&self, firmware: Firmware) {
        self.update_quiet(|s| s.firmware = Some(firmware));
    }

    pub fn set_temps(&self, temps: Temps) {
        self.update_quiet(|s| s.temps = Some(temps));
    }

    pub fn set_stream_active(&self, value: bool) {
        self.update_quiet(|s| s.stream_active = value);
    }

    pub fn count_status_message(&self) {
        self.update_quiet(|s| s.status_messages += 1);
    }

    /// Records the outcome of a snapshot upload, with `detail` holding the status or the error.
    pub fn record_snapshot(&self, ok: bool, detail: String) {
        let now = unix_now();
        self.update_quiet(|s| {
            s.last_snapshot = Some(SnapshotInfo {
                at: now,
                ok,
                detail,
            });
            if ok {
                s.last_snapshot_success = Some(now);
            } else {
                s.snapshot_failures += 1;
            }
        });
    }
}

#[cfg(test)]
#[path = "tests/state.rs"]
mod tests;
