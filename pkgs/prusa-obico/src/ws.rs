use anyhow::{anyhow, Context, Result};
use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use std::time::{Duration, Instant};
use tokio::time::{interval, timeout, Interval};
use tokio_tungstenite::tungstenite::handshake::client::Request;
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::{Bytes, Error, Message};

type Socket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

/// A stalled handshake or send must not freeze the loop that also answers pings.
const IO_TIMEOUT: Duration = Duration::from_secs(10);

/// Obico sends small JSON messages, so a larger frame is a bug or abuse. The library default would
/// let a misbehaving server fill the memory of the bridge.
const MAX_MESSAGE_BYTES: usize = 1024 * 1024;

/// A websocket whose handshake and sends are bounded by a timeout.
pub struct Ws(Socket);

impl Ws {
    pub async fn connect(request: Request) -> Result<Self> {
        let config = WebSocketConfig::default()
            .max_message_size(Some(MAX_MESSAGE_BYTES))
            .max_frame_size(Some(MAX_MESSAGE_BYTES));
        let url = request.uri().to_string();
        let connect = tokio_tungstenite::connect_async_with_config(request, Some(config), false);
        let (socket, _) = timeout(IO_TIMEOUT, connect)
            .await
            .map_err(|_| anyhow!("connect to {url} timed out"))?
            .with_context(|| format!("websocket handshake with {url} failed"))?;
        Ok(Self(socket))
    }

    /// Cancel safe, so it can sit in a select next to timers and channels.
    pub async fn next(&mut self) -> Option<Result<Message, Error>> {
        self.0.next().await
    }

    pub async fn send(&mut self, message: Message) -> Result<()> {
        timeout(IO_TIMEOUT, self.0.send(message))
            .await
            .map_err(|_| anyhow!("send timed out"))?
            .context("send failed")
    }

    pub async fn send_json(&mut self, value: &Value) -> Result<()> {
        self.send(Message::Text(value.to_string().into())).await
    }

    pub async fn ping(&mut self) -> Result<()> {
        self.send(Message::Ping(Bytes::new())).await
    }
}

/// Pings a websocket on a fixed interval and gives up on a peer that stays silent. Any received
/// frame counts as life, so the limit should span several ping intervals.
pub struct Keepalive {
    ticker: Interval,
    last_rx: Instant,
    silence_limit: Duration,
}

impl Keepalive {
    pub fn new(ping_interval: Duration, silence_limit: Duration) -> Self {
        Self {
            ticker: interval(ping_interval),
            last_rx: Instant::now(),
            silence_limit,
        }
    }

    /// Records a received frame.
    pub fn received(&mut self) {
        self.last_rx = Instant::now();
    }

    /// Waits for the next ping time. It is split from `ping` so that the socket is not borrowed
    /// while a select waits for a frame on it, and it is cancel safe.
    pub async fn tick(&mut self) {
        self.ticker.tick().await;
    }

    /// Sends the ping, or returns the reason the session ends when the peer went silent or the
    /// ping failed.
    pub async fn ping(&mut self, ws: &mut Ws) -> Result<(), String> {
        if self.last_rx.elapsed() > self.silence_limit {
            return Err(format!("no data for {} s", self.silence_limit.as_secs()));
        }
        ws.ping().await.map_err(|e| format!("{e:#}"))
    }
}
