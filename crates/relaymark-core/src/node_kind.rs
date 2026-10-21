//! Block and inline discrimination by registered type, never by `id`.

use serde_json::Value;

use crate::registry::directive_for_type;

const INLINE_TYPES: [&str; 13] = [
    "text",
    "hard_break",
    "soft_break",
    "link",
    "emphasis",
    "strong",
    "strikethrough",
    "underline",
    "highlight",
    "superscript",
    "subscript",
    "ai_authored",
    "code_span",
];

pub fn is_inline_node(node: &Value) -> bool {
    let Some(kind) = node.as_object().and_then(|n| n.get("type")).and_then(Value::as_str) else { return false };
    INLINE_TYPES.contains(&kind) || (kind.starts_with("relay.") && kind.ends_with("_ref") && directive_for_type(kind).is_none())
}

pub fn is_block_node(node: &Value) -> bool {
    node.as_object().and_then(|n| n.get("type")).is_some_and(Value::is_string) && !is_inline_node(node)
}
