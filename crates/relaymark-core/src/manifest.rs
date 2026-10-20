//! The manifest projection: actions, mentions, references, forms, sources,
//! claims, comparisons, bindings, layouts and renderer capabilities.

use std::collections::{HashMap, HashSet};

use serde_json::{Value, json};

use crate::json::{self, Map, trim_relay};
use crate::node_kind::{is_block_node, is_inline_node};
use crate::registry::directive_for_type;

/// Plain text for search, embeddings and summaries; references contribute labels.
pub fn to_plain_text(node: &Value) -> String {
    match node {
        Value::Array(items) => items.iter().map(to_plain_text).collect(),
        Value::Object(map) => {
            let kind = map.get("type").and_then(Value::as_str).unwrap_or_default();
            if kind == "text" {
                return map.get("text").and_then(Value::as_str).unwrap_or_default().to_owned();
            }
            if json::truthy(map.get("label")) && kind.starts_with("relay.") && kind.ends_with("_ref") {
                return match &map["label"] {
                    Value::String(label) => label.clone(),
                    other => json::stringify(other),
                };
            }
            map.get("content").and_then(Value::as_array).map(|c| c.iter().map(to_plain_text).collect()).unwrap_or_default()
        }
        _ => String::new(),
    }
}

/// Drop absent fields; `Value::Null` here stands for JavaScript `undefined`
/// only where the reference runtime would have produced it.
fn compact(entries: Vec<(&str, Option<Value>)>) -> Value {
    Value::Object(entries.into_iter().filter_map(|(k, v)| v.map(|v| (k.to_owned(), v))).collect())
}

fn present(block: &Value, key: &str) -> Option<Value> {
    block.get("props").and_then(|p| p.get(key)).cloned()
}

fn or_value(block: &Value, key: &str, default: Value) -> Option<Value> {
    Some(present(block, key).filter(|v| json::truthy(Some(v))).unwrap_or(default))
}

fn trimmed_text(block: &Value) -> String {
    trim_relay(&to_plain_text(block)).to_owned()
}

fn evidence_refs(block: &Value) -> Value {
    if let Some(refs) = block.get("evidence_refs").and_then(Value::as_array).filter(|r| !r.is_empty()) {
        return Value::Array(refs.clone());
    }
    present(block, "evidence").filter(Value::is_array).unwrap_or_else(|| json!([]))
}

fn visit(blocks: &[Value], visitor: &mut dyn FnMut(&Value)) {
    for block in blocks {
        visitor(block);
        let children: Vec<Value> = block.get("content").and_then(Value::as_array).into_iter().flatten().filter(|c| is_block_node(c)).cloned().collect();
        visit(&children, visitor);
    }
}

fn inline_nodes(nodes: &[Value], out: &mut Vec<Value>) {
    for node in nodes {
        if !node.is_object() || is_block_node(node) {
            continue;
        }
        if is_inline_node(node) {
            out.push(node.clone());
        }
        if let Some(children) = node.get("content").and_then(Value::as_array) {
            inline_nodes(children, out);
        }
    }
}

/// `projectManifest(document, diagnostics)`.
pub fn project_manifest(document: &Value, diagnostics: &[Value]) -> Value {
    let resources: HashMap<String, &Value> =
        document.get("resources").and_then(Value::as_array).into_iter().flatten().filter_map(|r| r.get("id").map(|id| (json::stringify(id), r))).collect();
    let mut lists: Vec<(&str, Vec<Value>)> = [
        "actions",
        "mentions",
        "references",
        "forms",
        "sources",
        "claims",
        "comparisons",
        "entity_references",
        "property_sheets",
        "data_views",
        "layouts",
        "capabilities",
    ]
    .into_iter()
    .map(|k| (k, Vec::new()))
    .collect();
    let mut push = |key: &str, value: Value| {
        if let Some((_, items)) = lists.iter_mut().find(|(k, _)| *k == key) {
            items.push(value);
        }
    };
    let blocks = document.get("blocks").and_then(Value::as_array).map(Vec::as_slice).unwrap_or(&[]);
    visit(blocks, &mut |block| {
        let kind = block.get("type").and_then(Value::as_str).unwrap_or_default();
        let directive = directive_for_type(kind);
        let id = block.get("id").cloned();
        if let Some(capability) = directive.and_then(|d| d.capability()) {
            let fallback = directive.and_then(|d| d.fallback()).filter(|f| !f.is_empty()).unwrap_or("plain_text");
            push("capabilities", json!({"block_id": id, "id": capability, "fallback": fallback}));
        }
        match kind {
            "relay.entity_reference" => {
                let text = trimmed_text(block);
                let label = present(block, "label").filter(|l| json::truthy(Some(l))).or_else(|| (!text.is_empty()).then(|| json!(text)));
                push(
                    "entity_references",
                    compact(vec![
                        ("block_id", id.clone()),
                        ("id", present(block, "id")),
                        ("label", label),
                        ("projection", or_value(block, "projection", json!("link"))),
                    ]),
                );
            }
            "relay.property_sheet" => push(
                "property_sheets",
                compact(vec![
                    ("block_id", id.clone()),
                    ("binding", present(block, "binding")),
                    ("fields", or_value(block, "fields", json!([]))),
                    ("title", present(block, "title")),
                    ("presentation", or_value(block, "presentation", json!("stack"))),
                ]),
            ),
            "relay.data_view" => push(
                "data_views",
                compact(vec![
                    ("block_id", id.clone()),
                    ("source", present(block, "source")),
                    ("projection", present(block, "projection")),
                    ("columns", or_value(block, "columns", json!([]))),
                    ("filter", present(block, "filter")),
                    ("sort", or_value(block, "sort", json!([]))),
                    ("group", present(block, "group")),
                    ("limit", present(block, "limit")),
                    ("title", present(block, "title")),
                ]),
            ),
            "relay.layout" => push(
                "layouts",
                compact(vec![
                    ("block_id", id.clone()),
                    ("mode", or_value(block, "mode", json!("one_column"))),
                    ("columns", present(block, "columns")),
                    ("label", present(block, "label")),
                ]),
            ),
            "relay.action_row" => {
                let mut args: Map = present(block, "args").filter(|a| json::truthy(Some(a))).and_then(|a| a.as_object().cloned()).unwrap_or_default();
                args.insert("title".into(), json!(trimmed_text(block)));
                push(
                    "actions",
                    compact(vec![
                        ("block_id", id.clone()),
                        ("proposal_id", present(block, "proposal_id")),
                        ("proposal_record_id", present(block, "proposal_record_id")),
                        ("proposal_revision", present(block, "proposal_revision")),
                        ("action", present(block, "action")),
                        ("target", present(block, "target")),
                        ("destination", present(block, "destination")),
                        ("visibility", present(block, "visibility")),
                        ("review", present(block, "review")),
                        ("decision_id", present(block, "decision_id")),
                        ("execution_id", present(block, "execution_id")),
                        ("undo_id", present(block, "undo_id")),
                        ("evidence_refs", Some(evidence_refs(block))),
                        ("args", Some(Value::Object(args))),
                    ]),
                );
                if let Some(target) = present(block, "target").and_then(|t| t.as_str().map(str::to_owned))
                    && let Some(entity) = target.strip_prefix("entity:")
                {
                    push("mentions", json!({"block_id": id, "kind": "entity", "id": entity, "label": target}));
                }
            }
            "relay.claim" => push(
                "claims",
                compact(vec![
                    ("block_id", id.clone()),
                    ("key", present(block, "key")),
                    ("subject", present(block, "subject")),
                    ("status", or_value(block, "status", json!("unverified"))),
                    ("confidence", present(block, "confidence")),
                    ("evidence_refs", Some(evidence_refs(block))),
                    ("text", Some(json!(trimmed_text(block)))),
                ]),
            ),
            "relay.comparison" => push(
                "comparisons",
                compact(vec![
                    ("block_id", id.clone()),
                    ("title", present(block, "title")),
                    ("subjects", or_value(block, "subjects", json!([]))),
                    ("criteria", or_value(block, "criteria", json!([]))),
                    ("values", or_value(block, "values", json!({}))),
                    ("preferred", present(block, "preferred")),
                    ("layout", or_value(block, "layout", json!("table"))),
                    ("evidence_refs", Some(evidence_refs(block))),
                    ("summary", Some(json!(trimmed_text(block)))),
                ]),
            ),
            "relay.form_question" => push(
                "forms",
                compact(vec![
                    ("block_id", id.clone()),
                    ("key", present(block, "key")),
                    ("label", present(block, "label")),
                    ("field_type", present(block, "field_type")),
                    ("required", or_value(block, "required", json!(false))),
                    ("options", or_value(block, "options", json!([]))),
                ]),
            ),
            "relay.source_bundle" => push(
                "sources",
                compact(vec![
                    ("block_id", id.clone()),
                    ("kind", Some(json!("source_bundle"))),
                    ("source_id", present(block, "id")),
                    ("bundle_revision", present(block, "revision")),
                    ("source_hash", present(block, "source_hash")),
                    ("label", present(block, "title")),
                ]),
            ),
            "relay.evidence_ref" => {
                let source = present(block, "source");
                let resource = source.as_ref().and_then(|s| resources.get(&json::stringify(s)));
                let scripture = (present(block, "source_type").and_then(|t| t.as_str().map(str::to_owned)).as_deref() == Some("scripture")
                    && resource.is_some_and(|r| r.get("type").and_then(Value::as_str) == Some("scripture")))
                .then(|| resource.and_then(|r| r.get("props").cloned()))
                .flatten();
                let excerpt = trimmed_text(block);
                push(
                    "sources",
                    compact(vec![
                        ("block_id", id.clone()),
                        ("kind", Some(json!("evidence_ref"))),
                        ("evidence_id", present(block, "id")),
                        ("source_id", source),
                        ("source_type", present(block, "source_type")),
                        ("source_revision", present(block, "source_revision")),
                        ("selector", present(block, "selector")),
                        ("scope", present(block, "scope")),
                        ("label", present(block, "label")),
                        ("excerpt", (!excerpt.is_empty()).then(|| json!(excerpt))),
                        ("scripture_release", scripture),
                    ]),
                );
            }
            "relay.transcript_segment" => push(
                "sources",
                compact(vec![
                    ("block_id", id.clone()),
                    ("kind", Some(json!("transcript_range"))),
                    ("source_id", present(block, "source")),
                    ("start", present(block, "start")),
                    ("end", present(block, "end")),
                    ("label", present(block, "speaker")),
                ]),
            ),
            "relay.file_ref" => push(
                "sources",
                compact(vec![
                    ("block_id", id.clone()),
                    ("kind", Some(json!("file_ref"))),
                    ("source_id", present(block, "id")),
                    ("uri", present(block, "uri")),
                    ("label", present(block, "label")),
                ]),
            ),
            "relay.note_ref" => {
                let source = present(block, "document").filter(|d| json::truthy(Some(d))).or_else(|| present(block, "block"));
                push(
                    "sources",
                    compact(vec![("block_id", id.clone()), ("kind", Some(json!("note_ref"))), ("source_id", source), ("label", present(block, "label"))]),
                );
            }
            "relay.url_ref" => push(
                "sources",
                compact(vec![("block_id", id.clone()), ("kind", Some(json!("url_ref"))), ("uri", present(block, "url")), ("label", present(block, "label"))]),
            ),
            _ => {}
        }
        let mut inlines = Vec::new();
        inline_nodes(block.get("content").and_then(Value::as_array).map(Vec::as_slice).unwrap_or(&[]), &mut inlines);
        for inline in inlines {
            let inline_kind = inline.get("type").and_then(Value::as_str).unwrap_or_default();
            if inline_kind.starts_with("relay.") && inline_kind.ends_with("_ref") {
                push(
                    "references",
                    compact(vec![
                        ("block_id", id.clone()),
                        ("type", inline.get("type").cloned()),
                        ("id", inline.get("id").cloned()),
                        ("label", inline.get("label").cloned()),
                        ("href", inline.get("href").cloned()),
                    ]),
                );
            }
            if inline_kind == "relay.entity_ref" {
                push(
                    "mentions",
                    compact(vec![
                        ("block_id", id.clone()),
                        ("kind", Some(json!("entity"))),
                        ("id", inline.get("id").cloned()),
                        ("label", inline.get("label").cloned()),
                    ]),
                );
            }
        }
    });
    // The reference literal declares every list, then deletes empty optional
    // ones, so `diagnostics` stays last.
    let mut manifest = Map::from_iter([("type".into(), json!("relaymark.manifest"))]);
    for (key, items) in lists {
        let items = if matches!(key, "mentions" | "references" | "capabilities") { unique(items) } else { items };
        let optional = matches!(key, "entity_references" | "property_sheets" | "data_views" | "layouts" | "capabilities");
        if !(optional && items.is_empty()) {
            manifest.insert(key.to_owned(), Value::Array(items));
        }
    }
    manifest.insert("diagnostics".into(), Value::Array(diagnostics.to_vec()));
    Value::Object(manifest)
}

fn unique(items: Vec<Value>) -> Vec<Value> {
    let mut seen = HashSet::new();
    items.into_iter().filter(|item| seen.insert(json::stringify(item))).collect()
}
