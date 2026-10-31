//! Tests of the command mapping, the line reader and the terminal mirror.

use super::{
    apply_host_action, apply_m27, is_ok, is_temperature_wait, Command, Flow, LineReader, Printer,
    Terminal, TerminalLine, CONNECT_LINES, MAX_LINE, OK_TIMEOUT,
};
use crate::marlin::M27;
use crate::state::{AppState, PrintState};
use std::time::{Duration, Instant};
use tokio::sync::mpsc;

#[test]
fn pause_request_survives_a_stale_printing_reply() {
    let state = AppState::new(None);
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    state.request_pause();
    apply_m27(M27::Printing { done: 2, total: 10 }, &state);
    assert_eq!(state.read().print_state, PrintState::Printing);
    apply_m27(M27::NotPrinting, &state);
    assert_eq!(state.read().print_state, PrintState::Paused);
    assert!(state.read().pause_requested());
}

#[test]
fn resume_from_the_lcd_clears_the_pause_request() {
    let state = AppState::new(None);
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    state.request_pause();
    apply_m27(M27::NotPrinting, &state);
    assert_eq!(state.read().print_state, PrintState::Paused);
    apply_m27(M27::Printing { done: 3, total: 10 }, &state);
    assert_eq!(state.read().print_state, PrintState::Printing);
    assert!(!state.read().pause_requested());
}

#[test]
fn first_printing_reply_after_a_reconnect_clears_the_pause_request() {
    let state = AppState::new(None);
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    state.request_pause();
    state.set_printer_offline();
    assert!(state.read().pause_requested());
    apply_m27(M27::Printing { done: 2, total: 10 }, &state);
    assert_eq!(state.read().print_state, PrintState::Printing);
    assert!(!state.read().pause_requested());
}

#[test]
fn pause_request_survives_a_reconnect_into_a_paused_printer() {
    let state = AppState::new(None);
    state.request_pause();
    state.set_printer_offline();
    apply_m27(M27::NotPrinting, &state);
    assert_eq!(state.read().print_state, PrintState::Paused);
    assert!(state.read().pause_requested());
}

#[test]
fn a_pause_the_print_ignored_for_too_long_expires() {
    let limit = Duration::from_secs(120);
    let state = AppState::new(None);
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    state.request_pause();
    let now = Instant::now();
    assert!(!state.expire_unconfirmed_pause(now, limit));
    assert!(state.read().pause_requested());

    assert!(state.expire_unconfirmed_pause(now + limit + Duration::from_secs(1), limit));
    assert!(!state.read().pause_requested());
}

#[test]
fn a_pause_that_took_effect_does_not_expire() {
    let limit = Duration::from_secs(120);
    let state = AppState::new(None);
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    state.request_pause();
    apply_m27(M27::NotPrinting, &state);
    assert!(!state.expire_unconfirmed_pause(Instant::now() + limit * 2, limit));
    assert!(state.read().pause_requested());
}

#[test]
fn a_pause_restored_from_the_marker_does_not_expire() {
    let limit = Duration::from_secs(120);
    let dir = std::env::temp_dir().join(format!("prusa-obico-marker-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("pause_requested"), b"").unwrap();
    let state = AppState::new(Some(dir.clone()));
    state.set_print_state(PrintState::Printing, Some(1.0), Some(1));
    assert!(!state.expire_unconfirmed_pause(Instant::now() + limit * 2, limit));
    assert!(state.read().pause_requested());
    std::fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn the_pause_limit_restarts_when_the_m601_leaves_the_queue() {
    let limit = Duration::from_secs(120);
    let state = AppState::new(None);
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    state.request_pause();
    let dispatched = Instant::now();
    std::thread::sleep(Duration::from_millis(5));
    assert!(state.confirm_pause());
    // Just past the limit from the dispatch, but within it from the M601.
    let at = dispatched + limit + Duration::from_millis(1);
    assert!(!state.expire_unconfirmed_pause(at, limit));
}

#[test]
fn a_print_only_reads_as_idle_after_several_not_printing_replies() {
    let state = AppState::new(None);
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    let print_ts = state.read().current_print_ts;
    for _ in 0..5 {
        apply_m27(M27::NotPrinting, &state);
        assert_eq!(state.read().print_state, PrintState::Printing);
    }
    assert_eq!(state.read().current_print_ts, print_ts);
    apply_m27(M27::NotPrinting, &state);
    assert_eq!(state.read().print_state, PrintState::Idle);
}

#[test]
fn a_printing_reply_restarts_the_count_towards_idle() {
    let state = AppState::new(None);
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    for _ in 0..5 {
        apply_m27(M27::NotPrinting, &state);
    }
    apply_m27(M27::Printing { done: 2, total: 10 }, &state);
    apply_m27(M27::NotPrinting, &state);
    assert_eq!(state.read().print_state, PrintState::Printing);
}

#[test]
fn the_first_reply_after_a_reconnect_reads_as_idle_at_once() {
    let state = AppState::new(None);
    apply_m27(M27::NotPrinting, &state);
    assert_eq!(state.read().print_state, PrintState::Idle);
}

#[tokio::test]
async fn long_and_garbled_lines_do_not_end_the_stream() {
    let mut input = b"ok\n".to_vec();
    input.extend(vec![b'x'; MAX_LINE + 10]);
    input.extend(b"\nT:1\xff\nlast");
    let mut lines = LineReader::new(&input[..]);
    assert_eq!(lines.next_line().await.unwrap().as_deref(), Some("ok"));
    assert_eq!(
        lines.next_line().await.unwrap().as_deref(),
        Some("T:1\u{fffd}")
    );
    assert_eq!(lines.next_line().await.unwrap(), None);
}

#[test]
fn gcode_for_commands() {
    assert_eq!(Command::Home(vec![]).gcode(), ["G28"]);
    assert_eq!(Command::Home(vec!['X', 'Y']).gcode(), ["G28 X Y"]);
    assert_eq!(
        Command::Jog(vec![('X', 10.0)]).gcode(),
        ["G91", "G1 X10 F3000", "G90"]
    );
    let cmd = Command::Gcode(vec!["M83".into(), "G1 E5 F300".into()]);
    assert_eq!(cmd.gcode(), ["M83", "G1 E5 F300"]);
    assert_eq!(cmd.name(), "gcode");
}

fn test_terminal(capacity: usize) -> (Terminal, mpsc::Receiver<TerminalLine>) {
    let (tx, rx) = mpsc::channel(capacity);
    let terminal = Terminal {
        state: AppState::new(None),
        tx,
    };
    (terminal, rx)
}

#[test]
fn terminal_mirrors_only_while_wanted_and_viewed() {
    let (terminal, mut rx) = test_terminal(8);
    terminal.received("ok T:21.0 /0.0");
    assert!(rx.try_recv().is_err());
    terminal.state.set_terminal_feed(true);
    terminal.received("ok");
    assert!(rx.try_recv().is_err());
    terminal.state.set_viewing(true);
    terminal.received("ok T:21.0 /0.0");
    terminal.mirror("M27");
    assert_eq!(rx.try_recv().unwrap().msg, "ok T:21.0 /0.0");
    assert_eq!(rx.try_recv().unwrap().msg, "M27");
    terminal.state.set_viewing(false);
    terminal.mirror("M27");
    assert!(rx.try_recv().is_err());
}

#[test]
fn terminal_skips_wait_and_blank_lines() {
    let (terminal, mut rx) = test_terminal(8);
    terminal.state.set_terminal_feed(true);
    terminal.state.set_viewing(true);
    terminal.received("wait");
    terminal.received("WAIT");
    terminal.received("   ");
    terminal.received("echo:busy");
    let line = rx.try_recv().unwrap();
    assert_eq!(line.msg, "echo:busy");
    assert!(line.ts > 1.0e9);
    assert!(rx.try_recv().is_err());
}

#[test]
fn terminal_drops_lines_when_the_channel_is_full() {
    let (terminal, mut rx) = test_terminal(1);
    terminal.state.set_terminal_feed(true);
    terminal.state.set_viewing(true);
    terminal.mirror("first");
    terminal.mirror("second");
    assert_eq!(rx.try_recv().unwrap().msg, "first");
    assert!(rx.try_recv().is_err());
}

#[test]
fn host_action_lines_track_the_pause_flag() {
    let state = AppState::new(None);
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    assert!(apply_host_action(&state, "//action:paused"));
    assert!(state.read().pause_requested());
    assert!(apply_host_action(&state, "//action:resumed"));
    assert!(!state.read().pause_requested());
}

#[test]
fn host_action_cancel_clears_both_request_flags() {
    let state = AppState::new(None);
    state.request_pause();
    state.request_cancel();
    assert!(apply_host_action(&state, "//action:cancel"));
    assert!(!state.read().pause_requested());
    assert!(!state.read().cancel_requested);
}

#[test]
fn other_lines_are_not_host_actions() {
    let state = AppState::new(None);
    state.request_pause();
    assert!(!apply_host_action(&state, "// action:pause"));
    assert!(!apply_host_action(&state, "//action:pause"));
    assert!(!apply_host_action(&state, "//action:ready"));
    assert!(!apply_host_action(&state, "ok"));
    assert!(state.read().pause_requested());
}

#[test]
fn only_ok_as_a_word_of_its_own_is_an_ack() {
    assert!(is_ok("ok"));
    assert!(is_ok("ok T:21.7 /0.0 B:21.8 /0.0 @:0 B@:0"));
    assert!(!is_ok("T:21.7 /0.0 B:21.8 /0.0"));
    assert!(!is_ok("echo:ok"));
    assert!(!is_ok("okapi.gcode"));
}

#[test]
fn flow_keeps_one_line_in_flight() {
    let now = Instant::now();
    let mut flow = Flow::new();
    assert!(!flow.busy());
    flow.push("G91");
    flow.push("M27");
    assert!(flow.busy());
    assert_eq!(flow.next(now).as_deref(), Some("G91"));
    assert_eq!(flow.next(now), None);
    flow.acked();
    assert_eq!(flow.next(now).as_deref(), Some("M27"));
    assert!(flow.busy());
    flow.acked();
    assert_eq!(flow.next(now), None);
    assert!(!flow.busy());
}

#[test]
fn flow_drops_the_queue_when_the_ok_is_overdue() {
    let start = Instant::now();
    let mut flow = Flow::new();
    flow.push("G28");
    flow.push("M27");
    assert!(!flow.expire(start, OK_TIMEOUT));
    assert_eq!(flow.next(start).as_deref(), Some("G28"));
    assert!(!flow.expire(start + OK_TIMEOUT, OK_TIMEOUT));
    assert!(flow.expire(start + OK_TIMEOUT + Duration::from_secs(1), OK_TIMEOUT));
    assert!(!flow.busy());
    assert_eq!(flow.next(start), None);
}

#[test]
fn flow_keeps_the_g90_of_a_jog_when_the_ok_is_overdue() {
    let start = Instant::now();
    let mut flow = Flow::new();
    flow.push_command(&Command::Jog(vec![('X', 1.0)]));
    flow.push("M27");
    assert_eq!(flow.next(start).as_deref(), Some("G91"));
    assert!(flow.expire(start + OK_TIMEOUT + Duration::from_secs(1), OK_TIMEOUT));
    assert!(flow.busy());
    assert_eq!(flow.next(start).as_deref(), Some("G90"));
    flow.acked();
    assert_eq!(flow.next(start), None);
}

#[test]
fn flow_drops_a_g90_that_a_user_queued_when_the_ok_is_overdue() {
    let start = Instant::now();
    let mut flow = Flow::new();
    flow.push("G28");
    flow.push("G90");
    assert_eq!(flow.next(start).as_deref(), Some("G28"));
    assert!(flow.expire(start + OK_TIMEOUT + Duration::from_secs(1), OK_TIMEOUT));
    assert!(!flow.busy());
}

#[test]
fn flow_keeps_the_connect_lines_when_the_first_ok_is_overdue() {
    let start = Instant::now();
    let mut flow = Flow::new();
    flow.push_connect();
    assert_eq!(flow.next(start).as_deref(), Some("M115"));
    assert!(flow.expire(start + OK_TIMEOUT + Duration::from_secs(1), OK_TIMEOUT));
    assert_eq!(flow.next(start).as_deref(), Some("M155 S2"));
    flow.acked();
    assert!(!flow.busy());
}

#[test]
fn the_connect_lines_leave_the_positioning_mode_of_a_running_print_alone() {
    assert!(!CONNECT_LINES.contains(&"G90"));
}

#[test]
fn absolute_mode_is_restored_once_and_only_when_idle() {
    let state = AppState::new(None);
    let printer = test_printer(&state);
    let mut flow = Flow::new();
    let mut pending = true;

    printer.restore_absolute_mode(&mut flow, &mut pending);
    assert!(!flow.busy());

    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    printer.restore_absolute_mode(&mut flow, &mut pending);
    assert!(!flow.busy());

    state.set_print_state(PrintState::Idle, None, None);
    printer.restore_absolute_mode(&mut flow, &mut pending);
    assert_eq!(flow.next(Instant::now()).as_deref(), Some("G90"));
    flow.acked();
    printer.restore_absolute_mode(&mut flow, &mut pending);
    assert!(!flow.busy());
}

#[test]
fn absolute_mode_waits_while_a_pause_reads_as_paused() {
    let state = AppState::new(None);
    let printer = test_printer(&state);
    let mut flow = Flow::new();
    let mut pending = true;
    state.request_pause();
    apply_m27(M27::NotPrinting, &state);
    printer.restore_absolute_mode(&mut flow, &mut pending);
    assert!(!flow.busy());
    assert!(pending);
}

#[test]
fn flow_ignores_an_unsolicited_ok() {
    let now = Instant::now();
    let mut flow = Flow::new();
    flow.acked();
    flow.push("M27");
    flow.push("M105");
    assert_eq!(flow.next(now).as_deref(), Some("M27"));
    assert_eq!(flow.next(now), None);
}

fn test_printer(state: &std::sync::Arc<AppState>) -> Printer {
    let (_cmd_tx, cmd_rx) = mpsc::channel(1);
    let (term_tx, _term_rx) = mpsc::channel(1);
    Printer::new("127.0.0.1:0".into(), state.clone(), cmd_rx, term_tx)
}

#[test]
fn pause_is_not_queued_when_no_print_is_running() {
    let state = AppState::new(None);
    let printer = test_printer(&state);
    let mut flow = Flow::new();
    state.request_pause();
    printer.accept_command(&mut flow, Command::Pause);
    assert!(!flow.busy());
    assert!(!state.read().pause_requested());
}

#[test]
fn a_queued_pause_keeps_the_flag_of_a_print_that_paused_meanwhile() {
    let state = AppState::new(None);
    let printer = test_printer(&state);
    let mut flow = Flow::new();
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    state.request_pause();
    apply_m27(M27::NotPrinting, &state);
    assert_eq!(state.read().print_state, PrintState::Paused);
    printer.accept_command(&mut flow, Command::Pause);
    assert!(!flow.busy());
    assert!(state.read().pause_requested());
}

#[test]
fn home_and_jog_are_not_queued_unless_the_printer_is_idle() {
    let state = AppState::new(None);
    let printer = test_printer(&state);
    for state_now in [
        PrintState::Offline,
        PrintState::Printing,
        PrintState::Paused,
    ] {
        state.set_print_state(state_now, Some(1.0), Some(1));
        for cmd in [Command::Home(Vec::new()), Command::Jog(vec![('X', 1.0)])] {
            let mut flow = Flow::new();
            printer.accept_command(&mut flow, cmd);
            assert!(!flow.busy(), "{state_now:?}");
        }
    }
    state.set_print_state(PrintState::Idle, None, None);
    let mut flow = Flow::new();
    printer.accept_command(&mut flow, Command::Home(Vec::new()));
    assert_eq!(flow.next(Instant::now()).as_deref(), Some("G28"));
}

#[test]
fn resume_is_not_queued_unless_paused_and_keeps_the_pause_flag() {
    let state = AppState::new(None);
    let printer = test_printer(&state);
    let mut flow = Flow::new();
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    state.request_pause();
    printer.accept_command(&mut flow, Command::Resume);
    assert!(!flow.busy());
    assert!(state.read().pause_requested());

    apply_m27(M27::Paused, &state);
    printer.accept_command(&mut flow, Command::Resume);
    assert_eq!(flow.next(Instant::now()).as_deref(), Some("M602"));
    // Only the firmware's confirmation ends the pause, since M602 can be lost or refused.
    assert!(state.read().pause_requested());
    printer.handle_line(&mut flow, "//action:resumed");
    assert!(!state.read().pause_requested());
}

#[test]
fn cancel_keeps_the_pause_flag_until_the_firmware_confirms_it() {
    let state = AppState::new(None);
    let printer = test_printer(&state);
    let mut flow = Flow::new();
    apply_m27(M27::Paused, &state);
    state.request_pause();
    printer.accept_command(&mut flow, Command::Cancel);
    assert_eq!(flow.next(Instant::now()).as_deref(), Some("M603"));
    assert!(state.read().pause_requested());
    printer.handle_line(&mut flow, "//action:cancel");
    assert!(!state.read().pause_requested());
}

#[test]
fn cancel_is_not_queued_unless_a_print_runs_and_the_flag_is_withdrawn() {
    let state = AppState::new(None);
    let printer = test_printer(&state);
    let mut flow = Flow::new();
    state.request_cancel();
    printer.accept_command(&mut flow, Command::Cancel);
    assert!(!flow.busy());
    assert!(!state.read().cancel_requested);

    for m27 in [M27::Printing { done: 1, total: 10 }, M27::Paused] {
        apply_m27(m27, &state);
        let mut flow = Flow::new();
        printer.accept_command(&mut flow, Command::Cancel);
        assert_eq!(flow.next(Instant::now()).as_deref(), Some("M603"));
    }
}

#[test]
fn pause_is_queued_with_an_m27_while_printing() {
    let state = AppState::new(None);
    let printer = test_printer(&state);
    let mut flow = Flow::new();
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    printer.accept_command(&mut flow, Command::Pause);
    let now = Instant::now();
    assert_eq!(flow.next(now).as_deref(), Some("M601"));
    flow.acked();
    assert_eq!(flow.next(now).as_deref(), Some("M27"));
    assert!(state.read().pause_requested());
}

#[test]
fn paused_action_is_ignored_unless_a_print_is_running() {
    let state = AppState::new(None);
    assert!(apply_host_action(&state, "//action:paused"));
    assert!(!state.read().pause_requested());
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    assert!(apply_host_action(&state, "//action:paused"));
    assert!(state.read().pause_requested());
}

#[test]
fn only_wait_reports_count_as_temperature_wait() {
    assert!(is_temperature_wait("T:180.0 E:0 W:5"));
    assert!(is_temperature_wait("T:60.0 E:0 W:?"));
    assert!(is_temperature_wait("T:21.70 E:0 B:45.3"));
    assert!(!is_temperature_wait("T:21.7 /0.0 B:21.8 /0.0 @:0 B@:0"));
    assert!(!is_temperature_wait("ok T:21.7 /0.0 B:21.8 /0.0"));
    assert!(!is_temperature_wait("echo: E:5"));
}

#[test]
fn a_bed_wait_report_keeps_the_reported_targets() {
    let state = AppState::new(None);
    let printer = test_printer(&state);
    let mut flow = Flow::new();
    printer.handle_line(&mut flow, "T:215.0 /215.0 B:40.0 /60.0 @:0 B@:0");
    printer.handle_line(&mut flow, "T:215.00 E:0 B:45.3");
    assert_eq!(state.read().temps.unwrap().bed.target, 60.0);
}

#[test]
fn flow_extends_the_ok_deadline_while_the_firmware_reports() {
    let start = Instant::now();
    let mut flow = Flow::new();
    flow.push("M109 S200");
    flow.push("M27");
    assert_eq!(flow.next(start).as_deref(), Some("M109 S200"));
    let report = start + OK_TIMEOUT;
    flow.extend(report);
    let late = start + OK_TIMEOUT + Duration::from_secs(1);
    assert!(!flow.expire(late, OK_TIMEOUT));
    assert!(flow.expire(report + OK_TIMEOUT + Duration::from_secs(1), OK_TIMEOUT));
    assert!(!flow.busy());
}

#[test]
fn flow_extend_does_nothing_without_a_line_in_flight() {
    let now = Instant::now();
    let mut flow = Flow::new();
    flow.extend(now);
    assert!(!flow.busy());
    flow.push("M27");
    flow.extend(now);
    assert_eq!(flow.next(now).as_deref(), Some("M27"));
}

#[test]
fn host_cancel_queues_an_m27_so_a_later_pause_sees_the_idle_printer() {
    let state = AppState::new(None);
    let printer = test_printer(&state);
    let mut flow = Flow::new();
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    printer.handle_line(&mut flow, "//action:cancel");
    assert_eq!(flow.next(Instant::now()).as_deref(), Some("M27"));
    flow.acked();
    assert!(!flow.busy());

    apply_m27(M27::NotPrinting, &state);
    assert_eq!(state.read().print_state, PrintState::Idle);
    printer.accept_command(&mut flow, Command::Pause);
    assert!(!flow.busy());
}

#[test]
fn a_reset_queues_an_m27_behind_the_connect_lines() {
    let state = AppState::new(None);
    let printer = test_printer(&state);
    let mut flow = Flow::new();
    apply_m27(M27::Printing { done: 1, total: 10 }, &state);
    flow.push("M601");
    printer.handle_reset(&mut flow);
    for expected in ["M115", "M155 S2", "M27"] {
        assert_eq!(flow.next(Instant::now()).as_deref(), Some(expected));
        flow.acked();
    }
    assert!(!flow.busy());
}

#[test]
fn a_late_ok_after_expiry_acks_the_next_line_and_does_not_wedge_the_flow() {
    let start = Instant::now();
    let mut flow = Flow::new();
    flow.push("G28");
    flow.push("M27");
    assert_eq!(flow.next(start).as_deref(), Some("G28"));
    assert!(flow.expire(start + OK_TIMEOUT + Duration::from_secs(1), OK_TIMEOUT));
    flow.push("M105");
    assert_eq!(flow.next(start).as_deref(), Some("M105"));
    // The ok of the expired G28 arrives late and is taken for the ok of the M105.
    flow.acked();
    flow.push("M27");
    assert_eq!(flow.next(start).as_deref(), Some("M27"));
}

#[tokio::test]
async fn an_over_long_line_is_discarded_across_several_buffer_fills() {
    let mut input = vec![b'x'; MAX_LINE + 100];
    input.extend(b"\nnext\n");
    let reader = tokio::io::BufReader::with_capacity(16, &input[..]);
    let mut lines = LineReader::new(reader);
    assert_eq!(lines.next_line().await.unwrap().as_deref(), Some("next"));
    assert_eq!(lines.next_line().await.unwrap(), None);
}
