use crate::backoff::Backoff;
use anyhow::Result;
use std::time::Duration;
use tokio::time::sleep;
use tracing::warn;

/// A server that accepts and then drops the socket would otherwise be retried every
/// second forever, so the delay only resets after a session that stayed up this long.
pub const STABLE_AFTER: Duration = Duration::from_secs(60);

/// How a session ended.
pub struct Ended {
    pub reason: String,
    /// How long the link counted as up, or None when it never did. Connecting alone does not
    /// always make a link up, because a bridge can accept while the device behind it is off.
    pub up_for: Option<Duration>,
}

/// One upstream connection that the supervisor keeps alive.
pub trait Link: Sized {
    type Conn;
    const NAME: &'static str;
    /// Up time from which the next outage starts with the shortest delay again.
    const STABLE_AFTER: Duration;

    async fn connect(&mut self) -> Result<Self::Conn>;
    async fn session(&mut self, conn: Self::Conn) -> Ended;

    /// Keeps the link alive for the life of the process.
    async fn supervise(mut self) {
        let mut outages = Outages::new();
        loop {
            let outcome = match self.connect().await {
                Ok(conn) => Ok(self.session(conn).await),
                Err(e) => Err(e),
            };
            let (report, delay) = outages.record(outcome, Self::STABLE_AFTER);
            match report {
                Some(Report::Disconnected(reason)) => {
                    warn!("{} disconnected: {reason}", Self::NAME)
                }
                Some(Report::Failed(reason)) => {
                    warn!("{} connection failed: {reason}", Self::NAME)
                }
                None => {}
            }
            sleep(delay).await;
        }
    }
}

#[derive(Debug, PartialEq)]
enum Report {
    Disconnected(String),
    Failed(String),
}

/// The delay and logging policy between attempts.
struct Outages {
    backoff: Backoff,
    /// The last reason that was logged. Retries that fail for the same reason stay quiet, but a
    /// new reason within the same outage, such as a 401 after an expired token, is logged. It is
    /// never cleared because every later outage begins with a logged disconnect, which replaces it.
    last_logged: Option<String>,
}

impl Outages {
    fn new() -> Self {
        Self {
            backoff: Backoff::new(),
            last_logged: None,
        }
    }

    /// Returns what to log, if anything, and the delay before the next attempt.
    fn record(
        &mut self,
        outcome: Result<Ended>,
        stable_after: Duration,
    ) -> (Option<Report>, Duration) {
        let (reason, up_for) = match outcome {
            Ok(ended) => (ended.reason, ended.up_for),
            Err(e) => (format!("{e:#}"), None),
        };
        if up_for.is_some_and(|up| up >= stable_after) {
            self.backoff.reset();
        }
        let delay = self.backoff.next_delay();
        if up_for.is_some() {
            self.last_logged = Some(reason.clone());
            return (Some(Report::Disconnected(reason)), delay);
        }
        if self.last_logged.as_deref() == Some(reason.as_str()) {
            return (None, delay);
        }
        self.last_logged = Some(reason.clone());
        (Some(Report::Failed(reason)), delay)
    }
}

#[cfg(test)]
#[path = "tests/reconnect.rs"]
mod tests;
