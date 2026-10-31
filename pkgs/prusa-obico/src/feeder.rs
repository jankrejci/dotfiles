use crate::backoff::Backoff;
use crate::ffmpeg::Input;
use crate::printer::LineReader;
use crate::state::AppState;
use anyhow::{Context, Result};
use std::process::Stdio;
use std::sync::{Arc, Mutex, PoisonError};
use std::time::{Duration, Instant};
use tokio::io::BufReader;
use tokio::process::Child;
use tokio::time::sleep_until;
use tracing::{debug, info, warn};

/// Viewers reload and reconnect often, so the feed outlives the last one briefly.
const GRACE: Duration = Duration::from_secs(30);

/// A feeder that stayed up this long had a working camera, so its next failure starts a new outage
/// with the shortest delay again. Without it a camera that drops once a day would back off for
/// good while somebody watches.
const STABLE_RUN: Duration = Duration::from_secs(60);

/// ffmpeg can print very long lines, and the journal needs only the start of them.
const MAX_LOG_CHARS: usize = 200;

fn clip(line: &str) -> String {
    line.chars().take(MAX_LOG_CHARS).collect()
}

/// Runs the ffmpeg feeder that copies the camera stream to Janus while someone watches.
pub struct Feeder {
    input: Input,
    rtp_port: u16,
    state: Arc<AppState>,
    child: Option<Child>,
    started: Option<Instant>,
    /// The last line ffmpeg printed, which names the cause when it exits.
    stderr_tail: Arc<Mutex<String>>,
    last_viewed: Option<Instant>,
    was_viewing: bool,
    backoff: Backoff,
    retry_at: Instant,
    /// One line per outage. A feeder that keeps crashing must not flood the journal.
    failure_logged: bool,
}

impl Feeder {
    pub fn new(input: Input, rtp_port: u16, state: Arc<AppState>) -> Self {
        Self {
            input,
            rtp_port,
            state,
            child: None,
            started: None,
            stderr_tail: Arc::default(),
            last_viewed: None,
            was_viewing: false,
            backoff: Backoff::new(),
            retry_at: Instant::now(),
            failure_logged: false,
        }
    }

    /// The feed runs while someone watches and for a grace period afterwards.
    fn wanted(&self, viewing: bool, now: Instant) -> bool {
        viewing || self.last_viewed.is_some_and(|t| now < t + GRACE)
    }

    /// The time the loop must wake at without a state change, which is the end of the grace
    /// period or the moment a failed feeder may start again.
    fn wake_at(&self, viewing: bool, now: Instant) -> Option<Instant> {
        if !self.wanted(viewing, now) {
            return None;
        }
        let grace_end = self.last_viewed.filter(|_| !viewing).map(|t| t + GRACE);
        let retry = (self.child.is_none() && self.retry_at > now).then_some(self.retry_at);
        [grace_end, retry].into_iter().flatten().min()
    }

    fn spawn(&self) -> Result<Child> {
        let mut child = self
            .input
            .command()
            .args(["-c:v", "copy", "-an", "-f", "rtp"])
            .arg(format!("rtp://127.0.0.1:{}?pkt_size=1300", self.rtp_port))
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            // A dying bridge must not leave a feeder streaming to nobody.
            .kill_on_drop(true)
            .spawn()
            .context("cannot run ffmpeg")?;
        if let Some(stderr) = child.stderr.take() {
            let tail = self.stderr_tail.clone();
            tokio::spawn(async move {
                let mut lines = LineReader::new(BufReader::new(stderr));
                while let Ok(Some(line)) = lines.next_line().await {
                    let line = clip(&line);
                    debug!("stream ffmpeg: {line}");
                    *tail.lock().unwrap_or_else(PoisonError::into_inner) = line;
                }
            });
        }
        Ok(child)
    }

    /// Resolves when the feeder exits and never while there is none.
    async fn exited(&mut self) {
        match self.child.as_mut() {
            Some(running) => {
                let _ = running.wait().await;
            }
            None => std::future::pending().await,
        }
    }

    /// Books the end of a feeder run and schedules the next start.
    fn on_exit(&mut self, now: Instant, exit: &str) {
        if self
            .started
            .is_some_and(|at| now.duration_since(at) >= STABLE_RUN)
        {
            self.backoff.reset();
            self.failure_logged = false;
        }
        if !self.failure_logged {
            let last = self
                .stderr_tail
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            warn!("stream feed ended: {exit}, last ffmpeg line: {last}");
            self.failure_logged = true;
        }
        self.child = None;
        self.started = None;
        self.state.set_stream_active(false);
        self.retry_at = now + self.backoff.next_delay();
    }

    /// Brings the feeder in line with what the viewers want right now.
    async fn step(&mut self, viewing: bool, now: Instant) {
        if !self.wanted(viewing, now) {
            self.backoff.reset();
            self.failure_logged = false;
            self.started = None;
            let Some(mut running) = self.child.take() else {
                return;
            };
            info!("nobody watching, stopping the stream feed");
            let _ = running.kill().await;
            self.state.set_stream_active(false);
            return;
        }
        if let Some(running) = self.child.as_mut() {
            let exit = match running.try_wait() {
                Ok(None) => return,
                Ok(Some(status)) => status.to_string(),
                Err(e) => e.to_string(),
            };
            self.on_exit(now, &exit);
            return;
        }
        if now < self.retry_at {
            return;
        }
        self.stderr_tail = Arc::default();
        match self.spawn() {
            Ok(c) => {
                info!("starting the stream feed");
                self.child = Some(c);
                self.started = Some(now);
                self.state.set_stream_active(true);
            }
            Err(e) => {
                if !self.failure_logged {
                    warn!("stream feed failed: {e:#}");
                    self.failure_logged = true;
                }
                self.retry_at = now + self.backoff.next_delay();
            }
        }
    }

    pub async fn run(mut self) {
        let mut changes = self.state.subscribe();
        loop {
            let now = Instant::now();
            let viewing = changes.borrow_and_update().viewing;
            // The grace period starts at the first look after the last viewer left.
            if viewing || self.was_viewing {
                self.last_viewed = Some(now);
            }
            self.was_viewing = viewing;
            self.step(viewing, now).await;
            let deadline = self.wake_at(viewing, now);
            tokio::select! {
                changed = changes.changed() => {
                    if changed.is_err() {
                        return;
                    }
                }
                _ = async {
                    match deadline {
                        Some(at) => sleep_until(at.into()).await,
                        None => std::future::pending().await,
                    }
                } => {}
                _ = self.exited() => {}
            }
        }
    }
}

#[cfg(test)]
#[path = "tests/feeder.rs"]
mod tests;
