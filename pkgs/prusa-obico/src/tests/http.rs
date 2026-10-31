//! Tests of the status JSON and the Prometheus text.

use super::{status_json, Metrics};
use crate::marlin::{Reading, Temps};
use crate::state::{AppState, PrintState};
use serde_json::Value;

#[test]
fn status_reports_null_without_a_print() {
    let state = AppState::new(None);
    let status = status_json(&state.read(), 7);
    assert_eq!(status["current_print_ts"], Value::Null);
    assert_eq!(status["temperatures"], Value::Null);
    assert_eq!(status["uptime_seconds"], 7);
    assert_eq!(status["state"], "offline");
}

#[test]
fn metrics_expose_flags_temperatures_and_commands() {
    let state = AppState::new(None);
    state.set_obico_connected(true);
    state.set_temps(Temps {
        tool: Reading {
            actual: 21.5,
            target: 0.0,
        },
        bed: Reading::default(),
    });
    state.record_command("pause");
    let text = Metrics(&state.read()).to_string();
    assert!(text.contains("prusa_obico_obico_connected 1\n"));
    assert!(text.contains("prusa_obico_printer_connected 0\n"));
    assert!(
        text.contains("prusa_obico_temperature_celsius{sensor=\"tool0\",kind=\"actual\"} 21.5\n")
    );
    assert!(text.contains("prusa_obico_commands_total{cmd=\"pause\"} 1\n"));
}

#[test]
fn link_loss_is_reported_in_status_and_metrics() {
    let state = AppState::new(None);
    assert_eq!(
        status_json(&state.read(), 0)["printer"]["link_lost_during_print"],
        false
    );
    assert!(Metrics(&state.read())
        .to_string()
        .contains("prusa_obico_link_lost_during_print 0\n"));
    state.set_print_state(PrintState::Printing, Some(1.0), Some(1));
    state.set_printer_offline();
    assert_eq!(
        status_json(&state.read(), 0)["printer"]["link_lost_during_print"],
        true
    );
    assert!(Metrics(&state.read())
        .to_string()
        .contains("prusa_obico_link_lost_during_print 1\n"));
}
