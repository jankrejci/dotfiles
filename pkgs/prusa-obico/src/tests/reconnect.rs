//! Tests of the reconnect delay and logging policy.

use super::{Ended, Outages, Report};
use anyhow::{anyhow, Result};
use std::time::Duration;

const STABLE: Duration = Duration::from_secs(60);

fn up(secs: u64) -> Result<Ended> {
    Ok(Ended {
        reason: "dropped".into(),
        up_for: Some(Duration::from_secs(secs)),
    })
}

fn never_up() -> Result<Ended> {
    Ok(Ended {
        reason: "silent".into(),
        up_for: None,
    })
}

fn refused() -> Result<Ended> {
    Err(anyhow!("refused"))
}

#[test]
fn startup_failure_logs_once() {
    let mut outages = Outages::new();
    let (first, _) = outages.record(refused(), STABLE);
    assert_eq!(first, Some(Report::Failed("refused".into())));
    let (second, _) = outages.record(refused(), STABLE);
    assert_eq!(second, None);
    let (third, _) = outages.record(refused(), STABLE);
    assert_eq!(third, None);
}

#[test]
fn disconnect_logs_and_silences_the_repeated_retries_after_it() {
    let mut outages = Outages::new();
    let (report, _) = outages.record(up(5), STABLE);
    assert_eq!(report, Some(Report::Disconnected("dropped".into())));
    let (report, _) = outages.record(refused(), STABLE);
    assert_eq!(report, Some(Report::Failed("refused".into())));
    let (report, _) = outages.record(refused(), STABLE);
    assert_eq!(report, None);
    let (report, _) = outages.record(up(5), STABLE);
    assert_eq!(report, Some(Report::Disconnected("dropped".into())));
}

#[test]
fn delay_resets_only_after_a_stable_session() {
    let mut outages = Outages::new();
    let delays: Vec<u64> = (0..3)
        .map(|_| outages.record(up(59), STABLE).1.as_secs())
        .collect();
    assert_eq!(delays, [1, 2, 4]);
    let (_, delay) = outages.record(up(60), STABLE);
    assert_eq!(delay.as_secs(), 1);
}

#[test]
fn a_session_that_never_came_up_keeps_backing_off() {
    let mut outages = Outages::new();
    let delays: Vec<u64> = (0..3)
        .map(|_| outages.record(never_up(), Duration::ZERO).1.as_secs())
        .collect();
    assert_eq!(delays, [1, 2, 4]);
}

#[test]
fn zero_stable_limit_resets_on_any_up_session() {
    let mut outages = Outages::new();
    outages.record(refused(), Duration::ZERO);
    outages.record(refused(), Duration::ZERO);
    let (_, delay) = outages.record(up(0), Duration::ZERO);
    assert_eq!(delay.as_secs(), 1);
}

#[test]
fn a_new_failure_reason_in_the_same_outage_is_logged() {
    let mut outages = Outages::new();
    let (report, _) = outages.record(refused(), STABLE);
    assert_eq!(report, Some(Report::Failed("refused".into())));
    let (report, _) = outages.record(Err(anyhow!("401 Unauthorized")), STABLE);
    assert_eq!(report, Some(Report::Failed("401 Unauthorized".into())));
    let (report, _) = outages.record(Err(anyhow!("401 Unauthorized")), STABLE);
    assert_eq!(report, None);
    let (report, _) = outages.record(refused(), STABLE);
    assert_eq!(report, Some(Report::Failed("refused".into())));
}
