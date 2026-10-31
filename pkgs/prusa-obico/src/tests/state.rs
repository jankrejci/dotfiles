//! Tests of the shared state transitions and notifications.

use super::{AppState, PrintState};
use crate::marlin::{Reading, Temps};
use std::fs;

#[test]
fn reconnect_stays_offline_until_first_state() {
    let state = AppState::new(None);
    state.set_printer_connected();
    assert_eq!(state.read().print_state, PrintState::Offline);
    state.set_print_state(PrintState::Idle, None, None);
    assert_eq!(state.read().print_state, PrintState::Idle);
}

#[test]
fn print_timestamp_survives_a_link_drop() {
    let state = AppState::new(None);
    state.set_print_state(PrintState::Printing, Some(10.0), Some(1));
    let ts = state.read().current_print_ts;
    assert!(ts.is_some());
    state.set_printer_offline();
    assert_eq!(state.read().current_print_ts, ts);
    state.set_print_state(PrintState::Printing, Some(20.0), Some(2));
    assert_eq!(state.read().current_print_ts, ts);
    state.set_print_state(PrintState::Paused, None, None);
    assert_eq!(state.read().current_print_ts, ts);
}

#[test]
fn pause_survives_a_link_drop() {
    let state = AppState::new(None);
    state.set_print_state(PrintState::Printing, Some(10.0), Some(1));
    state.request_pause();
    state.set_print_state(PrintState::Paused, None, None);
    state.set_printer_offline();
    assert_eq!(state.read().print_state, PrintState::Offline);
    assert!(state.read().pause_requested());
}

#[test]
fn pause_clears_only_while_paused_or_offline() {
    let state = AppState::new(None);
    state.set_print_state(PrintState::Printing, Some(10.0), Some(1));
    state.request_pause();
    state.clear_pause_if_paused_or_offline();
    assert!(state.read().pause_requested());
    state.set_print_state(PrintState::Paused, None, None);
    state.clear_pause_if_paused_or_offline();
    assert!(!state.read().pause_requested());
}

#[test]
fn pause_flag_persists_in_the_state_directory() {
    let dir = std::env::temp_dir().join(format!("prusa-obico-test-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let state = AppState::new(Some(dir.clone()));
    assert!(!state.read().pause_requested());
    state.request_pause();
    assert!(AppState::new(Some(dir.clone())).read().pause_requested());
    state.withdraw_pause();
    assert!(!AppState::new(Some(dir.clone())).read().pause_requested());
    fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn cancel_request_clears_when_idle_or_offline() {
    let state = AppState::new(None);
    state.set_print_state(PrintState::Printing, Some(10.0), Some(1));
    state.request_cancel();
    state.set_print_state(PrintState::Printing, Some(20.0), Some(2));
    assert!(state.read().cancel_requested);
    state.set_print_state(PrintState::Idle, None, None);
    assert!(!state.read().cancel_requested);
    state.request_cancel();
    state.set_printer_offline();
    assert!(!state.read().cancel_requested);
}

#[test]
fn offline_notifies_only_on_a_change() {
    let state = AppState::new(None);
    let mut rx = state.subscribe();
    state.set_printer_offline();
    assert!(!rx.has_changed().unwrap());
    state.set_printer_connected();
    // Mark the connect as seen so only the offline call is measured.
    rx.borrow_and_update();
    state.set_printer_offline();
    assert!(rx.has_changed().unwrap());
}

#[test]
fn quiet_updates_do_not_wake_watchers() {
    let state = AppState::new(None);
    let rx = state.subscribe();
    state.count_status_message();
    assert!(!rx.has_changed().unwrap());
    assert_eq!(rx.borrow().status_messages, 1);
    state.set_viewing(true);
    assert!(rx.has_changed().unwrap());
}

#[test]
fn print_timestamp_resets_when_idle() {
    let state = AppState::new(None);
    state.set_print_state(PrintState::Printing, Some(10.0), Some(1));
    state.set_print_state(PrintState::Idle, None, None);
    assert_eq!(state.read().current_print_ts, None);
}

#[test]
fn temps_serialize_in_the_octoprint_shape() {
    let temps = Temps {
        tool: Reading {
            actual: 215.3,
            target: 215.0,
        },
        bed: Reading {
            actual: 60.1,
            target: 60.0,
        },
    };
    assert_eq!(
        serde_json::to_value(temps).unwrap(),
        serde_json::json!({
            "tool0": {"actual": 215.3, "target": 215.0},
            "bed": {"actual": 60.1, "target": 60.0}
        })
    );
}

#[test]
fn concurrent_pause_updates_keep_the_marker_in_step_with_the_flag() {
    let dir = std::env::temp_dir().join(format!("prusa-obico-race-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let state = AppState::new(Some(dir.clone()));
    let threads: Vec<_> = (0..4)
        .map(|n| {
            let state = state.clone();
            std::thread::spawn(move || {
                for i in 0..200 {
                    state.set_pause_requested((i + n) % 3 != 0);
                }
            })
        })
        .collect();
    for t in threads {
        t.join().unwrap();
    }
    assert_eq!(
        dir.join("pause_requested").exists(),
        state.read().pause_requested()
    );
    fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn an_unreadable_marker_location_counts_as_no_pause() {
    let file = std::env::temp_dir().join(format!("prusa-obico-file-{}", std::process::id()));
    fs::write(&file, b"").unwrap();
    // A file in place of the directory makes the marker check fail with an error.
    let state = AppState::new(Some(file.clone()));
    assert!(!state.read().pause_requested());
    fs::remove_file(&file).unwrap();
}

#[test]
fn link_loss_latches_only_when_a_print_was_running() {
    let state = AppState::new(None);
    state.set_printer_connected();
    state.set_print_state(PrintState::Idle, None, None);
    state.set_printer_offline();
    assert!(!state.read().link_lost_during_print);

    for running in [PrintState::Printing, PrintState::Paused] {
        state.set_printer_connected();
        state.set_print_state(running, Some(1.0), Some(1));
        state.set_printer_offline();
        assert!(state.read().link_lost_during_print, "{running:?}");
        // Every failed retry calls this again and must not lose the latch.
        state.set_printer_offline();
        assert!(state.read().link_lost_during_print);
        state.set_printer_connected();
        assert!(state.read().link_lost_during_print);
        state.set_print_state(PrintState::Idle, None, None);
        assert!(!state.read().link_lost_during_print);
    }
}

#[test]
fn link_loss_survives_a_second_drop_before_the_first_state() {
    let state = AppState::new(None);
    state.set_printer_connected();
    state.set_print_state(PrintState::Printing, Some(1.0), Some(1));
    state.set_printer_offline();
    state.set_printer_connected();
    state.set_printer_offline();
    assert!(state.read().link_lost_during_print);
    state.set_printer_connected();
    assert!(state.read().link_lost_during_print);
    state.set_print_state(PrintState::Printing, Some(2.0), Some(2));
    assert!(!state.read().link_lost_during_print);
}
