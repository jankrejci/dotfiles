//! Transparent handle re-attach that works around a race in Janus.
//!
//! When the Obico tab loses focus the web client stops the stream and Janus answers with a
//! `hangup` event. Janus frees the libnice agent of that handle only in an asynchronous close
//! callback, which waits for the TURN relay allocation to be released and takes a couple of
//! seconds. A `watch` on the same handle that arrives earlier is treated by the Janus core as an
//! update of a PeerConnection that no longer exists. The streaming plugin is left half set up and
//! every later `watch` on that handle fails with "Already watching mountpoint" until the page is
//! reloaded. Upstream master still has the race.
//!
//! A fresh handle has no leftover agent, so after every `hangup` the next `watch` is held back
//! while the bridge attaches a new streaming handle, detaches the stuck one and forwards the
//! `watch` on the new handle. The client keeps using its original handle id, the rewriter
//! translates ids in both directions. It does not depend on how long the TURN release takes.
//!
//! The rewriter is sans-IO, the caller moves the returned frames over the websockets.

use serde_json::{json, Value};
use std::collections::HashMap;
use std::hash::Hash;
use tracing::{debug, info, warn};

/// Upper bound for every table, so a misbehaving client cannot grow them forever. Entries beyond
/// the cap are not tracked and their messages pass through untouched.
const MAX_TRACKED: usize = 64;
/// Marks transactions of frames the bridge sent on its own, so their replies stay hidden from the
/// client.
const BRIDGE_TRANSACTION_PREFIX: &str = "obico-bridge-";
const STREAMING_PLUGIN: &str = "janus.plugin.streaming";

/// The Janus handle that currently serves a handle of the client.
struct Mapping {
    janus: u64,
    session: u64,
    hung_up: bool,
}

/// A `watch` waiting for its new handle.
struct Held {
    client: u64,
    old: u64,
    session: u64,
    watch: Value,
    /// Set when the client detached its handle while the attach was in flight, so the new handle
    /// has no user and the reply must not start a stream on it.
    abandoned: bool,
}

/// Frames produced by one message from Janus.
#[derive(Debug, Default, PartialEq)]
pub struct Outcome {
    pub to_client: Option<String>,
    pub to_janus: Vec<String>,
}

#[derive(Default)]
pub struct HandleRewriter {
    /// Keyed by the handle id the client knows. A mapping outlives the reply to a client detach,
    /// because Janus sends the `detached` event later under the Janus handle id, and only the
    /// mapping translates it back to the client handle. It ends with that event or with the
    /// session, like the entries of `retired`.
    mappings: HashMap<u64, Mapping>,
    /// Keyed by the transaction of the bridge `attach`.
    attaching: HashMap<String, Held>,
    /// Bridge `detach` requests in flight, transaction to the old handle and its session.
    retiring: HashMap<String, (u64, u64)>,
    /// Janus handles the bridge detached, mapped to their session. The client must not see their
    /// events.
    /// After a successful detach the entry ends with the `detached` event and not with the reply.
    /// In `janus_ice_handle_destroy` Janus answers the request first and frees the handle later
    /// from its own loop, so the event can follow the reply by seconds. Dropping the entry on the
    /// reply would let that event reach the client under its own handle id.
    /// A failed detach is answered with an error and no event follows, so the error reply ends the
    /// entry. Ending the session drops it too.
    retired: HashMap<u64, u64>,
    counter: u64,
}

impl HandleRewriter {
    pub fn new() -> Self {
        Self::default()
    }

    /// Takes a frame from the Obico client and returns the frames for Janus.
    pub fn on_client(&mut self, raw: &str) -> Vec<String> {
        let Ok(mut msg) = serde_json::from_str::<Value>(raw) else {
            return vec![raw.to_string()];
        };
        let kind = text(&msg, "janus");
        let session = number(&msg, "session_id");
        let Some(client) = number(&msg, "handle_id") else {
            if let (true, Some(session)) = (kind == "destroy", session) {
                self.drop_session(session);
            }
            return vec![raw.to_string()];
        };
        let Some(mapping) = self.mappings.get(&client) else {
            return vec![raw.to_string()];
        };
        let (janus, hung_up) = (mapping.janus, mapping.hung_up);
        let session = session.unwrap_or(mapping.session);

        // The hang-up flag stays set until the attach reply arrives, so a second watch from the
        // same client would start a second attach and overwrite the first mapping. The held
        // watch starts the stream once its handle is attached, so the duplicate is dropped.
        // The duplicate's transaction gets no reply on purpose, because `on_client` only produces
        // frames for Janus. Whether the Obico client waits on that reply is not known. The held
        // watch is answered normally.
        if hung_up && is_watch(&msg) && self.attaching.values().any(|held| held.client == client) {
            debug!("Janus watch on handle {client} dropped, an attach is already in flight");
            return Vec::new();
        }
        if hung_up && is_watch(&msg) && self.attaching.len() < MAX_TRACKED {
            let transaction = self.next_transaction();
            let attach = json!({
                "janus": "attach",
                "plugin": STREAMING_PLUGIN,
                "session_id": session,
                "transaction": transaction,
            });
            info!("Janus handle {janus} was hung up, attaching a new one for the watch");
            self.attaching.insert(
                transaction,
                Held {
                    client,
                    old: janus,
                    session,
                    watch: msg,
                    abandoned: false,
                },
            );
            return vec![attach.to_string()];
        }

        if kind == "detach" {
            for held in self.attaching.values_mut().filter(|h| h.client == client) {
                held.abandoned = true;
            }
        }
        if janus == client {
            return vec![raw.to_string()];
        }
        set_handle(&mut msg, janus);
        vec![msg.to_string()]
    }

    /// Takes a frame from Janus and returns what goes to the client and back to Janus.
    pub fn on_janus(&mut self, raw: &str) -> Outcome {
        let passthrough = || Outcome {
            to_client: Some(raw.to_string()),
            to_janus: Vec::new(),
        };
        let Ok(mut msg) = serde_json::from_str::<Value>(raw) else {
            return passthrough();
        };
        let kind = text(&msg, "janus");
        let transaction = text(&msg, "transaction");

        if let Some(held) = self.attaching.remove(&transaction) {
            return self.attached(held, &msg);
        }
        if let Some((old, _)) = self.retiring.remove(&transaction) {
            if kind == "error" {
                warn!("Janus failed to detach the old handle {old}: {msg}");
                self.retired.remove(&old);
            }
            return Outcome::default();
        }
        if transaction.starts_with(BRIDGE_TRANSACTION_PREFIX) {
            return Outcome::default();
        }
        if kind == "timeout" {
            if let Some(session) = number(&msg, "session_id") {
                self.drop_session(session);
            }
            return passthrough();
        }
        let Some(sender) = number(&msg, "sender") else {
            return passthrough();
        };

        if self.retired.contains_key(&sender) {
            if kind == "detached" {
                self.retired.remove(&sender);
            }
            return Outcome::default();
        }
        let client = self.client_for(sender);
        match kind.as_str() {
            "hangup" => self.hung_up(client, sender, number(&msg, "session_id")),
            "detached" => {
                self.mappings.remove(&client);
            }
            _ => {}
        }
        if client == sender {
            return passthrough();
        }
        set_sender(&mut msg, client);
        Outcome {
            to_client: Some(msg.to_string()),
            to_janus: Vec::new(),
        }
    }

    /// Finishes a held `watch` once Janus answered the `attach`.
    fn attached(&mut self, held: Held, reply: &Value) -> Outcome {
        let Held {
            client,
            old,
            session,
            mut watch,
            abandoned,
        } = held;
        let new = reply
            .get("data")
            .and_then(|data| number(data, "id"))
            .filter(|_| text(reply, "janus") == "success");
        let Some(new) = new else {
            if abandoned {
                debug!("Janus attach for the detached handle {client} failed, nothing to forward");
                return Outcome::default();
            }
            warn!("Janus refused to attach a new handle, forwarding the watch on the old one: {reply}");
            // After an earlier remap Janus knows the handle as `old`, not as the client id.
            set_handle(&mut watch, old);
            if let Some(mapping) = self.mappings.get_mut(&client) {
                mapping.hung_up = false;
            }
            return Outcome {
                to_client: None,
                to_janus: vec![watch.to_string()],
            };
        };

        // The client detached the old handle itself, so only the new one is left to detach.
        if abandoned {
            info!("Janus handle {client} was detached during the attach, detaching handle {new}");
            return Outcome {
                to_client: None,
                to_janus: vec![self.retire(new, session)],
            };
        }

        insert_bounded(
            &mut self.mappings,
            client,
            Mapping {
                janus: new,
                session,
                hung_up: false,
            },
        );
        set_handle(&mut watch, new);
        let mut to_janus = Vec::new();
        if old != new {
            to_janus.push(self.retire(old, session));
        }
        to_janus.push(watch.to_string());
        Outcome {
            to_client: None,
            to_janus,
        }
    }

    /// Hides a Janus handle from the client and returns the frame that detaches it. The entry
    /// ends as documented on `retired`.
    fn retire(&mut self, handle: u64, session: u64) -> String {
        insert_bounded(&mut self.retired, handle, session);
        let transaction = self.next_transaction();
        insert_bounded(&mut self.retiring, transaction.clone(), (handle, session));
        json!({
            "janus": "detach",
            "session_id": session,
            "handle_id": handle,
            "transaction": transaction,
        })
        .to_string()
    }

    fn hung_up(&mut self, client: u64, janus: u64, session: Option<u64>) {
        if let Some(mapping) = self.mappings.get_mut(&client) {
            mapping.hung_up = true;
            return;
        }
        let Some(session) = session else { return };
        insert_bounded(
            &mut self.mappings,
            client,
            Mapping {
                janus,
                session,
                hung_up: true,
            },
        );
    }

    /// The client handle served by a Janus handle, which is the handle itself while unmapped.
    fn client_for(&self, janus: u64) -> u64 {
        self.mappings
            .iter()
            .find(|(_, mapping)| mapping.janus == janus)
            .map_or(janus, |(client, _)| *client)
    }

    fn drop_session(&mut self, session: u64) {
        self.mappings.retain(|_, m| m.session != session);
        self.attaching.retain(|_, h| h.session != session);
        self.retiring.retain(|_, (_, s)| *s != session);
        self.retired.retain(|_, s| *s != session);
    }

    fn next_transaction(&mut self) -> String {
        self.counter = self.counter.wrapping_add(1);
        format!("{BRIDGE_TRANSACTION_PREFIX}{}", self.counter)
    }
}

fn is_watch(msg: &Value) -> bool {
    text(msg, "janus") == "message"
        && msg
            .get("body")
            .is_some_and(|body| text(body, "request") == "watch")
}

fn text(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn number(value: &Value, key: &str) -> Option<u64> {
    value.get(key).and_then(Value::as_u64)
}

fn set_handle(msg: &mut Value, handle: u64) {
    if let Some(object) = msg.as_object_mut() {
        object.insert("handle_id".to_string(), handle.into());
    }
}

fn set_sender(msg: &mut Value, handle: u64) {
    if let Some(object) = msg.as_object_mut() {
        object.insert("sender".to_string(), handle.into());
    }
}

fn insert_bounded<K: Hash + Eq, V>(map: &mut HashMap<K, V>, key: K, value: V) {
    if map.len() >= MAX_TRACKED && !map.contains_key(&key) {
        return;
    }
    map.insert(key, value);
}

#[cfg(test)]
#[path = "tests/janus_handles.rs"]
mod tests;
