mod backoff;
mod http;
mod obico;
mod printer;
mod snapshot;
mod state;

use clap::Parser;
use state::AppState;
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::atomic::Ordering;
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::task::JoinSet;
use tracing::{error, info, warn};
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(version, about = "Bridge a Prusa MK3S serial link to the Obico cloud")]
struct Args {
    /// TCP endpoint carrying the raw 115200 baud serial line, as host:port.
    #[arg(long, env = "PRUSA_OBICO_PRINTER")]
    printer: String,

    #[arg(long, env = "PRUSA_OBICO_URL", default_value = "https://app.obico.io")]
    obico_url: String,

    /// File holding the Obico printer auth token.
    #[arg(long, env = "PRUSA_OBICO_TOKEN_FILE")]
    token_file: PathBuf,

    /// Video stream used to grab snapshots for AI failure detection.
    #[arg(long, env = "PRUSA_OBICO_VIDEO_URL")]
    video_url: Option<String>,

    #[arg(long, env = "PRUSA_OBICO_FFMPEG", default_value = "ffmpeg")]
    ffmpeg: String,

    /// Address for the /status and /metrics HTTP endpoints.
    #[arg(long, env = "PRUSA_OBICO_LISTEN", default_value = "127.0.0.1:9188")]
    listen: String,
}

#[tokio::main]
async fn main() -> ExitCode {
    tracing_subscriber::fmt()
        .without_time()
        .with_ansi(false)
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();
    let args = Args::parse();
    // Both TLS stacks need an explicit provider because no default is compiled in.
    let _ = rustls::crypto::ring::default_provider().install_default();

    if let Err(e) = obico::read_token(&args.token_file) {
        error!("{e}");
        return ExitCode::FAILURE;
    }
    let listener = match tokio::net::TcpListener::bind(&args.listen).await {
        Ok(l) => l,
        Err(e) => {
            error!("cannot bind {}: {e}", args.listen);
            return ExitCode::FAILURE;
        }
    };
    info!("listening on {}", args.listen);

    let state = AppState::new();
    let (tx, rx) = mpsc::channel(16);
    let mut tasks = JoinSet::new();
    tasks.spawn({
        let state = state.clone();
        async move {
            http::serve(listener, state)
                .await
                .map_err(|e| format!("http server: {e}"))
        }
    });
    tasks.spawn({
        let (state, addr) = (state.clone(), args.printer.clone());
        async move {
            printer::run(addr, state, rx).await;
            Ok(())
        }
    });
    tasks.spawn({
        let state = state.clone();
        let cfg = obico::Config {
            url: args.obico_url.clone(),
            token_file: args.token_file.clone(),
        };
        async move {
            obico::run(cfg, state, tx).await;
            Ok(())
        }
    });
    tasks.spawn({
        let state = state.clone();
        let cfg = snapshot::Config {
            obico_url: args.obico_url.clone(),
            token_file: args.token_file.clone(),
            video_url: args.video_url.clone(),
            ffmpeg: args.ffmpeg.clone(),
        };
        async move {
            snapshot::run(cfg, state).await;
            Ok(())
        }
    });

    // Ready means the listener is bound, the upstream links reconnect on their own.
    let _ = sd_notify::notify(&[sd_notify::NotifyState::Ready]);

    if let Some(interval) = sd_notify::watchdog_enabled() {
        let state = state.clone();
        let period = interval / 2;
        tokio::spawn(async move {
            let mut seen = u64::MAX;
            let mut ticker = tokio::time::interval(period);
            loop {
                ticker.tick().await;
                let now = state.tick.load(Ordering::Relaxed);
                if now == seen {
                    warn!("supervisor loop stalled, withholding watchdog");
                    continue;
                }
                seen = now;
                let _ = sd_notify::notify(&[sd_notify::NotifyState::Watchdog]);
            }
        });
    }

    let mut heartbeat = tokio::time::interval(Duration::from_secs(1));
    let mut sigterm = match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
    {
        Ok(s) => s,
        Err(e) => {
            error!("cannot install SIGTERM handler: {e}");
            return ExitCode::FAILURE;
        }
    };
    loop {
        tokio::select! {
            _ = heartbeat.tick() => {
                state.tick.fetch_add(1, Ordering::Relaxed);
            }
            _ = sigterm.recv() => {
                info!("terminating");
                return ExitCode::SUCCESS;
            }
            // Any task ending is a bug, so exit and let systemd restart the service.
            done = tasks.join_next() => {
                error!("task ended unexpectedly: {done:?}");
                return ExitCode::FAILURE;
            }
        }
    }
}
