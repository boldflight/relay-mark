//! Deterministic layer composition over already-authorized contributions, and
//! renderer capability negotiation. Neither authorizes anything.

use std::cmp::Ordering;
use std::collections::HashSet;

use serde_json::{Value, json};

use crate::json::{self, locale_compare};
use crate::node_kind::is_block_node;
use crate::registry::directive_for_type;

fn diagnostic(level: &str, code: &str, message: String) -> Value {
    json!({"level": level, "code": code, "message": message})
}

fn rank_then_id(left: &Value, right: &Value) -> Ordering {
    let rank = |v: &Value| v.get("rank").and_then(Value::as_f64).filter(|r| *r != 0.0).unwrap_or(0.0);
    let id = |v: &Value| match v.get("id") {
        Some(value) if json::truthy(Some(value)) => match value {
            Value::String(text) => text.clone(),
            other => json::stringify(other),
        },
        _ => String::new(),
    };
    let difference = rank(left) - rank(right);
    if difference != 0.0 && !difference.is_nan() {
        return if difference < 0.0 { Ordering::Less } else { Ordering::Greater };
    }
    locale_compare(&id(left), &id(right))
}

fn label(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(text)) if !text.is_empty() => text.clone(),
        Some(other) if json::truthy(Some(other)) => json::stringify(other),
        _ => "unknown".into(),
    }
}

/// `composeLayerContributions(layers)` → `{type, items, diagnostics}`.
pub fn compose_layers(layers: &Value) -> Value {
    let mut diagnostics = Vec::new();
    let mut items: Vec<Value> = Vec::new();
    let mut ordered: Vec<&Value> = layers.as_array().map(|l| l.iter().collect()).unwrap_or_default();
    ordered.sort_by(|a, b| rank_then_id(a, b));
    for layer in ordered {
        let role = layer.get("role").and_then(Value::as_str).unwrap_or_default();
        if !["authored", "source", "generated", "discussion", "ink"].contains(&role) {
            diagnostics.push(diagnostic("error", "relaymark.layer.role", format!("Layer '{}' has an unsupported semantic role.", label(layer.get("id")))));
            continue;
        }
        let mut layer_items: Vec<&Value> = layer.get("items").and_then(Value::as_array).map(|i| i.iter().collect()).unwrap_or_default();
        layer_items.sort_by(|a, b| rank_then_id(a, b));
        for item in layer_items {
            let block = item.get("block").unwrap_or(&Value::Null);
            if !is_block_node(block) {
                diagnostics.push(diagnostic(
                    "error",
                    "relaymark.layer.block",
                    format!("Layer item '{}' must contain one RelayMark block.", label(item.get("id"))),
                ));
                continue;
            }
            let mut contribution = serde_json::Map::new();
            for (key, value) in [("layer_id", layer.get("id")), ("layer_role", layer.get("role")), ("item_id", item.get("id")), ("block", Some(block))] {
                if let Some(value) = value {
                    contribution.insert(key.into(), value.clone());
                }
            }
            let contribution = Value::Object(contribution);
            let placement = item.get("placement").filter(|p| json::truthy(Some(p)));
            let Some(placement) = placement.filter(|p| p.get("kind").and_then(Value::as_str) != Some("slot")) else {
                items.push(contribution);
                continue;
            };
            let kind = placement.get("kind").and_then(Value::as_str).unwrap_or_default();
            let state = placement.get("anchor_state").map_or(Some("present"), Value::as_str).unwrap_or("");
            let fallback = placement.get("fallback").map_or(Some("unresolved"), Value::as_str).unwrap_or("");
            if !["before", "after", "slot"].contains(&kind)
                || !["present", "absent", "stale", "undisclosed"].contains(&state)
                || !["append_to_layer", "omit", "unresolved"].contains(&fallback)
            {
                diagnostics.push(diagnostic(
                    "error",
                    "relaymark.layer.placement",
                    format!("Layer item '{}' has invalid placement metadata.", label(item.get("id"))),
                ));
                continue;
            }
            let anchor = placement.get("anchor").and_then(|a| a.get("block_id"));
            let found = if state == "present" { items.iter().position(|existing| existing["block"].get("id") == anchor) } else { None };
            if let Some(index) = found {
                items.insert(if kind == "before" { index } else { index + 1 }, contribution);
                continue;
            }
            let item_id = item.get("id").map(|v| v.as_str().map_or_else(|| json::stringify(v), str::to_owned)).unwrap_or_else(|| "undefined".into());
            match fallback {
                "append_to_layer" => {
                    let last = items.iter().rposition(|existing| existing.get("layer_id") == contribution.get("layer_id"));
                    items.insert(last.map_or(items.len(), |i| i + 1), contribution);
                    diagnostics.push(diagnostic(
                        "warning",
                        "relaymark.layer.anchor_fallback",
                        format!("Layer item '{item_id}' used append_to_layer because its anchor is {state}."),
                    ));
                }
                "omit" => diagnostics.push(diagnostic(
                    "warning",
                    "relaymark.layer.anchor_omitted",
                    format!("Layer item '{item_id}' was omitted because its anchor is {state}."),
                )),
                _ => diagnostics.push(diagnostic(
                    "error",
                    "relaymark.layer.anchor_unresolved",
                    format!("Layer item '{item_id}' remains unresolved because its anchor is {state}."),
                )),
            }
        }
    }
    json!({"type": "relaymark.composed_paper", "items": items, "diagnostics": diagnostics})
}

/// Registry-owned renderer requirements and the deterministic fallback for
/// every block a renderer cannot support.
pub fn negotiate_capabilities(document: &Value, supported: &[&str]) -> Vec<Value> {
    let supported: HashSet<&str> = supported.iter().copied().collect();
    let mut resolutions = Vec::new();
    fn visit(blocks: &[Value], visitor: &mut dyn FnMut(&Value)) {
        for block in blocks {
            visitor(block);
            let children: Vec<Value> = block.get("content").and_then(Value::as_array).into_iter().flatten().filter(|c| is_block_node(c)).cloned().collect();
            visit(&children, visitor);
        }
    }
    let blocks = document.get("blocks").and_then(Value::as_array).map(Vec::as_slice).unwrap_or(&[]);
    visit(blocks, &mut |block| {
        let Some(directive) = block.get("type").and_then(Value::as_str).and_then(directive_for_type) else { return };
        let Some(capability) = directive.capability() else { return };
        let fallback = directive.fallback().filter(|f| ["children", "plain_text", "summary", "omit"].contains(f)).unwrap_or("plain_text");
        let render = supported.contains(capability);
        resolutions
            .push(json!({"block_id": block.get("id"), "capability": capability, "supported": render, "disposition": if render { "render" } else { fallback }}));
    });
    resolutions
}
