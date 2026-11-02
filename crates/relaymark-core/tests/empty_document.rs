//! The empty document: an empty fragment, an empty AST and an empty body agree.
//! spec/relaymark/editor/empty-document-v1.json is run here, by the Elixir adapter and by Swift.

use relaymark_core as rm;
use serde_json::Value;

#[test]
fn every_shared_case_answers_as_the_contract_says() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/relaymark/editor/empty-document-v1.json");
    let fixture: Value = serde_json::from_slice(&std::fs::read(path).expect("fixture")).expect("json");
    let cases = fixture["cases"].as_array().expect("cases");
    assert_eq!(cases.len(), 4);
    for case in cases {
        let (job, name) = (case["job"].as_str().expect("job"), &case["name"]);
        let input = serde_json::to_vec(&case["input"]).expect("input");
        let answer = rm::jobs::run(job, &input, b"").unwrap_or_else(|e| panic!("{name}: {e}"));
        let actual: Value = serde_json::from_slice(&answer).expect("job output");
        assert_eq!(actual, case["expected"], "{name}");
    }
}

// Keep: a Today paper whose body is empty must still serialize to its stored source and round trip.
#[test]
fn the_empty_document_serializes_and_parses_back() {
    let document: Value = serde_json::json!({"type": "relaymark.document", "blocks": []});
    let source = rm::serialize_document(&document).expect("serialize");
    assert_eq!(rm::parse_document(&source, None).expect("parse")["blocks"], serde_json::json!([]));
}
