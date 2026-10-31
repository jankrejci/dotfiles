use std::time::Duration;

const MIN: Duration = Duration::from_secs(1);
const MAX: Duration = Duration::from_secs(60);

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
#[path = "tests/backoff.rs"]
mod tests;
