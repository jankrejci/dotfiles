//! Tests of when the feeder runs and when it wakes.

use super::{clip, Feeder, GRACE, MAX_LOG_CHARS, STABLE_RUN};
use crate::ffmpeg::Input;
use crate::state::AppState;
use std::time::{Duration, Instant};

fn test_feeder() -> Feeder {
    let input = Input {
        ffmpeg: "ffmpeg".into(),
        url: "http://camera.invalid/video".into(),
    };
    Feeder::new(input, 17732, AppState::new(None))
}

#[test]
fn feed_follows_viewer_with_grace() {
    let mut feeder = test_feeder();
    let now = Instant::now();
    assert!(feeder.wanted(true, now));
    assert!(!feeder.wanted(false, now));
    feeder.last_viewed = Some(now);
    assert!(feeder.wanted(false, now + GRACE - Duration::from_secs(1)));
    assert!(!feeder.wanted(false, now + GRACE));
}

#[test]
fn wake_at_covers_grace_end_and_retry() {
    let mut feeder = test_feeder();
    let now = Instant::now();
    let later = now + Duration::from_secs(5);
    // Nothing to wait for while idle.
    feeder.retry_at = later;
    assert_eq!(feeder.wake_at(false, now), None);
    // A failed feeder under a viewer retries at its backoff time.
    feeder.last_viewed = Some(now);
    assert_eq!(feeder.wake_at(true, now), Some(later));
    // After the viewer left, the grace end comes first unless the retry is sooner.
    assert_eq!(feeder.wake_at(false, now), Some(later));
    feeder.retry_at = now;
    assert_eq!(feeder.wake_at(false, now), Some(now + GRACE));
    assert_eq!(feeder.wake_at(false, now + GRACE), None);
}

#[test]
fn a_long_run_resets_the_backoff_but_a_short_one_does_not() {
    let mut feeder = test_feeder();
    let now = Instant::now();
    // A crash loop doubles the delay.
    feeder.on_exit(now, "exit status: 1");
    feeder.on_exit(now, "exit status: 1");
    assert_eq!(feeder.retry_at, now + Duration::from_secs(2));
    feeder.started = Some(now);
    feeder.on_exit(now + STABLE_RUN - Duration::from_secs(1), "exit status: 1");
    assert_eq!(
        feeder.retry_at,
        now + STABLE_RUN - Duration::from_secs(1) + Duration::from_secs(4)
    );
    feeder.started = Some(now);
    feeder.on_exit(now + STABLE_RUN, "exit status: 1");
    assert_eq!(feeder.retry_at, now + STABLE_RUN + Duration::from_secs(1));
    assert!(feeder.started.is_none());
}

#[test]
fn log_lines_are_cut_to_a_fixed_length() {
    let long = "é".repeat(MAX_LOG_CHARS + 50);
    assert_eq!(clip(&long).chars().count(), MAX_LOG_CHARS);
    assert_eq!(clip("short"), "short");
}
