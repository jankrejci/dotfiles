use crate::ffmpeg::Input;
use crate::obico::ObicoUrl;
use crate::state::{AppState, Inner, PrintState};
use anyhow::{anyhow, bail, Context, Result};
use reqwest::multipart::{Form, Part};
use std::process::Stdio;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::time::{sleep_until, timeout};
use tracing::{debug, info, warn};

const ACTIVE_INTERVAL: Duration = Duration::from_secs(10);
const IDLE_INTERVAL: Duration = Duration::from_secs(120);
const CAPTURE_TIMEOUT: Duration = Duration::from_secs(20);
const UPLOAD_TIMEOUT: Duration = Duration::from_secs(30);
/// ffmpeg can print a long error log and the last lines hold the cause.
const MAX_DETAIL: usize = 1024;

/// Returns at most the last `max` bytes of `s`, cut on a char boundary.
fn tail(s: &str, max: usize) -> &str {
    let mut start = s.len().saturating_sub(max);
    while !s.is_char_boundary(start) {
        start += 1;
    }
    s.get(start..).unwrap_or_default()
}

/// Snapshots go out faster while a print runs or someone watches.
fn snapshot_interval(s: &Inner) -> Duration {
    let active = matches!(s.print_state, PrintState::Printing | PrintState::Paused) || s.viewing;
    if active {
        return ACTIVE_INTERVAL;
    }
    IDLE_INTERVAL
}

/// Cuts frames from the video stream and uploads them to Obico for failure detection.
pub struct Snapshotter {
    obico_url: ObicoUrl,
    token: Arc<str>,
    input: Input,
    client: reqwest::Client,
    state: Arc<AppState>,
    last_ok: bool,
}

impl Snapshotter {
    /// Builds the HTTP client up front, because a client that cannot be built is a broken
    /// environment, not something to retry.
    pub fn new(
        obico_url: ObicoUrl,
        token: Arc<str>,
        input: Input,
        state: Arc<AppState>,
    ) -> Result<Self> {
        let client = reqwest::Client::builder()
            .timeout(UPLOAD_TIMEOUT)
            .build()
            .context("cannot build the HTTP client")?;
        Ok(Self {
            obico_url,
            token,
            input,
            client,
            state,
            last_ok: true,
        })
    }

    async fn capture(&self) -> Result<Vec<u8>> {
        let mut cmd = self.input.command();
        cmd.args([
            "-frames:v",
            "1",
            "-f",
            "image2",
            "-c:v",
            "mjpeg",
            "-q:v",
            "4",
            "pipe:1",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        // Dropping the future on timeout must not leave ffmpeg running.
        .kill_on_drop(true);
        let output = timeout(CAPTURE_TIMEOUT, cmd.output())
            .await
            .map_err(|_| anyhow!("ffmpeg timed out after {} s", CAPTURE_TIMEOUT.as_secs()))?
            .context("cannot run ffmpeg")?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            bail!(
                "ffmpeg {}: {}",
                output.status,
                tail(stderr.trim(), MAX_DETAIL)
            );
        }
        if output.stdout.is_empty() {
            bail!("ffmpeg produced no frame");
        }
        Ok(output.stdout)
    }

    async fn upload(&self, jpeg: Vec<u8>, viewing: bool) -> Result<String> {
        let part = Part::bytes(jpeg)
            .file_name("snapshot.jpg")
            .mime_str("image/jpeg")
            .context("invalid snapshot mime type")?;
        let mut form = Form::new().part("pic", part);
        if viewing {
            form = form.text("viewing_boost", "true");
        }
        let url = self.obico_url.endpoint("/api/v1/octo/pic/");
        let response = self
            .client
            .post(url)
            .header("Authorization", format!("Token {}", self.token))
            .multipart(form)
            .send()
            .await
            .map_err(|e| anyhow!(e.without_url().to_string()))
            .context("upload failed")?;
        let status = response.status();
        if !status.is_success() {
            bail!("upload rejected with {status}");
        }
        Ok(status.to_string())
    }

    async fn attempt(&self, viewing: bool) -> Result<String> {
        let jpeg = self.capture().await?;
        debug!("captured {} byte frame", jpeg.len());
        self.upload(jpeg, viewing).await
    }

    /// Logs transitions only, so a dead camera does not flood the journal, and records the
    /// outcome in the state.
    fn record(&mut self, result: Result<String>) {
        let ok = result.is_ok();
        match &result {
            Ok(_) if !self.last_ok => info!("snapshot upload recovered"),
            Err(e) if self.last_ok => warn!("snapshot failed: {e:#}"),
            Err(e) => debug!("snapshot failed: {e:#}"),
            Ok(_) => debug!("snapshot uploaded"),
        }
        self.last_ok = ok;
        self.state
            .record_snapshot(ok, result.unwrap_or_else(|e| format!("{e:#}")));
    }

    pub async fn run(mut self) {
        let mut changes = self.state.subscribe();
        let mut last_attempt: Option<Instant> = None;
        loop {
            let s = changes.borrow_and_update().clone();
            // Without Obico there is nobody to upload to, so only a state change can end the wait.
            if !s.obico_connected {
                if changes.changed().await.is_err() {
                    return;
                }
                continue;
            }
            // A state change can switch the interval, so the wait ends early and the loop looks again.
            if let Some(due) = last_attempt
                .map(|t| t + snapshot_interval(&s))
                .filter(|due| *due > Instant::now())
            {
                tokio::select! {
                    changed = changes.changed() => {
                        if changed.is_err() {
                            return;
                        }
                    }
                    _ = sleep_until(due.into()) => {}
                }
                continue;
            }
            let result = self.attempt(s.viewing).await;
            self.record(result);
            // Counted from the end, because a hanging camera takes longer than the interval to
            // time out and would otherwise be retried back to back.
            last_attempt = Some(Instant::now());
        }
    }
}

#[cfg(test)]
#[path = "tests/snapshot.rs"]
mod tests;
