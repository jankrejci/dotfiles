use crate::backoff::{Backoff, STABLE_AFTER};
use crate::state::AppState;
use futures_util::{SinkExt, StreamExt};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use tokio::time::{sleep, timeout};
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::handshake::client::Request;
use tokio_tungstenite::tungstenite::http::HeaderValue;
use tokio_tungstenite::tungstenite::Message;
use tracing::{info, warn};

/// Janus refuses websocket clients that do not announce its protocol.
const SUBPROTOCOL: &str = "janus-protocol";
/// An unreachable gateway must fail the attempt instead of hanging the retry loop.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);

fn request(url: &str) -> Result<Request, String> {
    let mut request = url.into_client_request().map_err(|e| e.to_string())?;
    request.headers_mut().insert(
        "sec-websocket-protocol",
        HeaderValue::from_static(SUBPROTOCOL),
    );
    Ok(request)
}

async fn session(
    url: &str,
    state: &AppState,
    from_obico: &mut mpsc::Receiver<String>,
    to_obico: &mpsc::Sender<String>,
    on_connected: impl FnOnce(),
) -> Result<String, String> {
    let (mut ws, _) = timeout(
        CONNECT_TIMEOUT,
        tokio_tungstenite::connect_async(request(url)?),
    )
    .await
    .map_err(|_| "connect timed out".to_string())?
    .map_err(|e| e.to_string())?;
    on_connected();
    // Signaling queued while Janus was down belongs to sessions that no longer exist.
    while from_obico.try_recv().is_ok() {}
    state.update(|s| s.janus_connected = true);
    // Obico learns about the webcam from the settings that go out on this wakeup.
    state.changed.notify_one();
    let result = loop {
        tokio::select! {
            frame = ws.next() => {
                let frame = match frame {
                    None => break Ok("closed by peer".to_string()),
                    Some(Err(e)) => break Err(e.to_string()),
                    Some(Ok(f)) => f,
                };
                match frame {
                    Message::Text(text) => {
                        // A full channel means Obico is gone or slow, stale signaling is useless.
                        let _ = to_obico.try_send(text.as_str().to_string());
                    }
                    Message::Close(frame) => break Ok(format!("closed by server: {frame:?}")),
                    _ => {}
                }
            }
            raw = from_obico.recv() => {
                let Some(raw) = raw else { break Ok("signaling channel closed".to_string()) };
                if let Err(e) = ws.send(Message::Text(raw.into())).await {
                    break Err(e.to_string());
                }
            }
        }
    };
    state.update(|s| s.janus_connected = false);
    result
}

pub async fn run(
    url: String,
    state: Arc<AppState>,
    mut from_obico: mpsc::Receiver<String>,
    to_obico: mpsc::Sender<String>,
) {
    let mut backoff = Backoff::new();
    // Each outage logs one line: the failure at startup, the disconnect after
    // that. The flag never resets because every later outage begins with a
    // logged disconnect, and the retries that follow it stay quiet.
    let mut failure_logged = false;
    loop {
        let mut connected_at = None;
        let outcome = session(&url, &state, &mut from_obico, &to_obico, || {
            connected_at = Some(Instant::now());
            info!("Janus connected");
        })
        .await;
        let connected = connected_at.is_some();
        if connected_at.is_some_and(|at| at.elapsed() >= STABLE_AFTER) {
            backoff.reset();
        }
        match outcome {
            Ok(reason) | Err(reason) if connected => {
                warn!("Janus disconnected: {reason}");
                failure_logged = true;
            }
            Ok(reason) | Err(reason) => {
                if !failure_logged {
                    warn!("Janus connection to {url} failed: {reason}");
                    failure_logged = true;
                }
            }
        }
        sleep(backoff.next_delay()).await;
    }
}
