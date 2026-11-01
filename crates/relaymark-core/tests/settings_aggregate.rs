//! A form question's settings are ONE aggregate `settings` attribute in the
//! collaborative document, as stock y-tiptap and the server store it. Per-key
//! `settings:<key>` fields must never be written, and are refused when read.

use relaymark_core as rm;
use serde_json::{Value, json};

fn settings() -> Value {
    json!({"max_duration": 60, "audio_only": false, "nullable": null, "🌍": {"nested": true}, "": 0})
}

fn document() -> Value {
    json!({
        "type": "relaymark.document",
        "blocks": [{
            "type": "relay.form_question",
            "id": "b00000000000140008000000000000000",
            "props": {"id": "recording", "type": "video_response", "required": false, "points": null, "min": null, "max": null, "settings": settings()},
            "content": [{"type": "paragraph", "id": "b00000000000240008000000000000000", "content": [{"type": "text", "text": "Explain"}]}]
        }]
    })
}

#[test]
fn a_question_snapshot_carries_exactly_one_aggregate_settings_attribute() {
    let snapshot = rm::document_to_snapshot(&document()).expect("snapshot");
    let attributes = snapshot["children"][0]["attributes"].as_object().expect("attributes");
    assert_eq!(attributes["settings"], settings());
    assert_eq!(attributes.keys().filter(|key| key.starts_with("settings")).count(), 1, "{attributes:?}");
    assert_eq!(rm::snapshot_to_document(&snapshot).expect("round trip"), document());
}

#[test]
fn per_key_snapshot_state_is_refused_not_folded() {
    let mut snapshot = rm::document_to_snapshot(&document()).expect("snapshot");
    let attributes = snapshot["children"][0]["attributes"].as_object_mut().expect("attributes");
    attributes.insert("settings".into(), json!(true));
    attributes.insert("settings:bWF4X2R1cmF0aW9u".into(), json!(60));
    assert!(rm::snapshot_to_document(&snapshot).is_err());
}
