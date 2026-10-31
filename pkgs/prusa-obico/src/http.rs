use crate::state::{AppState, Inner};
use axum::extract::State;
use axum::http::header;
use axum::response::IntoResponse;
use axum::routing::get;
use axum::{Json, Router};
use serde_json::{json, Value};
use std::fmt::Write;
use std::sync::Arc;
use tokio::net::TcpListener;

pub fn status_json(s: &Inner, uptime_secs: u64) -> Value {
    json!({
        "printer": {"connected": s.printer_connected, "firmware": s.firmware},
        "obico": {"connected": s.obico_connected},
        "janus": {"connected": s.janus_connected},
        "stream": {"active": s.stream_active},
        "state": s.print_state.as_str(),
        "temperatures": s.temps.map(|t| json!({
            "tool0": {"actual": t.tool_actual, "target": t.tool_target},
            "bed": {"actual": t.bed_actual, "target": t.bed_target},
        })),
        "completion": s.completion,
        "current_print_ts": s.current_print_ts,
        "viewing": s.viewing,
        "last_snapshot": s.last_snapshot.as_ref().map(|i| json!({
            "timestamp": i.at, "ok": i.ok, "detail": i.detail,
        })),
        "last_command": s.last_command.as_ref().map(|(name, at)| json!({
            "cmd": name, "timestamp": at,
        })),
        "uptime_seconds": uptime_secs,
    })
}

pub fn metrics_text(s: &Inner) -> String {
    use crate::state::PrintState;
    let mut out = String::new();
    let mut metric = |name: &str, help: &str, kind: &str, value: String| {
        let _ = write!(out, "# HELP prusa_obico_{name} {help}\n# TYPE prusa_obico_{name} {kind}\nprusa_obico_{name} {value}\n");
    };
    let flag = |b: bool| (b as u8).to_string();
    metric(
        "printer_connected",
        "Serial link to the printer is up.",
        "gauge",
        flag(s.printer_connected),
    );
    metric(
        "obico_connected",
        "WebSocket to Obico is up.",
        "gauge",
        flag(s.obico_connected),
    );
    metric(
        "janus_connected",
        "WebSocket to the local Janus gateway is up.",
        "gauge",
        flag(s.janus_connected),
    );
    metric(
        "stream_active",
        "The ffmpeg feeder for the live stream is running.",
        "gauge",
        flag(s.stream_active),
    );
    metric(
        "printing",
        "A print is running.",
        "gauge",
        flag(s.print_state == PrintState::Printing),
    );
    metric(
        "paused",
        "A print is paused.",
        "gauge",
        flag(s.print_state == PrintState::Paused),
    );
    metric(
        "completion_ratio",
        "Print completion between 0 and 1.",
        "gauge",
        (s.completion.unwrap_or(0.0) / 100.0).to_string(),
    );
    metric(
        "last_snapshot_success_timestamp_seconds",
        "Unix time of the last uploaded snapshot, 0 if none.",
        "gauge",
        s.last_snapshot_success.unwrap_or(0).to_string(),
    );
    metric(
        "snapshot_failures_total",
        "Failed snapshot attempts.",
        "counter",
        s.snapshot_failures.to_string(),
    );
    metric(
        "status_messages_total",
        "Status messages sent to Obico.",
        "counter",
        s.status_messages.to_string(),
    );
    out.push_str("# HELP prusa_obico_temperature_celsius Printer temperatures.\n# TYPE prusa_obico_temperature_celsius gauge\n");
    if let Some(t) = s.temps {
        for (sensor, kind, v) in [
            ("tool0", "actual", t.tool_actual),
            ("tool0", "target", t.tool_target),
            ("bed", "actual", t.bed_actual),
            ("bed", "target", t.bed_target),
        ] {
            let _ = writeln!(
                out,
                "prusa_obico_temperature_celsius{{sensor=\"{sensor}\",kind=\"{kind}\"}} {v}"
            );
        }
    }
    out.push_str("# HELP prusa_obico_commands_total Commands forwarded to the printer.\n# TYPE prusa_obico_commands_total counter\n");
    for (cmd, n) in &s.commands {
        let _ = writeln!(out, "prusa_obico_commands_total{{cmd=\"{cmd}\"}} {n}");
    }
    out
}

async fn status(State(state): State<Arc<AppState>>) -> Json<Value> {
    Json(status_json(
        &state.snapshot(),
        state.started.elapsed().as_secs(),
    ))
}

async fn metrics(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/plain; version=0.0.4")],
        metrics_text(&state.snapshot()),
    )
}

pub async fn serve(listener: TcpListener, state: Arc<AppState>) -> std::io::Result<()> {
    let app = Router::new()
        .route("/status", get(status))
        .route("/metrics", get(metrics))
        .with_state(state);
    axum::serve(listener, app).await
}
