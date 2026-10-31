//! Bridge between a Prusa MK3S serial link and the Obico cloud.
//!
//! Tests live next to their module as `#[cfg(test)] #[path = "tests/x.rs"] mod tests;`, a layout
//! that stays on purpose. They remain unit tests of a child module, so they reach private items
//! without widening visibility, and the production files stay short. The idiomatic `x/tests.rs`
//! would need a directory per module with nothing in it but the tests.

mod backoff;
mod feeder;
mod ffmpeg;
mod http;
mod janus;
mod janus_handles;
mod marlin;
mod obico;
mod printer;
mod reconnect;
mod snapshot;
mod state;
mod ws;

use anyhow::{bail, Context, Result};
use clap::Parser;
use feeder::Feeder;
use obico::ObicoUrl;
use snapshot::Snapshotter;
use state::AppState;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use tokio::task::JoinSet;
use tracing::{error, info, warn};
use tracing_subscriber::EnvFilter;

/// systemd separates several state directories with a colon and the first one is ours. Clap takes
/// a plain function as value parser, so this one stays free.
fn first_dir(value: &str) -> Result<PathBuf, String> {
    value
        .split(':')
        .next()
        .filter(|d| !d.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| "state directory is empty".to_string())
}

#[derive(Parser)]
#[command(version, about = "Bridge a Prusa MK3S serial link to the Obico cloud")]
struct Args {
    /// TCP endpoint carrying the raw 115200 baud serial line, as host:port. It stays a string
    /// because the host may be a name that only resolves when the bridge connects.
    #[arg(long, env = "PRUSA_OBICO_PRINTER")]
    printer: String,

    #[arg(long, env = "PRUSA_OBICO_URL", default_value = "https://app.obico.io")]
    obico_url: ObicoUrl,

    /// File holding the Obico printer auth token.
    #[arg(long, env = "PRUSA_OBICO_TOKEN_FILE")]
    token_file: PathBuf,

    /// Video stream used to grab snapshots for AI failure detection.
    #[arg(long, env = "PRUSA_OBICO_VIDEO_URL")]
    video_url: Option<String>,

    #[arg(long, env = "PRUSA_OBICO_FFMPEG", default_value = "ffmpeg")]
    ffmpeg: String,

    /// Address for the /status and /metrics HTTP endpoints. Both are unauthenticated, which is why
    /// the NixOS module binds them to localhost only and leaves access to a proxy.
    #[arg(long, env = "PRUSA_OBICO_LISTEN")]
    listen: SocketAddr,

    /// Websocket of the local Janus gateway that relays the live stream.
    #[arg(long, env = "PRUSA_OBICO_JANUS_WS")]
    janus_ws: String,

    /// Local UDP port where Janus expects the RTP feed.
    #[arg(long, env = "PRUSA_OBICO_RTP_PORT")]
    rtp_port: u16,

    /// Directory for the pause marker, which systemd provides as STATE_DIRECTORY.
    #[arg(long, env = "STATE_DIRECTORY", value_parser = first_dir)]
    state_directory: Option<PathBuf>,
}

impl Args {
    /// The file is a systemd credential copied at service start, so a rotated token needs a restart
    /// anyway and one read at startup is enough.
    fn read_token(&self) -> Result<Arc<str>> {
        let path = &self.token_file;
        let raw = std::fs::read_to_string(path)
            .with_context(|| format!("cannot read token file {}", path.display()))?;
        let token = raw.trim();
        if token.is_empty() {
            bail!("token file {} is empty", path.display());
        }
        Ok(token.into())
    }
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
    match run(args).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            error!("{e:#}");
            ExitCode::FAILURE
        }
    }
}

/// Starts the tasks and returns when the service is told to stop. Any failure to start, and any
/// task that ends, is an error.
async fn run(args: Args) -> Result<()> {
    // Both TLS stacks need an explicit provider because no default is compiled in.
    let _ = rustls::crypto::ring::default_provider().install_default();

    let token = args.read_token()?;
    let listener = tokio::net::TcpListener::bind(args.listen)
        .await
        .with_context(|| format!("cannot bind {}", args.listen))?;
    info!("listening on {}", args.listen);

    if args.state_directory.is_none() {
        warn!("STATE_DIRECTORY is not set, a pause will not survive a restart of the bridge");
    }
    let state = AppState::new(args.state_directory.clone());
    let (tx, rx) = mpsc::channel(16);
    let (to_janus, from_obico) = mpsc::channel(64);
    let (to_obico, from_janus) = mpsc::channel(64);
    let (to_terminal, from_printer) = mpsc::channel(64);
    let mut tasks = JoinSet::new();
    tasks.spawn({
        let state = state.clone();
        async move {
            http::Http::new(listener, state)
                .serve()
                .await
                .context("http server")
        }
    });
    tasks.spawn({
        let (state, addr) = (state.clone(), args.printer.clone());
        async move {
            printer::Printer::new(addr, state, rx, to_terminal)
                .run()
                .await;
            Ok(())
        }
    });
    tasks.spawn({
        let state = state.clone();
        let cfg = obico::Config {
            url: args.obico_url.clone(),
            token: token.clone(),
            has_video: args.video_url.is_some(),
        };
        async move {
            obico::Obico::new(cfg, state, tx, to_janus, from_janus, from_printer)
                .run()
                .await;
            Ok(())
        }
    });
    tasks.spawn({
        let (state, url) = (state.clone(), args.janus_ws.clone());
        async move {
            janus::Janus::new(url, state, from_obico, to_obico)
                .run()
                .await;
            Ok(())
        }
    });
    match args.video_url.clone() {
        None => info!("no video URL configured, snapshots and live stream disabled"),
        Some(url) => {
            let input = ffmpeg::Input {
                ffmpeg: args.ffmpeg.clone(),
                url,
            };
            let snapshotter = Snapshotter::new(
                args.obico_url.clone(),
                token.clone(),
                input.clone(),
                state.clone(),
            )?;
            tasks.spawn(async move {
                snapshotter.run().await;
                Ok(())
            });
            let feeder = Feeder::new(input, args.rtp_port, state.clone());
            tasks.spawn(async move {
                feeder.run().await;
                Ok(())
            });
        }
    }

    // Ready means the listener is bound. The upstream links reconnect on their own.
    let _ = sd_notify::notify(&[sd_notify::NotifyState::Ready]);

    // Petting from the main loop means a wedged runtime stops it and systemd restarts the service.
    let watchdog_period = sd_notify::watchdog_enabled().map(|interval| interval / 2);
    let mut last_pet = Instant::now();
    let mut heartbeat = tokio::time::interval(Duration::from_secs(1));
    let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        .context("cannot install SIGTERM handler")?;
    loop {
        tokio::select! {
            _ = heartbeat.tick() => {
                if watchdog_period.is_some_and(|period| last_pet.elapsed() >= period) {
                    let _ = sd_notify::notify(&[sd_notify::NotifyState::Watchdog]);
                    last_pet = Instant::now();
                }
            }
            _ = sigterm.recv() => {
                info!("terminating");
                return Ok(());
            }
            // A manual run ends with Ctrl-C. Returning drops the children, which kills ffmpeg.
            _ = tokio::signal::ctrl_c() => {
                info!("interrupted");
                return Ok(());
            }
            // Any task ending is a bug, so exit and let systemd restart the service.
            done = tasks.join_next() => bail!("task ended unexpectedly: {done:?}"),
        }
    }
}

#[cfg(test)]
#[path = "tests/main.rs"]
mod tests;
