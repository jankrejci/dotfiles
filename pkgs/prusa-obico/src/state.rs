use std::collections::BTreeMap;
use std::sync::atomic::AtomicU64;
use std::sync::{Arc, RwLock};
use std::time::{Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::Notify;

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

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Temps {
    pub tool_actual: f64,
    pub tool_target: f64,
    pub bed_actual: f64,
    pub bed_target: f64,
}

#[derive(Clone, Debug)]
pub struct SnapshotInfo {
    pub at: i64,
    pub ok: bool,
    pub detail: String,
}

#[derive(Clone, Debug)]
pub struct Inner {
    pub printer_connected: bool,
    pub firmware: Option<String>,
    pub obico_connected: bool,
    pub print_state: PrintState,
    pub pause_requested: bool,
    pub temps: Option<Temps>,
    pub completion: Option<f64>,
    pub filepos: Option<u64>,
    pub current_print_ts: i64,
    pub viewing: bool,
    pub last_snapshot: Option<SnapshotInfo>,
    pub last_snapshot_success: Option<i64>,
    pub snapshot_failures: u64,
    pub last_command: Option<(String, i64)>,
    pub commands: BTreeMap<String, u64>,
    pub status_messages: u64,
}

/// Everything the tasks share. Locks are never held across an await.
pub struct AppState {
    inner: RwLock<Inner>,
    /// Wakes the Obico task for an immediate status message.
    pub changed: Notify,
    pub started: Instant,
    /// Bumped by the supervisor loop and checked by the watchdog task.
    pub tick: AtomicU64,
}

impl AppState {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: RwLock::new(Inner {
                printer_connected: false,
                firmware: None,
                obico_connected: false,
                print_state: PrintState::Offline,
                pause_requested: false,
                temps: None,
                completion: None,
                filepos: None,
                current_print_ts: -1,
                viewing: false,
                last_snapshot: None,
                last_snapshot_success: None,
                snapshot_failures: 0,
                last_command: None,
                commands: BTreeMap::new(),
                status_messages: 0,
            }),
            changed: Notify::new(),
            started: Instant::now(),
            tick: AtomicU64::new(0),
        })
    }

    pub fn snapshot(&self) -> Inner {
        self.inner.read().unwrap().clone()
    }

    pub fn update<R>(&self, f: impl FnOnce(&mut Inner) -> R) -> R {
        f(&mut self.inner.write().unwrap())
    }

    pub fn set_printer_connected(&self) {
        // The print state stays Offline until the first M27 reply tells what the printer
        // is really doing, otherwise a running print would flash as Idle.
        self.update(|s| s.printer_connected = true);
        self.changed.notify_one();
    }

    pub fn set_printer_offline(&self) {
        self.update(|s| {
            s.printer_connected = false;
            s.print_state = PrintState::Offline;
            s.pause_requested = false;
            s.temps = None;
            s.completion = None;
            s.filepos = None;
        });
        self.changed.notify_one();
    }

    /// Applies a new print state and keeps `current_print_ts` consistent with it.
    pub fn set_print_state(&self, new: PrintState, completion: Option<f64>, filepos: Option<u64>) {
        let changed = self.update(|s| {
            let old = s.print_state;
            s.print_state = new;
            match new {
                PrintState::Paused => {
                    if completion.is_some() {
                        s.completion = completion;
                        s.filepos = filepos;
                    }
                }
                _ => {
                    s.completion = completion;
                    s.filepos = filepos;
                }
            }
            // The timestamp survives a printer link drop so Obico sees the same print after
            // a reconnect. A bridge restart still starts a new print in Obico because the
            // timestamp lives only in memory.
            if matches!(new, PrintState::Printing | PrintState::Paused) && s.current_print_ts == -1
            {
                s.current_print_ts = unix_now();
            }
            if new == PrintState::Idle {
                s.current_print_ts = -1;
            }
            old != new
        });
        if changed {
            self.changed.notify_one();
        }
    }

    pub fn record_command(&self, name: &str) {
        self.update(|s| {
            *s.commands.entry(name.to_string()).or_insert(0) += 1;
            s.last_command = Some((name.to_string(), unix_now()));
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reconnect_stays_offline_until_first_state() {
        let state = AppState::new();
        state.set_printer_connected();
        assert_eq!(state.snapshot().print_state, PrintState::Offline);
        state.set_print_state(PrintState::Idle, None, None);
        assert_eq!(state.snapshot().print_state, PrintState::Idle);
    }

    #[test]
    fn print_timestamp_survives_a_link_drop() {
        let state = AppState::new();
        state.set_print_state(PrintState::Printing, Some(10.0), Some(1));
        let ts = state.snapshot().current_print_ts;
        assert_ne!(ts, -1);
        state.set_printer_offline();
        assert_eq!(state.snapshot().current_print_ts, ts);
        state.set_print_state(PrintState::Printing, Some(20.0), Some(2));
        assert_eq!(state.snapshot().current_print_ts, ts);
        state.set_print_state(PrintState::Paused, None, None);
        assert_eq!(state.snapshot().current_print_ts, ts);
    }

    #[test]
    fn print_timestamp_resets_when_idle() {
        let state = AppState::new();
        state.set_print_state(PrintState::Printing, Some(10.0), Some(1));
        state.set_print_state(PrintState::Idle, None, None);
        assert_eq!(state.snapshot().current_print_ts, -1);
    }
}
