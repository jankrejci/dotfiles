//! Tests of the Janus handle re-attach.

use super::{HandleRewriter, MAX_TRACKED};
use serde_json::{json, Value};

const SESSION: u64 = 7;
const HANDLE: u64 = 100;
const FRESH: u64 = 200;

fn parse(raw: &str) -> Value {
    serde_json::from_str(raw).unwrap()
}

fn watch(handle: u64) -> String {
    json!({
        "janus": "message",
        "body": {"request": "watch", "offer_video": true, "id": 1},
        "transaction": "client-watch",
        "session_id": SESSION,
        "handle_id": handle,
    })
    .to_string()
}

fn hangup(sender: u64) -> String {
    json!({"janus": "hangup", "session_id": SESSION, "sender": sender, "reason": "DTLS alert"})
        .to_string()
}

fn attach_success(transaction: &str, id: u64) -> String {
    json!({"janus": "success", "transaction": transaction, "data": {"id": id}}).to_string()
}

fn transaction(raw: &str) -> String {
    parse(raw)["transaction"].as_str().unwrap().to_string()
}

/// Drives a hangup and the following watch and returns the transaction of the bridge attach.
fn hang_up_and_watch(rewriter: &mut HandleRewriter, handle: u64) -> String {
    rewriter.on_janus(&hangup(handle));
    let frames = rewriter.on_client(&watch(HANDLE));
    assert_eq!(frames.len(), 1);
    let attach = parse(&frames[0]);
    assert_eq!(attach["janus"], "attach");
    assert_eq!(attach["plugin"], "janus.plugin.streaming");
    assert_eq!(attach["session_id"], SESSION);
    transaction(&frames[0])
}

/// A rewriter whose client handle is already served by a fresh Janus handle.
fn remapped() -> HandleRewriter {
    let mut rewriter = HandleRewriter::new();
    let txn = hang_up_and_watch(&mut rewriter, HANDLE);
    rewriter.on_janus(&attach_success(&txn, FRESH));
    rewriter
}

#[test]
fn passes_plain_traffic_through() {
    let mut rewriter = HandleRewriter::new();
    let create = json!({"janus": "create", "transaction": "t"}).to_string();
    assert_eq!(rewriter.on_client(&create), vec![create]);
    assert_eq!(rewriter.on_client("not json"), ["not json"]);
    let trickle = json!({"janus": "trickle", "session_id": SESSION, "handle_id": HANDLE});
    let trickle = trickle.to_string();
    assert_eq!(rewriter.on_client(&trickle), vec![trickle]);
    // A watch without an earlier hangup is not the race.
    assert_eq!(rewriter.on_client(&watch(HANDLE)), [watch(HANDLE)]);

    let event = json!({"janus": "event", "sender": HANDLE}).to_string();
    let outcome = rewriter.on_janus(&event);
    assert_eq!(outcome.to_client.as_deref(), Some(event.as_str()));
    assert!(outcome.to_janus.is_empty());
    let outcome = rewriter.on_janus("not json");
    assert_eq!(outcome.to_client.as_deref(), Some("not json"));
    let ack = json!({"janus": "ack", "transaction": "t"}).to_string();
    assert_eq!(rewriter.on_janus(&ack).to_client, Some(ack));
}

#[test]
fn hangup_reaches_the_client() {
    let mut rewriter = HandleRewriter::new();
    let outcome = rewriter.on_janus(&hangup(HANDLE));
    assert_eq!(outcome.to_client, Some(hangup(HANDLE)));
}

#[test]
fn watch_after_hangup_attaches_and_forwards_on_the_new_handle() {
    let mut rewriter = HandleRewriter::new();
    let txn = hang_up_and_watch(&mut rewriter, HANDLE);

    let outcome = rewriter.on_janus(&attach_success(&txn, FRESH));
    assert_eq!(outcome.to_client, None);
    assert_eq!(outcome.to_janus.len(), 2);

    let detach = parse(&outcome.to_janus[0]);
    assert_eq!(detach["janus"], "detach");
    assert_eq!(detach["handle_id"], HANDLE);
    assert_eq!(detach["session_id"], SESSION);

    let forwarded = parse(&outcome.to_janus[1]);
    assert_eq!(forwarded["handle_id"], FRESH);
    assert_eq!(forwarded["transaction"], "client-watch");
    assert_eq!(forwarded["body"]["request"], "watch");
}

#[test]
fn bridge_replies_and_old_handle_events_are_swallowed() {
    let mut rewriter = HandleRewriter::new();
    let txn = hang_up_and_watch(&mut rewriter, HANDLE);
    let outcome = rewriter.on_janus(&attach_success(&txn, FRESH));
    let detach_txn = transaction(&outcome.to_janus[0]);

    let reply = json!({"janus": "success", "transaction": detach_txn}).to_string();
    assert_eq!(rewriter.on_janus(&reply), Default::default());

    let detached = json!({"janus": "detached", "session_id": SESSION, "sender": HANDLE});
    assert_eq!(rewriter.on_janus(&detached.to_string()), Default::default());
    // The retirement ends with the event, a reused id is a new handle.
    let event = json!({"janus": "event", "sender": HANDLE}).to_string();
    assert!(rewriter.on_janus(&event).to_client.is_some());
}

#[test]
fn failed_detach_reply_clears_the_retired_entry() {
    let mut rewriter = HandleRewriter::new();
    let txn = hang_up_and_watch(&mut rewriter, HANDLE);
    let outcome = rewriter.on_janus(&attach_success(&txn, FRESH));
    let detach_txn = transaction(&outcome.to_janus[0]);
    assert!(rewriter.retired.contains_key(&HANDLE));

    let reply = json!({"janus": "error", "transaction": detach_txn, "error": {"code": 458}});
    assert_eq!(rewriter.on_janus(&reply.to_string()), Default::default());
    assert!(rewriter.retired.is_empty());
    assert!(rewriter.retiring.is_empty());
}

#[test]
fn successful_detach_reply_keeps_the_entry_until_detached() {
    let mut rewriter = HandleRewriter::new();
    let txn = hang_up_and_watch(&mut rewriter, HANDLE);
    let outcome = rewriter.on_janus(&attach_success(&txn, FRESH));
    let detach_txn = transaction(&outcome.to_janus[0]);

    let reply = json!({"janus": "success", "transaction": detach_txn}).to_string();
    assert_eq!(rewriter.on_janus(&reply), Default::default());
    assert!(rewriter.retired.contains_key(&HANDLE));
    assert!(rewriter.retiring.is_empty());

    let detached = json!({"janus": "detached", "session_id": SESSION, "sender": HANDLE});
    assert_eq!(rewriter.on_janus(&detached.to_string()), Default::default());
    assert!(rewriter.retired.is_empty());
}

#[test]
fn events_from_the_old_handle_are_swallowed() {
    let mut rewriter = remapped();
    let event = json!({"janus": "event", "sender": HANDLE, "plugindata": {}}).to_string();
    assert_eq!(rewriter.on_janus(&event), Default::default());
}

#[test]
fn replies_from_the_new_handle_carry_the_client_handle() {
    let mut rewriter = remapped();
    let event = json!({"janus": "event", "session_id": SESSION, "sender": FRESH, "jsep": {}});
    let outcome = rewriter.on_janus(&event.to_string());
    let forwarded = parse(&outcome.to_client.unwrap());
    assert_eq!(forwarded["sender"], HANDLE);
    assert_eq!(forwarded["jsep"], json!({}));
}

#[test]
fn client_messages_are_rewritten_to_the_new_handle() {
    let mut rewriter = remapped();
    let trickle = json!({"janus": "trickle", "session_id": SESSION, "handle_id": HANDLE});
    let frames = rewriter.on_client(&trickle.to_string());
    assert_eq!(frames.len(), 1);
    assert_eq!(parse(&frames[0])["handle_id"], FRESH);
}

#[test]
fn second_cycle_remaps_again() {
    let mut rewriter = remapped();
    let next = FRESH + 1;

    let outcome = rewriter.on_janus(&hangup(FRESH));
    assert_eq!(parse(&outcome.to_client.unwrap())["sender"], HANDLE);

    let frames = rewriter.on_client(&watch(HANDLE));
    assert_eq!(parse(&frames[0])["janus"], "attach");
    let outcome = rewriter.on_janus(&attach_success(&transaction(&frames[0]), next));

    let detach = parse(&outcome.to_janus[0]);
    assert_eq!(detach["handle_id"], FRESH);
    assert_eq!(parse(&outcome.to_janus[1])["handle_id"], next);

    let event = json!({"janus": "event", "sender": next}).to_string();
    assert_eq!(
        parse(&rewriter.on_janus(&event).to_client.unwrap())["sender"],
        HANDLE
    );
}

#[test]
fn attach_failure_forwards_the_watch_unchanged() {
    let mut rewriter = HandleRewriter::new();
    let txn = hang_up_and_watch(&mut rewriter, HANDLE);
    let error = json!({
        "janus": "error",
        "transaction": txn,
        "error": {"code": 458, "reason": "Session not found"},
    });
    let outcome = rewriter.on_janus(&error.to_string());
    assert_eq!(outcome.to_client, None);
    assert_eq!(outcome.to_janus, [watch(HANDLE)]);
    // The handle is in use again, so traffic is not rewritten.
    let trickle = json!({"janus": "trickle", "session_id": SESSION, "handle_id": HANDLE});
    assert_eq!(
        parse(&rewriter.on_client(&trickle.to_string())[0])["handle_id"],
        HANDLE
    );
}

#[test]
fn attach_failure_after_a_remap_forwards_the_watch_on_the_current_handle() {
    let mut rewriter = remapped();
    rewriter.on_janus(&hangup(FRESH));
    let frames = rewriter.on_client(&watch(HANDLE));
    let error = json!({
        "janus": "error",
        "transaction": transaction(&frames[0]),
        "error": {"code": 458, "reason": "Session not found"},
    });
    let outcome = rewriter.on_janus(&error.to_string());
    assert_eq!(outcome.to_client, None);
    assert_eq!(outcome.to_janus.len(), 1);
    assert_eq!(parse(&outcome.to_janus[0])["handle_id"], FRESH);
}

#[test]
fn client_detach_keeps_the_mapping_until_the_detached_event() {
    let mut rewriter = remapped();
    let detach = json!({
        "janus": "detach",
        "session_id": SESSION,
        "handle_id": HANDLE,
        "transaction": "client-detach",
    });
    let frames = rewriter.on_client(&detach.to_string());
    assert_eq!(parse(&frames[0])["handle_id"], FRESH);

    // The reply carries no sender and passes through untouched.
    let reply = json!({"janus": "success", "transaction": "client-detach"}).to_string();
    assert_eq!(rewriter.on_janus(&reply).to_client, Some(reply));
    assert!(rewriter.mappings.contains_key(&HANDLE));

    // Janus sends the event later under its own handle id, which the client knows as HANDLE.
    let detached = json!({"janus": "detached", "session_id": SESSION, "sender": FRESH});
    let outcome = rewriter.on_janus(&detached.to_string());
    assert_eq!(parse(&outcome.to_client.unwrap())["sender"], HANDLE);
    assert!(rewriter.mappings.is_empty());
}

#[test]
fn session_timeout_drops_the_mapping() {
    let mut rewriter = remapped();
    let timeout = json!({"janus": "timeout", "session_id": SESSION}).to_string();
    assert_eq!(rewriter.on_janus(&timeout).to_client, Some(timeout));
    assert!(rewriter.mappings.is_empty());
    assert!(rewriter.retired.is_empty());
    let trickle = json!({"janus": "trickle", "session_id": SESSION, "handle_id": HANDLE});
    let trickle = trickle.to_string();
    assert_eq!(rewriter.on_client(&trickle), vec![trickle]);
}

#[test]
fn session_destroy_drops_only_that_session() {
    let mut rewriter = remapped();
    rewriter.on_janus(&json!({"janus": "hangup", "session_id": 8, "sender": 5}).to_string());
    assert_eq!(rewriter.mappings.len(), 2);
    let destroy = json!({"janus": "destroy", "session_id": SESSION, "transaction": "t"});
    rewriter.on_client(&destroy.to_string());
    assert_eq!(rewriter.mappings.len(), 1);
    assert!(rewriter.mappings.contains_key(&5));
}

#[test]
fn tables_are_capped() {
    let mut rewriter = HandleRewriter::new();
    let first = 1000;
    let extra = first + MAX_TRACKED as u64;
    for handle in first..=extra {
        rewriter.on_janus(&hangup(handle));
    }
    assert_eq!(rewriter.mappings.len(), MAX_TRACKED);
    // The handle beyond the cap is untracked, so its watch passes through.
    assert_eq!(rewriter.on_client(&watch(extra)), [watch(extra)]);
    assert!(rewriter.attaching.is_empty());

    let mut rewriter = HandleRewriter::new();
    for handle in first..first + MAX_TRACKED as u64 {
        rewriter.on_janus(&hangup(handle));
        rewriter.on_client(&watch(handle));
    }
    assert_eq!(rewriter.attaching.len(), MAX_TRACKED);
    rewriter.on_janus(&hangup(extra));
    assert_eq!(rewriter.on_client(&watch(extra)), [watch(extra)]);
    assert_eq!(rewriter.attaching.len(), MAX_TRACKED);
}

#[test]
fn second_watch_during_an_attach_is_dropped() {
    let mut rewriter = HandleRewriter::new();
    let txn = hang_up_and_watch(&mut rewriter, HANDLE);
    assert!(rewriter.on_client(&watch(HANDLE)).is_empty());
    assert_eq!(rewriter.attaching.len(), 1);

    // The held watch still completes with exactly one detach of the old handle.
    let outcome = rewriter.on_janus(&attach_success(&txn, FRESH));
    assert_eq!(outcome.to_janus.len(), 2);
    assert_eq!(parse(&outcome.to_janus[0])["janus"], "detach");
    assert_eq!(parse(&outcome.to_janus[1])["handle_id"], FRESH);
}

/// A client detach while the bridge attach is in flight, returning the attach transaction.
fn detach_during_attach(rewriter: &mut HandleRewriter) -> String {
    let txn = hang_up_and_watch(rewriter, HANDLE);
    let detach = json!({
        "janus": "detach",
        "session_id": SESSION,
        "handle_id": HANDLE,
        "transaction": "client-detach",
    });
    let frames = rewriter.on_client(&detach.to_string());
    assert_eq!(parse(&frames[0])["handle_id"], HANDLE);
    txn
}

#[test]
fn attach_reply_after_a_client_detach_detaches_the_new_handle() {
    let mut rewriter = HandleRewriter::new();
    let txn = detach_during_attach(&mut rewriter);

    let outcome = rewriter.on_janus(&attach_success(&txn, FRESH));
    assert_eq!(outcome.to_client, None);
    // The client detached the old handle itself, so only the new one is detached and no watch
    // is forwarded.
    assert_eq!(outcome.to_janus.len(), 1);
    let detach = parse(&outcome.to_janus[0]);
    assert_eq!(detach["janus"], "detach");
    assert_eq!(detach["handle_id"], FRESH);
    assert_eq!(detach["session_id"], SESSION);
    assert!(rewriter.retired.contains_key(&FRESH));
    assert!(!rewriter.mappings.values().any(|m| m.janus == FRESH));

    // The bridge detach and its events stay hidden from the client.
    let reply = json!({"janus": "success", "transaction": transaction(&outcome.to_janus[0])});
    assert_eq!(rewriter.on_janus(&reply.to_string()), Default::default());
    let detached = json!({"janus": "detached", "session_id": SESSION, "sender": FRESH});
    assert_eq!(rewriter.on_janus(&detached.to_string()), Default::default());
    assert!(rewriter.retired.is_empty());
    assert!(rewriter.retiring.is_empty());
}

#[test]
fn failed_attach_after_a_client_detach_forwards_nothing() {
    let mut rewriter = HandleRewriter::new();
    let txn = detach_during_attach(&mut rewriter);
    let error = json!({
        "janus": "error",
        "transaction": txn,
        "error": {"code": 458, "reason": "Session not found"},
    });
    assert_eq!(rewriter.on_janus(&error.to_string()), Default::default());
    assert!(rewriter.retired.is_empty());
    assert!(rewriter.retiring.is_empty());
}
