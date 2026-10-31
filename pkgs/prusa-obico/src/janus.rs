use crate::reconnect::{self, Ended, Link};
use crate::state::AppState;
use crate::ws::Ws;
use anyhow::{Context, Result};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use tokio::time::interval;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::handshake::client::Request;
use tokio_tungstenite::tungstenite::http::HeaderValue;
use tokio_tungstenite::tungstenite::Message;
use tracing::info;

/// Janus refuses websocket clients that do not announce its protocol.
const SUBPROTOCOL: &str = "janus-protocol";
/// The bridge sends its own websocket pings because Janus session keepalives come from the
/// Obico web client and stop whenever nobody watches the stream.
const PING_INTERVAL: Duration = Duration::from_secs(10);
/// Any received frame counts as life. Janus answers each ping with a pong, so the limit spans
/// several ping intervals and silence beyond it means a dead link.
const SILENCE_LIMIT: Duration = Duration::from_secs(30);

pub struct Janus {
    url: String,
    state: Arc<AppState>,
    from_obico: mpsc::Receiver<String>,
    to_obico: mpsc::Sender<String>,
}

impl Janus {
    pub fn new(
        url: String,
        state: Arc<AppState>,
        from_obico: mpsc::Receiver<String>,
        to_obico: mpsc::Sender<String>,
    ) -> Self {
        Self {
            url,
            state,
            from_obico,
            to_obico,
        }
    }

    pub async fn run(self) {
        self.supervise().await
    }

    fn request(&self) -> Result<Request> {
        let mut request = self
            .url
            .as_str()
            .into_client_request()
            .context("invalid Janus URL")?;
        request.headers_mut().insert(
            "sec-websocket-protocol",
            HeaderValue::from_static(SUBPROTOCOL),
        );
        Ok(request)
    }
}

impl Link for Janus {
    type Conn = Ws;
    const NAME: &'static str = "Janus";
    const STABLE_AFTER: Duration = reconnect::STABLE_AFTER;

    async fn connect(&mut self) -> Result<Ws> {
        let request = self.request()?;
        Ws::connect(request).await
    }

    async fn session(&mut self, mut ws: Ws) -> Ended {
        info!("Janus connected");
        let connected_at = Instant::now();
        // Signaling queued while Janus was down belongs to sessions that no longer exist.
        while self.from_obico.try_recv().is_ok() {}
        // Obico learns about the webcam from the settings that go out on this wakeup.
        self.state.set_janus_connected(true);
        let mut ping = interval(PING_INTERVAL);
        let mut last_rx = Instant::now();
        let reason = loop {
            tokio::select! {
                frame = ws.next() => {
                    let frame = match frame {
                        None => break "closed by peer".to_string(),
                        Some(Err(e)) => break e.to_string(),
                        Some(Ok(f)) => f,
                    };
                    last_rx = Instant::now();
                    match frame {
                        Message::Text(text) => {
                            // A full channel means Obico is gone or slow, stale signaling is useless.
                            let _ = self.to_obico.try_send(text.as_str().to_string());
                        }
                        Message::Close(frame) => break format!("closed by server: {frame:?}"),
                        _ => {}
                    }
                }
                raw = self.from_obico.recv() => {
                    let Some(raw) = raw else { break "signaling channel closed".to_string() };
                    if let Err(e) = ws.send(Message::Text(raw.into())).await {
                        break format!("{e:#}");
                    }
                }
                _ = ping.tick() => {
                    if last_rx.elapsed() > SILENCE_LIMIT {
                        break format!("no data for {} s", SILENCE_LIMIT.as_secs());
                    }
                    if let Err(e) = ws.ping().await {
                        break format!("{e:#}");
                    }
                }
            }
        };
        self.state.set_janus_connected(false);
        Ended {
            reason,
            up_for: Some(connected_at.elapsed()),
        }
    }
}
