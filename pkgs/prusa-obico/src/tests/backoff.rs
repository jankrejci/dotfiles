//! Tests of the reconnect delay.

use super::Backoff;

#[test]
fn doubles_and_caps() {
    let mut b = Backoff::new();
    let delays: Vec<u64> = (0..8).map(|_| b.next_delay().as_secs()).collect();
    assert_eq!(delays, [1, 2, 4, 8, 16, 32, 60, 60]);
    b.reset();
    assert_eq!(b.next_delay().as_secs(), 1);
}
