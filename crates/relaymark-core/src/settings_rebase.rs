//! Conflict avoidance for a form question's settings without per-key storage.
//!
//! Question and option settings are ONE aggregate `settings` attribute (the
//! October 18 standard-collaboration decision; per-key `settings:<key>`
//! storage killed performance and must never return; Douglas, 2026-11-02).
//! Yjs keeps the last writer's whole attribute, so two people changing
//! different keys of one question at once would lose one change. A client
//! that still holds an unacknowledged settings edit and sees the attribute
//! replaced re-applies the keys it changed onto the incoming value, in one
//! follow-up transaction. The same key changed by both stays the incoming
//! (last writer's) value. See `spec/relaymark/editor/settings-rebase-v1.json`.

use serde_json::{Map, Value};

use crate::{Error, Result};

/// `[base, local, incoming]` to `{settings}`: the settings to write after the
/// incoming change, or `null` when the incoming value already holds every
/// surviving local change (nothing to write). `base` is the value the local
/// edit started from, `local` the value it wrote, `incoming` the value the
/// document holds now. A missing (`null`) settings object is empty, except an
/// `incoming` of `null` (the question is gone): nothing is rebased.
pub(crate) fn rebase(input: &Value) -> Result<Value> {
    let items = match input {
        Value::Array(items) if items.len() == 3 => items,
        _ => return Err(Error::new("Settings rebase takes [base, local, incoming]")),
    };
    let object = |value: &Value| -> Result<Map<String, Value>> {
        match value {
            Value::Null => Ok(Map::new()),
            Value::Object(map) => Ok(map.clone()),
            _ => Err(Error::new("Settings must be an object or null")),
        }
    };
    if items[2].is_null() {
        return Ok(result(None));
    }
    let (base, local, incoming) = (object(&items[0])?, object(&items[1])?, object(&items[2])?);
    let mut merged = incoming.clone();
    let mut keys: Vec<&String> = base.keys().collect();
    keys.extend(local.keys().filter(|key| !base.contains_key(*key)));
    for key in keys {
        let (before, mine, theirs) = (base.get(key), local.get(key), incoming.get(key));
        // Not changed here, or the incoming value already agrees.
        if mine == before || theirs == mine {
            continue;
        }
        // Changed on both sides to different values: the last writer's stays.
        if theirs != before {
            continue;
        }
        match mine {
            Some(value) => {
                merged.insert(key.clone(), value.clone());
            }
            None => {
                merged.shift_remove(key);
            }
        }
    }
    Ok(result((merged != incoming).then_some(merged)))
}

fn result(settings: Option<Map<String, Value>>) -> Value {
    let mut out = Map::new();
    out.insert("settings".to_owned(), settings.map(Value::Object).unwrap_or(Value::Null));
    Value::Object(out)
}
