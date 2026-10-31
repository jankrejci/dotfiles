use crate::backoff::Backoff;
use crate::state::AppState;
use std::process::Stdio;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{Child, Command};
use tokio::time::interval;
use tracing::{info, warn};

/// Viewers reload and reconnect often, so the feed outlives the last one briefly.
const GRACE: Duration = Duration::from_secs(30);

pub struct Config {
    pub video_url: Option<String>,
    pub ffmpeg: String,
    pub rtp_port: u16,
}

/// The feed runs while someone watches and for a grace period afterwards.
fn wanted(viewing: bool, last_viewed: Option<Instant>, now: Instant) -> bool {
    viewing || last_viewed.is_some_and(|t| now < t + GRACE)
}

fn spawn(cfg: &Config, video_url: &str) -> Result<Child, String> {
    let mut child = Command::new(&cfg.ffmpeg)
        .args(["-nostdin", "-loglevel", "error", "-i", video_url])
        .args(["-c:v", "copy", "-an", "-f", "rtp"])
        .arg(format!("rtp://127.0.0.1:{}?pkt_size=1300", cfg.rtp_port))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        // A dying bridge must not leave a feeder streaming to nobody.
        .kill_on_drop(true)
        .spawn()
        .map_err(|e| format!("cannot run ffmpeg: {e}"))?;
    if let Some(stderr) = child.stderr.take() {
        tokio::spawn(async move {
            let mut lines = BufReader::new(stderr).lines();
            while let Ok(Some(line)) = lines.next_line().await {
                warn!("stream ffmpeg: {line}");
            }
        });
    }
    Ok(child)
}

pub async fn run(cfg: Config, state: Arc<AppState>) {
    let Some(video_url) = cfg.video_url.clone() else {
        info!("no video URL configured, live stream disabled");
        return std::future::pending().await;
    };
    let mut child: Option<Child> = None;
    let mut last_viewed: Option<Instant> = None;
    let mut backoff = Backoff::new();
    let mut retry_at = Instant::now();
    // One line per outage, a feeder that keeps crashing must not flood the journal.
    let mut failure_logged = false;
    let mut tick = interval(Duration::from_secs(1));
    loop {
        tick.tick().await;
        let now = Instant::now();
        let viewing = state.snapshot().viewing;
        if viewing {
            last_viewed = Some(now);
        }
        if !wanted(viewing, last_viewed, now) {
            backoff.reset();
            failure_logged = false;
            let Some(mut running) = child.take() else {
                continue;
            };
            info!("nobody watching, stopping the stream feed");
            let _ = running.kill().await;
            state.update(|s| s.stream_active = false);
            continue;
        }
        if let Some(running) = child.as_mut() {
            let exit = match running.try_wait() {
                Ok(None) => continue,
                Ok(Some(status)) => status.to_string(),
                Err(e) => e.to_string(),
            };
            if !failure_logged {
                warn!("stream feed ended: {exit}");
                failure_logged = true;
            }
            child = None;
            state.update(|s| s.stream_active = false);
            retry_at = now + backoff.next_delay();
            continue;
        }
        if now < retry_at {
            continue;
        }
        match spawn(&cfg, &video_url) {
            Ok(c) => {
                info!("starting the stream feed");
                child = Some(c);
                state.update(|s| s.stream_active = true);
            }
            Err(e) => {
                if !failure_logged {
                    warn!("stream feed failed: {e}");
                    failure_logged = true;
                }
                retry_at = now + backoff.next_delay();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn feed_follows_viewer_with_grace() {
        let now = Instant::now();
        assert!(wanted(true, None, now));
        assert!(!wanted(false, None, now));
        assert!(wanted(
            false,
            Some(now),
            now + GRACE - Duration::from_secs(1)
        ));
        assert!(!wanted(false, Some(now), now + GRACE));
    }
}
