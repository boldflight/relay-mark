//! Differential replay against the JavaScript reference runtime.
//!
//! `tools/record.mjs` records every outermost call into the reference
//! runtime's exported functions. These tests replay each call that maps to
//! this crate's public API and require the same outcome: the same refusal,
//! or byte-identical output (`JSON.stringify` order included).
//!
//! `tests/reference/js-test-suite.jsonl` (the reference test suite's calls)
//! always runs; a larger recorded corpus runs with
//!
//!     RELAYMARK_ORACLE=/path/calls.jsonl cargo test --release --test differential -- --nocapture

use relaymark_core as rm;
use serde_json::{Map, Value};
use std::collections::BTreeMap;
use std::path::Path;

enum Outcome {
    Value(Value),
    Text(String),
    Refused(String),
}

/// JSON.stringify semantics for recorded values: `undefined` members vanish,
/// `undefined` array items become null. `None` when the value is not
/// representable as JSON input at all.
fn decode(value: &Value) -> Option<Value> {
    match value {
        Value::Object(map) if map.contains_key("$undefined") => Some(Value::Null),
        Value::Object(map) if map.contains_key("$number") || map.contains_key("$unrecordable") || map.contains_key("$bytes") => None,
        Value::Object(map) => {
            let mut out = Map::new();
            for (key, item) in map {
                if item.get("$undefined").is_some() {
                    continue;
                }
                out.insert(key.clone(), decode(item)?);
            }
            Some(Value::Object(out))
        }
        Value::Array(items) => items.iter().map(decode).collect::<Option<Vec<_>>>().map(Value::Array),
        other => Some(other.clone()),
    }
}

fn bytes(value: &Value) -> Option<Vec<u8>> {
    use base64::Engine;
    let encoded = value.get("$bytes")?.as_str()?;
    base64::engine::general_purpose::STANDARD.decode(encoded).ok()
}

fn namespace(options: Option<&Value>) -> Option<String> {
    options.and_then(|o| o.get("namespace")).and_then(Value::as_str).map(str::to_owned)
}

fn result<T>(r: rm::Result<T>, ok: impl FnOnce(T) -> Outcome) -> Outcome {
    match r {
        Ok(v) => ok(v),
        Err(e) => Outcome::Refused(e.message().to_owned()),
    }
}

/// Replays one recorded call; `None` when it does not map to the public API.
fn replay(name: &str, raw: &[Value]) -> Option<Outcome> {
    let arg = |i: usize| raw.get(i).and_then(decode);
    let text = |i: usize| raw.get(i).and_then(Value::as_str).map(str::to_owned);
    Some(match name {
        "document-source.parseDocument" => {
            let source = text(0)?;
            let ns = namespace(arg(1).as_ref());
            result(rm::parse_document(&source, ns.as_deref()), Outcome::Value)
        }
        "document-source.serializeDocument" => result(rm::serialize_document(&arg(0)?), Outcome::Text),
        "document-source.projectDocumentMarkdown" => result(rm::project_markdown(&arg(0)?), Outcome::Text),
        "document-source.renderDocument" => result(rm::render_html(&arg(0)?), Outcome::Text),
        "document-source.paperDocumentDestinations" => result(rm::paper_destinations(&arg(0)?), |v| Outcome::Value(Value::Array(v))),
        "document-source.importDocument" => {
            let ns = namespace(arg(1).as_ref())?;
            result(rm::import::document(&arg(0)?, &ns), Outcome::Value)
        }
        "document-source.importDocumentSource" => {
            let ns = namespace(arg(1).as_ref())?;
            result(rm::import::source(&text(0)?, &ns), Outcome::Value)
        }
        "document-source.importDocumentSnapshot" => {
            let ns = namespace(arg(1).as_ref())?;
            result(rm::import::snapshot(&arg(0)?, &ns), Outcome::Value)
        }
        "document-source.importFormPublication" => {
            let options = arg(1)?;
            let ns = options.get("namespace").and_then(Value::as_str)?.to_owned();
            let retained = options.get("source").and_then(Value::as_str).map(str::to_owned);
            result(rm::import::form_publication(&arg(0)?, &ns, retained.as_deref()), Outcome::Value)
        }
        "document-snapshot.documentToSnapshot" => result(rm::document_to_snapshot(&arg(0)?), Outcome::Value),
        "document-snapshot.snapshotToDocument" => result(rm::snapshot_to_document(&arg(0)?), Outcome::Value),
        "document-snapshot.normalizeDocument" => result(rm::normalize_document(&arg(0)?), Outcome::Value),
        "document-snapshot.importAggregateSettingsSnapshot" => result(rm::import::aggregate_settings_snapshot(&arg(0)?), Outcome::Value),
        "document-adapter.relayMarkToProseMirror" => result(rm::document_to_prosemirror(&arg(0)?), Outcome::Value),
        "document-adapter.proseMirrorToRelayMark" => result(rm::prosemirror_to_document(&arg(0)?), Outcome::Value),
        "document-inline.validateTextAttributes" => result(rm::validate_text_attributes(&arg(0)?), |()| Outcome::Value(Value::Bool(true))),
        "validator.validateDocument" => {
            let context = arg(1).unwrap_or(Value::Object(Map::new()));
            Outcome::Value(Value::Array(rm::validate(&arg(0)?, &context)))
        }
        "validator.validateDirectiveNode" => Outcome::Value(Value::Array(rm::validate_directive(&arg(0)?))),
        "runtime.compileRelayMark" => Outcome::Value(rm::compile(&text(0)?)),
        "serializer.serializeRelayMark" => result(rm::serialize_source(&arg(0)?), Outcome::Text),
        "projections.projectManifest" => {
            let diagnostics = arg(1).and_then(|d| d.as_array().cloned()).unwrap_or_default();
            Outcome::Value(rm::project_manifest(&arg(0)?, &diagnostics))
        }
        "projections.toPlainText" => Outcome::Text(rm::plain_text(&arg(0)?)),
        "composition.composeLayerContributions" => Outcome::Value(rm::compose_layers(&arg(0)?)),
        "capabilities.negotiateRendererCapabilities" => {
            let supported: Vec<String> = arg(1)?.as_array()?.iter().filter_map(|s| s.as_str().map(str::to_owned)).collect();
            let supported: Vec<&str> = supported.iter().map(String::as_str).collect();
            Outcome::Value(Value::Array(rm::negotiate_capabilities(&arg(0)?, &supported)))
        }
        "transport.validateTransportedAgentAnswerPair" => {
            let document = bytes(raw.first()?)?;
            let manifest = bytes(raw.get(1)?)?;
            let context = arg(2).unwrap_or(Value::Object(Map::new()));
            result(rm::validate_transported_agent_answer_pair(&document, &manifest, &context), Outcome::Value)
        }
        _ => return None,
    })
}

/// The calls the reference runtime's own test suite makes, recorded once with
/// `tools/record.mjs`: an oracle that outlives the JavaScript implementation.
#[test]
fn replays_the_reference_test_suite() {
    replay_file(&Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/reference/js-test-suite.jsonl"));
}

/// Any further recorded corpus (see `tools/corpus.mjs`).
#[test]
fn replays_a_recorded_corpus() {
    match std::env::var("RELAYMARK_ORACLE") {
        Ok(path) => replay_file(Path::new(&path)),
        Err(_) => eprintln!("RELAYMARK_ORACLE unset; skipping corpus replay"),
    }
}

fn replay_file(path: &Path) {
    let lines = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    let mut passed: BTreeMap<String, usize> = BTreeMap::new();
    let mut unmapped: BTreeMap<String, usize> = BTreeMap::new();
    let mut failures = Vec::new();
    for (number, line) in lines.lines().enumerate() {
        // Lone UTF-16 surrogates have no Rust string form; such calls cannot
        // reach this crate through any binding.
        let Ok(call) = serde_json::from_str::<Value>(line) else {
            *unmapped.entry("(lone surrogate, not representable)".to_owned()).or_default() += 1;
            continue;
        };
        let name = call["fn"].as_str().unwrap_or_default();
        let args = call["args"].as_array().cloned().unwrap_or_default();
        let Ok(outcome) = std::panic::catch_unwind(|| replay(name, &args)) else {
            failures.push(format!("line {} {name}: PANIC", number + 1));
            continue;
        };
        let Some(outcome) = outcome else {
            *unmapped.entry(name.to_owned()).or_default() += 1;
            continue;
        };
        let expected_ok = call["ok"].as_bool().unwrap_or(false);
        let mismatch = match (&outcome, expected_ok) {
            (Outcome::Refused(_), false) => None,
            (Outcome::Refused(reason), true) => Some(format!("refused ({reason}); reference succeeded")),
            (_, false) => Some(format!("succeeded; reference refused ({})", call["error"])),
            (Outcome::Text(actual), true) => {
                let expected = call["value"].as_str().unwrap_or_default();
                (actual != expected).then(|| first_difference(expected, actual))
            }
            (Outcome::Value(actual), true) => {
                let expected = rm::to_json(&decode(&call["value"]).unwrap_or(Value::Null));
                let actual = rm::to_json(actual);
                (actual != expected).then(|| first_difference(&expected, &actual))
            }
        };
        match mismatch {
            None => *passed.entry(name.to_owned()).or_default() += 1,
            Some(reason) => failures.push(format!("line {} {name}: {reason}", number + 1)),
        }
    }
    eprintln!("{}\nmatched: {passed:#?}\nnot replayed (outside the public API): {unmapped:#?}", path.display());
    for failure in &failures {
        eprintln!("MISMATCH {failure}");
    }
    assert!(failures.is_empty(), "{} differential mismatches", failures.len());
}

fn first_difference(expected: &str, actual: &str) -> String {
    let at = expected.char_indices().zip(actual.chars()).find(|((_, e), a)| e != a).map(|((i, _), _)| i).unwrap_or(expected.len().min(actual.len()));
    let window = |s: &str| {
        let start = s.floor_char_boundary(at.saturating_sub(60));
        let end = s.ceil_char_boundary((at + 60).min(s.len()));
        s[start..end].to_owned()
    };
    format!("differs at byte {at}\n  expected …{}…\n  actual   …{}…", window(expected), window(actual))
}
