use crate::state::{unix_now, AppState, PrintState, SnapshotInfo};
use reqwest::multipart::{Form, Part};
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::process::Command;
use tokio::time::{interval, timeout};
use tracing::{debug, info, warn};

const ACTIVE_INTERVAL: Duration = Duration::from_secs(10);
const IDLE_INTERVAL: Duration = Duration::from_secs(120);
const CAPTURE_TIMEOUT: Duration = Duration::from_secs(20);

pub struct Config {
    pub obico_url: String,
    pub token_file: PathBuf,
    pub video_url: Option<String>,
    pub ffmpeg: String,
}

async fn capture(cfg: &Config, video_url: &str) -> Result<Vec<u8>, String> {
    let mut cmd = Command::new(&cfg.ffmpeg);
    cmd.args(["-nostdin", "-loglevel", "error", "-i", video_url])
        .args([
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
        .map_err(|_| format!("ffmpeg timed out after {} s", CAPTURE_TIMEOUT.as_secs()))?
        .map_err(|e| format!("cannot run ffmpeg: {e}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("ffmpeg {}: {}", output.status, stderr.trim()));
    }
    if output.stdout.is_empty() {
        return Err("ffmpeg produced no frame".into());
    }
    Ok(output.stdout)
}

async fn upload(
    client: &reqwest::Client,
    cfg: &Config,
    token: &str,
    jpeg: Vec<u8>,
    viewing: bool,
) -> Result<String, String> {
    let part = Part::bytes(jpeg)
        .file_name("snapshot.jpg")
        .mime_str("image/jpeg")
        .map_err(|e| e.to_string())?;
    let mut form = Form::new().part("pic", part);
    if viewing {
        form = form.text("viewing_boost", "true");
    }
    let url = format!("{}/api/v1/octo/pic/", cfg.obico_url.trim_end_matches('/'));
    let response = client
        .post(url)
        .header("Authorization", format!("Token {token}"))
        .multipart(form)
        .send()
        .await
        .map_err(|e| e.without_url().to_string())?;
    let status = response.status();
    if !status.is_success() {
        return Err(format!("upload rejected with {status}"));
    }
    Ok(status.to_string())
}

pub async fn run(cfg: Config, state: Arc<AppState>) {
    let Some(video_url) = cfg.video_url.clone() else {
        info!("no video URL configured, snapshots disabled");
        return std::future::pending().await;
    };
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
    {
        Ok(c) => c,
        Err(e) => {
            warn!("cannot build HTTP client, snapshots disabled: {e}");
            return std::future::pending().await;
        }
    };
    let mut tick = interval(Duration::from_secs(1));
    let mut last_attempt: Option<Instant> = None;
    let mut last_ok = true;
    loop {
        tick.tick().await;
        let s = state.snapshot();
        if !s.obico_connected {
            continue;
        }
        let active =
            matches!(s.print_state, PrintState::Printing | PrintState::Paused) || s.viewing;
        let wait = if active {
            ACTIVE_INTERVAL
        } else {
            IDLE_INTERVAL
        };
        if last_attempt.is_some_and(|t| t.elapsed() < wait) {
            continue;
        }
        last_attempt = Some(Instant::now());
        let result = async {
            let token = crate::obico::read_token(&cfg.token_file)?;
            let jpeg = capture(&cfg, &video_url).await?;
            debug!("captured {} byte frame", jpeg.len());
            upload(&client, &cfg, &token, jpeg, s.viewing).await
        }
        .await;
        let ok = result.is_ok();
        // Log only transitions so a dead camera does not flood the journal.
        match &result {
            Ok(_) if !last_ok => info!("snapshot upload recovered"),
            Err(e) if last_ok => warn!("snapshot failed: {e}"),
            Err(e) => debug!("snapshot failed: {e}"),
            Ok(_) => debug!("snapshot uploaded"),
        }
        last_ok = ok;
        let now = unix_now();
        state.update(|s| {
            s.last_snapshot = Some(SnapshotInfo {
                at: now,
                ok,
                detail: result.unwrap_or_else(|e| e),
            });
            if ok {
                s.last_snapshot_success = Some(now);
            } else {
                s.snapshot_failures += 1;
            }
        });
    }
}
