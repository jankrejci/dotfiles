use std::time::Duration;

const MIN: Duration = Duration::from_secs(1);
const MAX: Duration = Duration::from_secs(60);
/// A server that accepts and then drops the socket would otherwise be retried every
/// second forever, so the delay only resets after a session that stayed up this long.
pub const STABLE_AFTER: Duration = Duration::from_secs(60);

/// Exponential reconnect delay from one to sixty seconds.
pub struct Backoff(Duration);

impl Backoff {
    pub fn new() -> Self {
        Self(MIN)
    }

    pub fn reset(&mut self) {
        self.0 = MIN;
    }

    /// Returns the delay to wait now and doubles it for the next failure.
    pub fn next_delay(&mut self) -> Duration {
        let current = self.0;
        self.0 = (self.0 * 2).min(MAX);
        current
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn doubles_and_caps() {
        let mut b = Backoff::new();
        let delays: Vec<u64> = (0..8).map(|_| b.next_delay().as_secs()).collect();
        assert_eq!(delays, [1, 2, 4, 8, 16, 32, 60, 60]);
        b.reset();
        assert_eq!(b.next_delay().as_secs(), 1);
    }
}
