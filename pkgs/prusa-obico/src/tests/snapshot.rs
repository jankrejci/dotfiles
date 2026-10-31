//! Tests of the snapshot interval and outcome recording.

use super::{snapshot_interval, tail, Snapshotter, ACTIVE_INTERVAL, IDLE_INTERVAL};
use crate::ffmpeg::Input;
use crate::state::{AppState, PrintState};
use anyhow::anyhow;

#[test]
fn tail_keeps_the_end_on_a_char_boundary() {
    assert_eq!(tail("short", 1024), "short");
    assert_eq!(tail("abcdef", 3), "def");
    // The cut would fall inside the two byte character, so it moves forward.
    assert_eq!(tail("aéb", 2), "b");
}

fn test_snapshotter() -> Snapshotter {
    let input = Input {
        ffmpeg: "ffmpeg".into(),
        url: "http://camera.invalid/video".into(),
    };
    Snapshotter::new(
        "https://obico.invalid".parse().unwrap(),
        "token".into(),
        input,
        AppState::new(None),
    )
    .unwrap()
}

#[test]
fn interval_is_short_while_printing_or_watched() {
    let state = AppState::new(None);
    assert_eq!(snapshot_interval(&state.read()), IDLE_INTERVAL);
    state.set_viewing(true);
    assert_eq!(snapshot_interval(&state.read()), ACTIVE_INTERVAL);
    state.set_viewing(false);
    state.set_print_state(PrintState::Printing, Some(1.0), Some(1));
    assert_eq!(snapshot_interval(&state.read()), ACTIVE_INTERVAL);
}

#[test]
fn record_counts_failures_and_remembers_success() {
    let mut snapshotter = test_snapshotter();
    snapshotter.record(Err(anyhow!("camera down")));
    let s = snapshotter.state.read();
    assert_eq!(s.snapshot_failures, 1);
    assert!(s.last_snapshot_success.is_none());
    assert_eq!(s.last_snapshot.as_ref().unwrap().detail, "camera down");
    drop(s);
    snapshotter.record(Ok("200 OK".into()));
    let s = snapshotter.state.read();
    assert!(s.last_snapshot_success.is_some());
    assert!(s.last_snapshot.as_ref().unwrap().ok);
}
