//! Tests of the Obico messages and command gating.

use super::{
    end_session, parse_gcode, parse_home, parse_jog, Config, Session, BOOST_MESSAGES,
    MAX_GCODE_LINES,
};
use crate::printer::{Command, MAX_GCODE_LINE};
use crate::state::{AppState, PrintState};
use serde_json::json;
use std::collections::VecDeque;
use tokio::sync::mpsc;

fn test_config(has_video: bool) -> Config {
    Config {
        url: "https://app.obico.io".parse().unwrap(),
        token: "token".into(),
        has_video,
    }
}

#[test]
fn settings_advertise_h264_webcam() {
    let cam = &test_config(true).settings()["webcams"][0];
    assert_eq!(cam["stream_mode"], "h264_copy");
    assert_eq!(cam["stream_id"], 1);
    assert_eq!(cam["streamRatio"], "4:3");
}

#[test]
fn ws_url_swaps_the_scheme() {
    let mut cfg = test_config(false);
    assert_eq!(cfg.url.ws(), "wss://app.obico.io/ws/dev/");
    cfg.url = "http://localhost:3334/".parse().unwrap();
    assert_eq!(cfg.url.ws(), "ws://localhost:3334/ws/dev/");
}

#[test]
fn settings_without_video_have_no_webcam() {
    assert_eq!(test_config(false).settings()["webcams"], json!([]));
}

#[test]
fn gcode_lines_pass_verbatim_without_blanks() {
    let cmd = parse_gcode(&json!("M83\n T0 \r\n\nG1 E5 F300")).unwrap();
    assert_eq!(
        cmd,
        Command::Gcode(vec!["M83".into(), "T0".into(), "G1 E5 F300".into()])
    );
    let list = parse_gcode(&json!(["M106 S255", "M117 hi"])).unwrap();
    assert_eq!(
        list,
        Command::Gcode(vec!["M106 S255".into(), "M117 hi".into()])
    );
}

#[test]
fn gcode_drops_comment_lines_but_keeps_inline_comments() {
    assert_eq!(
        parse_gcode(&json!("; hi\nM83\n  ;x")).unwrap(),
        Command::Gcode(vec!["M83".into()])
    );
    assert!(parse_gcode(&json!("; hi")).is_err());
    assert_eq!(
        parse_gcode(&json!("M117 a;b")).unwrap(),
        Command::Gcode(vec!["M117 a;b".into()])
    );
}

#[test]
fn gcode_refuses_framing_tricks() {
    assert!(parse_gcode(&json!("M117 a\u{0}b")).is_err());
    assert!(parse_gcode(&json!("M117 a\tb")).is_err());
    assert!(parse_gcode(&json!("x".repeat(MAX_GCODE_LINE + 1))).is_err());
    assert!(parse_gcode(&json!("x".repeat(MAX_GCODE_LINE))).is_ok());
    assert!(parse_gcode(&json!("  \n ")).is_err());
    assert!(parse_gcode(&json!(null)).is_err());
}

#[test]
fn gcode_line_count_is_capped() {
    let lines = |n: usize| json!(vec!["M117 hi"; n]);
    assert!(parse_gcode(&lines(MAX_GCODE_LINES)).is_ok());
    assert!(parse_gcode(&lines(MAX_GCODE_LINES + 1)).is_err());
}

#[test]
fn jog_distance_is_clamped() {
    let jog = parse_jog(&json!({"x": 500.0, "y": -500.0, "z": 1.5, "e": 5.0}));
    assert_eq!(
        jog.unwrap(),
        Command::Jog(vec![('X', 50.0), ('Y', -50.0), ('Z', 1.5)])
    );
}

#[test]
fn jog_refuses_z_down_and_empty_moves() {
    assert!(parse_jog(&json!({"x": 5.0, "z": -0.1})).is_err());
    assert!(parse_jog(&json!({"e": 5.0})).is_err());
    assert_eq!(
        parse_jog(&json!({"z": 500.0})).unwrap(),
        Command::Jog(vec![('Z', 50.0)])
    );
}

#[test]
fn home_keeps_only_motion_axes() {
    assert_eq!(
        parse_home(&json!(["x", "Y", "e", "z"])).unwrap(),
        Command::Home(vec!['X', 'Y', 'Z'])
    );
}

#[test]
fn home_takes_a_whole_value_as_the_axis_and_not_its_first_letter() {
    assert_eq!(
        parse_home(&json!(["x", "zebra", "zz"])).unwrap(),
        Command::Home(vec!['X'])
    );
    assert!(parse_home(&json!(["zebra"])).is_err());
}

#[test]
fn home_all_for_an_empty_list_and_refuses_garbage() {
    assert_eq!(parse_home(&json!([])).unwrap(), Command::Home(vec![]));
    assert!(parse_home(&json!(null)).is_err());
    assert!(parse_home(&json!("x")).is_err());
    assert!(parse_home(&json!({"x": 1})).is_err());
    assert!(parse_home(&json!(["e", 1, ""])).is_err());
}

fn test_session(capacity: usize) -> (Session, mpsc::Receiver<Command>, mpsc::Receiver<String>) {
    let (commands, command_rx) = mpsc::channel(capacity);
    let (janus, janus_rx) = mpsc::channel(4);
    let session = Session {
        state: AppState::new(None),
        commands,
        janus,
        boost: 0,
        seen_refs: VecDeque::new(),
    };
    (session, command_rx, janus_rx)
}

#[test]
fn dispatch_refuses_while_the_printer_is_offline() {
    let (mut session, mut commands, _janus) = test_session(4);
    assert_eq!(
        session.dispatch(Command::Pause).map_err(|e| e.to_string()),
        Err("printer offline".to_string())
    );
    assert!(commands.try_recv().is_err());
}

#[test]
fn dispatch_pause_sets_the_flag_and_queues_the_command() {
    let (mut session, mut commands, _janus) = test_session(4);
    session
        .state
        .set_print_state(PrintState::Printing, Some(1.0), Some(1));
    assert_eq!(
        session.dispatch(Command::Pause).map_err(|e| e.to_string()),
        Ok(())
    );
    assert!(session.state.read().pause_requested());
    assert!(matches!(commands.try_recv(), Ok(Command::Pause)));
    assert_eq!(session.boost, BOOST_MESSAGES);
    assert_eq!(
        session.dispatch(Command::Pause).map_err(|e| e.to_string()),
        Err("pause already requested".to_string())
    );
}

#[test]
fn dispatch_rolls_back_the_flags_when_the_queue_is_full() {
    let (mut session, _commands, _janus) = test_session(1);
    session
        .state
        .set_print_state(PrintState::Printing, Some(1.0), Some(1));
    assert_eq!(
        session.dispatch(Command::Cancel).map_err(|e| e.to_string()),
        Ok(())
    );
    session.state.withdraw_cancel();
    assert_eq!(
        session.dispatch(Command::Cancel).map_err(|e| e.to_string()),
        Err("command queue full".to_string())
    );
    assert!(!session.state.read().cancel_requested);
}

#[test]
fn text_forwards_signaling_and_answers_passthru() {
    let (mut session, _commands, mut janus) = test_session(4);
    let text = json!({
        "janus": "{\"janus\":\"create\"}",
        "remote_status": {"viewing": true},
        "passthru": {"ref": "r1", "target": "_printer", "func": "pause_print"}
    })
    .to_string();
    let replies = session.handle_text(&text);
    assert_eq!(janus.try_recv().unwrap(), "{\"janus\":\"create\"}");
    assert!(session.state.read().viewing);
    assert_eq!(
        replies,
        [json!({"passthru": {"ref": "r1", "error": "printer offline"}})]
    );
    // A repeated ref is a retry of a message that was already answered.
    assert!(session.handle_text(&text).is_empty());
}

#[test]
fn janus_payload_must_be_a_string() {
    let (mut session, _commands, mut janus) = test_session(4);
    session.handle_text(&json!({"janus": {"janus": "create"}}).to_string());
    session.handle_text(&json!({"commands": []}).to_string());
    assert!(janus.try_recv().is_err());
}

#[test]
fn passthru_without_a_ref_gets_no_reply() {
    let (mut session, _commands, _janus) = test_session(4);
    let reply = session.handle_passthru(&json!({"target": "gcode_hooks", "func": "x"}));
    assert_eq!(reply, None);
}

#[test]
fn status_marks_a_missing_print_with_minus_one() {
    let state = AppState::new(None);
    assert_eq!(
        test_config(false).status_message(&state.read(), false)["current_print_ts"],
        -1
    );
    state.set_print_state(PrintState::Printing, Some(1.0), Some(1));
    let ts = state.read().current_print_ts;
    assert_eq!(
        test_config(false).status_message(&state.read(), false)["current_print_ts"],
        json!(ts)
    );
}

#[test]
fn gcode_passes_while_printing_but_not_offline() {
    let (mut session, mut commands, _janus) = test_session(4);
    let cmd = || Command::Gcode(vec!["M220 S120".into()]);
    assert_eq!(
        session.dispatch(cmd()).map_err(|e| e.to_string()),
        Err("printer offline".to_string())
    );
    session
        .state
        .set_print_state(PrintState::Printing, Some(1.0), Some(1));
    assert!(session.dispatch(cmd()).is_ok());
    assert_eq!(commands.try_recv().unwrap(), cmd());
}

#[test]
fn commands_passthru_forwards_the_gcode() {
    let (mut session, mut commands, _janus) = test_session(4);
    session.state.set_print_state(PrintState::Idle, None, None);
    let request = json!({
        "ref": "r1", "target": "_printer", "func": "commands", "args": ["M18\nM117 hi"]
    });
    assert_eq!(
        session.handle_passthru(&request),
        Some(json!({"passthru": {"ref": "r1", "ret": null}}))
    );
    assert_eq!(
        commands.try_recv().unwrap(),
        Command::Gcode(vec!["M18".into(), "M117 hi".into()])
    );
    let bad = json!({
        "ref": "r2", "target": "_printer", "func": "commands", "args": ["M117 a\u{1}"]
    });
    let reply = session.handle_passthru(&bad).unwrap();
    assert_eq!(
        reply["passthru"]["error"],
        "G-code contains a control character"
    );
}

#[test]
fn terminal_feed_toggle_changes_only_on_on_and_off() {
    let (mut session, _commands, _janus) = test_session(4);
    let toggle = |session: &mut Session, arg: &str| {
        // Each call needs its own ref, because a repeated ref is dropped as a retry.
        let ref_id = session.seen_refs.len().to_string();
        let request = json!({
            "ref": ref_id, "target": "gcode_hooks", "func": "toggle_terminal_feed", "args": [arg]
        });
        session.handle_passthru(&request).unwrap()["passthru"]["ret"].clone()
    };
    assert_eq!(toggle(&mut session, "get"), json!(false));
    assert_eq!(toggle(&mut session, "on"), json!(true));
    assert_eq!(toggle(&mut session, "get"), json!(true));
    assert_eq!(toggle(&mut session, "bogus"), json!(true));
    assert_eq!(toggle(&mut session, "off"), json!(false));
}

#[test]
fn jog_axis_key_is_exactly_one_letter() {
    let jog = parse_jog(&json!({"xy": 5.0, "x1": 5.0, "": 5.0, "Y": 2.0}));
    assert_eq!(jog.unwrap(), Command::Jog(vec![('Y', 2.0)]));
    assert!(parse_jog(&json!({"xy": 5.0, "zz": 5.0})).is_err());
}

#[test]
fn jog_refuses_a_duplicate_axis() {
    assert!(parse_jog(&json!({"x": 5.0, "X": 2.0})).is_err());
}

#[test]
fn ending_the_session_stops_the_terminal_feed_and_the_viewer() {
    let state = AppState::new(None);
    state.set_obico_connected(true);
    state.set_viewing(true);
    state.set_terminal_feed(true);
    end_session(&state);
    let s = state.read();
    assert!(!s.obico_connected);
    assert!(!s.viewing);
    assert!(!s.terminal_feed);
}

/// A command name, its constructor and the outcome in the states idle, printing and paused.
type Case = (&'static str, fn() -> Command, [Result<(), String>; 3]);

/// Dispatches a fresh copy of the command in the given print state.
fn dispatch_in(state: PrintState, make: fn() -> Command) -> Result<(), String> {
    let (mut session, _commands, _janus) = test_session(4);
    session.state.set_print_state(state, Some(1.0), Some(1));
    session.dispatch(make()).map_err(|e| e.to_string())
}

#[test]
fn dispatch_gates_each_command_by_print_state() {
    let refused = |msg: &str| Err(msg.to_string());
    let cases: [Case; 5] = [
        (
            "pause",
            || Command::Pause,
            [refused("not printing"), Ok(()), refused("not printing")],
        ),
        (
            "resume",
            || Command::Resume,
            [refused("not paused"), refused("not paused"), Ok(())],
        ),
        (
            "cancel",
            || Command::Cancel,
            [refused("not printing"), Ok(()), Ok(())],
        ),
        (
            "home",
            || Command::Home(vec![]),
            [Ok(()), refused("printer busy"), refused("printer busy")],
        ),
        (
            "jog",
            || Command::Jog(vec![('X', 1.0)]),
            [Ok(()), refused("printer busy"), refused("printer busy")],
        ),
    ];
    let states = [PrintState::Idle, PrintState::Printing, PrintState::Paused];
    for (name, make, expected) in cases {
        for (state, want) in states.into_iter().zip(expected) {
            assert_eq!(dispatch_in(state, make), want, "{name} while {state:?}");
        }
    }
}

#[test]
fn dispatch_refuses_a_duplicate_cancel_while_printing_or_paused() {
    for state in [PrintState::Printing, PrintState::Paused] {
        let (mut session, _commands, _janus) = test_session(4);
        session.state.set_print_state(state, Some(1.0), Some(1));
        assert!(session.dispatch(Command::Cancel).is_ok());
        assert_eq!(
            session.dispatch(Command::Cancel).map_err(|e| e.to_string()),
            Err("cancel already requested".to_string()),
            "{state:?}"
        );
    }
}

#[test]
fn dispatch_refuses_a_second_pause_before_the_printer_reports_it() {
    let (mut session, _commands, _janus) = test_session(4);
    session
        .state
        .set_print_state(PrintState::Printing, Some(1.0), Some(1));
    assert!(session.dispatch(Command::Pause).is_ok());
    // The print state still says printing because no M27 reply arrived yet.
    assert_eq!(session.state.read().print_state, PrintState::Printing);
    assert_eq!(
        session.dispatch(Command::Pause).map_err(|e| e.to_string()),
        Err("pause already requested".to_string())
    );
}

#[test]
fn dispatch_rolls_back_the_pause_flag_when_the_queue_is_full() {
    let (mut session, _commands, _janus) = test_session(1);
    session
        .state
        .set_print_state(PrintState::Printing, Some(1.0), Some(1));
    assert!(session
        .dispatch(Command::Gcode(vec!["M105".into()]))
        .is_ok());
    assert_eq!(
        session.dispatch(Command::Pause).map_err(|e| e.to_string()),
        Err("command queue full".to_string())
    );
    assert!(!session.state.read().pause_requested());
}
