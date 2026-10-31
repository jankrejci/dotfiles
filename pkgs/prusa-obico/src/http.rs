use crate::state::{AppState, Inner, PrintState};
use axum::extract::State;
use axum::http::header;
use axum::response::IntoResponse;
use axum::routing::get;
use axum::{Json, Router};
use serde_json::{json, Value};
use std::fmt;
use std::sync::Arc;
use tokio::net::TcpListener;

/// The JSON served by the status endpoint.
fn status_json(s: &Inner, uptime_secs: u64) -> Value {
    json!({
        "printer": {
            "connected": s.printer_connected,
            "firmware": s.firmware,
            "link_lost_during_print": s.link_lost_during_print
        },
        "obico": {"connected": s.obico_connected},
        "janus": {"connected": s.janus_connected},
        "stream": {"active": s.stream_active},
        "state": s.print_state.as_str(),
        "temperatures": s.temps,
        "completion": s.completion,
        "current_print_ts": s.current_print_ts,
        "viewing": s.viewing,
        "last_snapshot": s.last_snapshot,
        "last_command": s.last_command,
        "uptime_seconds": uptime_secs,
    })
}

/// The state in the Prometheus text format.
pub struct Metrics<'a>(pub &'a Inner);

impl fmt::Display for Metrics<'_> {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = self.0;
        let mut metric = |name: &str, help: &str, kind: &str, value: String| -> fmt::Result {
            write!(out, "# HELP prusa_obico_{name} {help}\n# TYPE prusa_obico_{name} {kind}\nprusa_obico_{name} {value}\n")
        };
        let flag = |b: bool| (b as u8).to_string();
        metric(
            "printer_connected",
            "Serial link to the printer is up.",
            "gauge",
            flag(s.printer_connected),
        )?;
        metric(
            "obico_connected",
            "WebSocket to Obico is up.",
            "gauge",
            flag(s.obico_connected),
        )?;
        metric(
            "janus_connected",
            "WebSocket to the local Janus gateway is up.",
            "gauge",
            flag(s.janus_connected),
        )?;
        metric(
            "stream_active",
            "The ffmpeg feeder for the live stream is running.",
            "gauge",
            flag(s.stream_active),
        )?;
        metric(
            "printing",
            "A print is running.",
            "gauge",
            flag(s.print_state == PrintState::Printing),
        )?;
        metric(
            "link_lost_during_print",
            "The serial link dropped during a print and the printer has not come back.",
            "gauge",
            flag(s.link_lost_during_print),
        )?;
        metric(
            "paused",
            "A print is paused.",
            "gauge",
            flag(s.print_state == PrintState::Paused),
        )?;
        metric(
            "completion_ratio",
            "Print completion between 0 and 1.",
            "gauge",
            (s.completion.unwrap_or(0.0) / 100.0).to_string(),
        )?;
        metric(
            "last_snapshot_success_timestamp_seconds",
            "Unix time of the last uploaded snapshot, 0 if none.",
            "gauge",
            s.last_snapshot_success.unwrap_or(0).to_string(),
        )?;
        metric(
            "snapshot_failures_total",
            "Failed snapshot attempts.",
            "counter",
            s.snapshot_failures.to_string(),
        )?;
        metric(
            "status_messages_total",
            "Status messages sent to Obico.",
            "counter",
            s.status_messages.to_string(),
        )?;
        out.write_str("# HELP prusa_obico_temperature_celsius Printer temperatures.\n# TYPE prusa_obico_temperature_celsius gauge\n")?;
        if let Some(t) = s.temps {
            for (sensor, kind, v) in [
                ("tool0", "actual", t.tool.actual),
                ("tool0", "target", t.tool.target),
                ("bed", "actual", t.bed.actual),
                ("bed", "target", t.bed.target),
            ] {
                writeln!(
                    out,
                    "prusa_obico_temperature_celsius{{sensor=\"{sensor}\",kind=\"{kind}\"}} {v}"
                )?;
            }
        }
        out.write_str("# HELP prusa_obico_commands_total Commands forwarded to the printer.\n# TYPE prusa_obico_commands_total counter\n")?;
        for (cmd, n) in &s.commands {
            writeln!(out, "prusa_obico_commands_total{{cmd=\"{cmd}\"}} {n}")?;
        }
        Ok(())
    }
}

async fn status(State(state): State<Arc<AppState>>) -> Json<Value> {
    let uptime = state.started.elapsed().as_secs();
    Json(state.with(|s| status_json(s, uptime)))
}

async fn metrics(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/plain; version=0.0.4")],
        state.with(|s| Metrics(s).to_string()),
    )
}

/// The status and metrics endpoints on an already bound listener.
pub struct Http {
    listener: TcpListener,
    state: Arc<AppState>,
}

impl Http {
    pub fn new(listener: TcpListener, state: Arc<AppState>) -> Self {
        Self { listener, state }
    }

    pub async fn serve(self) -> std::io::Result<()> {
        let app = Router::new()
            .route("/status", get(status))
            .route("/metrics", get(metrics))
            .with_state(self.state);
        axum::serve(self.listener, app).await
    }
}

#[cfg(test)]
#[path = "tests/http.rs"]
mod tests;
