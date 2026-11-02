//! The shared smart-list cases, authored in relay-elixir
//! `test/fixtures/collection_set_v1.json` and vendored byte for byte as
//! spec/relaymark/collection-set-v1.json. Keep: the engine and the web list
//! different members or orders for the same smart list unless both pass these.

use std::path::PathBuf;

use relaymark_core as rm;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

/// The authority's SHA-256. Re-vendoring changes this and the case count together.
const PINNED_SHA256: &str = "c6acd58492a589707e7a63d4033982c5974ca5d634ce333a44c81ea1cc1a408e";
const PINNED_CASES: usize = 36;

fn bytes() -> Vec<u8> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/relaymark/collection-set-v1.json");
    std::fs::read(path).expect("fixture")
}

#[test]
fn the_vendored_fixture_is_the_pinned_authority_copy() {
    let digest: String = Sha256::digest(bytes()).iter().map(|b| format!("{b:02x}")).collect();
    assert_eq!(digest, PINNED_SHA256, "re-vendor from relay-elixir test/fixtures/collection_set_v1.json (spec/relaymark/README.md)");
    let fixture: Value = serde_json::from_slice(&bytes()).expect("json");
    assert_eq!(fixture["cases"].as_array().map(Vec::len), Some(PINNED_CASES));
}

fn evaluate(fixture: &Value, case: &Value) -> Value {
    let mut input = case.clone();
    // A case's own records replace the shared ones.
    input["records"] = case.get("records").unwrap_or(&fixture["records"]).clone();
    if let Some(grouping) = case["groups"].get("grouping") {
        input["grouping"] = grouping.clone();
    }
    rm::edit::collection_set(&input).unwrap_or_else(|e| panic!("{}: {}", case["name"], e.message()))
}

#[test]
fn every_case_lists_what_the_contract_says() {
    let fixture: Value = serde_json::from_slice(&bytes()).expect("json");
    let mut failures = Vec::new();
    for case in fixture["cases"].as_array().expect("cases") {
        let got = evaluate(&fixture, case);
        let actual = json!({"ids": got["ids"], "total": got["total"], "page": got["page"], "page_count": got["page_count"]});
        if actual != case["expect"] {
            failures.push(format!("{}: {actual} != {}", case["name"], case["expect"]));
        }
        if let Some(groups) = case.get("groups") {
            let actual = json!({"descriptors": got["groups"]["descriptors"], "entity_group_keys": got["groups"]["entity_group_keys"]});
            let expected = json!({"descriptors": groups["descriptors"], "entity_group_keys": groups["entity_group_keys"]});
            if actual != expected {
                failures.push(format!("{} (groups): {actual} != {expected}", case["name"]));
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn a_collection_that_is_not_held_is_partial_not_empty() {
    let fixture: Value = serde_json::from_slice(&bytes()).expect("json");
    let case =
        json!({"list": "collection", "entity_id": "missing", "account": null, "params": {}, "page": 1, "page_size": 24, "shell_entity_types": "complete"});
    let got = evaluate(&fixture, &case);
    assert_eq!((got["status"].as_str(), got["total"].is_null(), got["ids"].as_array().map(Vec::len)), (Some("partial"), true, Some(0)));
}

#[test]
fn an_unknown_list_is_refused() {
    let fixture: Value = serde_json::from_slice(&bytes()).expect("json");
    let input = json!({"records": fixture["records"], "list": "bogus"});
    assert!(rm::edit::collection_set(&input).is_err());
}
