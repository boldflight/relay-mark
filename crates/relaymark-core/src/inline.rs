//! Canonical text runs and inline atoms. In the AST each mark wraps exactly one
//! child in schema order; in the editor model it is a flat mark list.

use std::sync::OnceLock;

use regex::Regex;
use serde_json::{Value, json};

use crate::error::{Result, bail};
use crate::json::{self, Map};
use crate::links::{link_attributes, link_properties, safe_link_href, validate_link_attributes};

/// Editor text marks in rank order.
pub const TEXT_MARKS: [&str; 10] = ["link", "bold", "code", "italic", "strike", "underline", "highlight", "superscript", "subscript", "ai_authored"];

/// The AST wrapper type for each editor mark.
pub fn ast_type_for_mark(mark: &str) -> Option<&'static str> {
    Some(match mark {
        "link" => "link",
        "bold" => "strong",
        "code" => "code_span",
        "italic" => "emphasis",
        "strike" => "strikethrough",
        "underline" => "underline",
        "highlight" => "highlight",
        "superscript" => "superscript",
        "subscript" => "subscript",
        "ai_authored" => "ai_authored",
        _ => return None,
    })
}

fn mark_for_ast_type(ast: &str) -> Option<&'static str> {
    TEXT_MARKS.iter().copied().find(|mark| ast_type_for_mark(mark) == Some(ast))
}

pub fn mark_rank(mark: &str) -> Option<usize> {
    TEXT_MARKS.iter().position(|m| *m == mark)
}

fn object<'a>(value: &'a Value, label: &str) -> Result<&'a Map> {
    match value.as_object() {
        Some(map) => Ok(map),
        None => bail!("Invalid {label}"),
    }
}

fn keys(value: &Value, allowed: &[&str], label: &str) -> Result<()> {
    for key in object(value, label)?.keys() {
        if !allowed.contains(&key.as_str()) {
            bail!("Unsupported {label} field: {key}");
        }
    }
    Ok(())
}

/// An agent run that wrote the text. Only servers add it.
fn run_id(attrs: &Value) -> Result<String> {
    keys(attrs, &["run_id"], "ai_authored attrs")?;
    match attrs.get("run_id").and_then(Value::as_str) {
        Some(id) if !id.is_empty() && json::utf16_len(id) <= 64 => Ok(id.to_owned()),
        _ => bail!("Invalid ai_authored run_id"),
    }
}

fn href(value: Option<&Value>) -> Result<String> {
    match value.and_then(Value::as_str) {
        Some(href) if safe_link_href(href) => Ok(href.to_owned()),
        _ => bail!("Invalid link href"),
    }
}

/// Typing attributes use the same full mark and link validator as XML.
pub fn validate_text_attributes(attributes: &Value) -> Result<()> {
    keys(attributes, &TEXT_MARKS, "typing attributes")?;
    let mut marks = Vec::new();
    for mark in TEXT_MARKS {
        let Some(value) = attributes.get(mark) else { continue };
        let value = object(value, "typing mark")?;
        if mark == "link" || mark == "ai_authored" {
            marks.push(json!({"type": mark, "attrs": value}));
        } else if !value.is_empty() {
            bail!("Unsupported typing mark attrs");
        } else {
            marks.push(json!({"type": mark}));
        }
    }
    map_inline(&json!({"type": "text", "text": "x", "marks": marks}))?;
    Ok(())
}

/// Editor inline node to AST inline node.
pub fn map_inline(node: &Value) -> Result<Value> {
    object(node, "inline")?;
    let kind = json::str_field(node, "type");
    if matches!(kind, Some("relayReference" | "relayTag")) {
        return map_atom(node);
    }
    if kind == Some("hardBreak") {
        keys(node, &["type"], "hardBreak")?;
        return Ok(json!({"type": "hard_break"}));
    }
    keys(node, &["type", "text", "marks"], "text")?;
    let text = match (kind, node.get("text").and_then(Value::as_str)) {
        (Some("text"), Some(text)) if !text.is_empty() => text,
        _ => bail!("Expected nonempty text"),
    };
    let empty = Vec::new();
    let marks = match node.get("marks") {
        None | Some(Value::Null) => &empty,
        Some(Value::Array(marks)) => marks,
        Some(_) => bail!("Invalid text marks"),
    };
    let mut previous: Option<usize> = None;
    for mark in marks {
        keys(mark, &["type", "attrs"], "mark")?;
        let name = json::str_field(mark, "type").unwrap_or("");
        let rank = mark_rank(name);
        if rank.is_none() || rank <= previous || (name == "code" && marks.len() != 1) {
            bail!("Unsupported or noncanonical text marks");
        }
        previous = rank;
        let attrs = mark.get("attrs");
        match name {
            "link" => {
                validate_link_attributes(attrs.unwrap_or(&Value::Null))?;
            }
            "ai_authored" => {
                run_id(attrs.unwrap_or(&Value::Null))?;
            }
            _ if attrs.is_some() => bail!("Unsupported {name} attrs"),
            _ => {}
        }
    }
    let mut result = json!({"type": "text", "text": text});
    for mark in marks.iter().rev() {
        let name = json::str_field(mark, "type").unwrap_or("");
        let mut wrapper = Map::new();
        wrapper.insert("type".into(), Value::String(ast_type_for_mark(name).unwrap_or(name).to_owned()));
        if name == "link" {
            let attrs = &mark["attrs"];
            wrapper.insert("href".into(), Value::String(href(attrs.get("href"))?));
            let props = link_properties(attrs)?;
            if !props.is_empty() {
                wrapper.insert("props".into(), Value::Object(props));
            }
        }
        if name == "ai_authored" {
            wrapper.insert("run_id".into(), Value::String(run_id(&mark["attrs"])?));
        }
        wrapper.insert("content".into(), Value::Array(vec![result]));
        result = Value::Object(wrapper);
    }
    Ok(result)
}

/// AST inline node to editor inline node.
pub fn unmap_inline(node: &Value) -> Result<Value> {
    object(node, "inline")?;
    let kind = json::str_field(node, "type");
    if matches!(kind, Some("relay.entity_ref" | "relay.tag_ref")) {
        return unmap_atom(node);
    }
    if kind == Some("hard_break") {
        keys(node, &["type"], "hard_break")?;
        return Ok(json!({"type": "hardBreak"}));
    }
    let mut marks: Vec<Value> = Vec::new();
    let mut cursor = node;
    let mut previous: Option<usize> = None;
    while json::str_field(cursor, "type") != Some("text") {
        let pm = json::str_field(cursor, "type").and_then(mark_for_ast_type);
        let rank = pm.and_then(mark_rank);
        let first_child_is_text =
            cursor.get("content").and_then(Value::as_array).and_then(|c| c.first()).is_some_and(|c| json::str_field(c, "type") == Some("text"));
        if rank.is_none() || rank <= previous || (pm == Some("code") && (!marks.is_empty() || !first_child_is_text)) {
            bail!("Unsupported or noncanonical inline wrapper");
        }
        let pm = pm.unwrap_or_default();
        previous = rank;
        let allowed: &[&str] = match pm {
            "link" => &["type", "href", "props", "content"],
            "ai_authored" => &["type", "run_id", "content"],
            _ => &["type", "content"],
        };
        keys(cursor, allowed, "inline wrapper")?;
        let Some(content) = cursor.get("content").and_then(Value::as_array).filter(|c| c.len() == 1) else { bail!("Inline wrapper requires one child") };
        marks.push(match pm {
            "link" => json!({"type": "link", "attrs": link_attributes(&href(cursor.get("href"))?, cursor.get("props"))?}),
            "ai_authored" => {
                let id = run_id(&json!({"run_id": cursor.get("run_id").cloned().unwrap_or(Value::Null)}))?;
                json!({"type": "ai_authored", "attrs": {"run_id": id}})
            }
            _ => json!({"type": pm}),
        });
        cursor = &content[0];
        object(cursor, "inline child")?;
    }
    keys(cursor, &["type", "text"], "text")?;
    let text = match cursor.get("text").and_then(Value::as_str) {
        Some(text) if !text.is_empty() => text,
        _ => bail!("Expected nonempty text"),
    };
    let mut result = Map::new();
    result.insert("type".into(), Value::String("text".into()));
    if !marks.is_empty() {
        result.insert("marks".into(), Value::Array(marks));
    }
    result.insert("text".into(), Value::String(text.to_owned()));
    Ok(Value::Object(result))
}

// ---- Inline atoms: identity-bearing references and tags ----

fn re(cell: &'static OnceLock<Regex>, pattern: &str) -> &'static Regex {
    cell.get_or_init(|| Regex::new(pattern).expect("static pattern"))
}

fn uuid_v(value: &str) -> bool {
    static UUID: OnceLock<Regex> = OnceLock::new();
    re(&UUID, r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$").is_match(value)
}

fn entity_type_name(value: &str) -> bool {
    static TYPE: OnceLock<Regex> = OnceLock::new();
    re(&TYPE, r"^[A-Z][A-Za-z0-9]*(?: [A-Z][A-Za-z0-9]*)*$").is_match(value)
}

fn tag_name(value: &str) -> bool {
    static TAG: OnceLock<Regex> = OnceLock::new();
    re(&TAG, r"^[a-z0-9][a-z0-9_-]*$").is_match(value)
}

fn identity(id: Option<&Value>) -> Result<String> {
    match id.and_then(Value::as_str) {
        Some(id) if uuid_v(id) => Ok(id.to_owned()),
        _ => bail!("Invalid canonical atom UUID"),
    }
}

/// Canonical `[[Type: id | label]]` source for an inline entity reference.
pub fn build_entity_reference_source(entity_type: Option<&Value>, entity_id: Option<&Value>, label: Option<&Value>) -> Result<String> {
    let (Some(kind), Some(label)) = (entity_type.and_then(Value::as_str), label.and_then(Value::as_str)) else {
        bail!("Invalid authored reference label or type")
    };
    if !entity_type_name(kind) || kind == "Tag" || label.is_empty() {
        bail!("Invalid authored reference label or type");
    }
    let quoted = label != json::js_trim(label) || label.chars().any(|c| matches!(c, '\r' | '\n' | '[' | ']' | '"' | '\\' | '`' | '*' | '_' | '<' | '>' | '!'));
    // Escaped UTF-16 JSON avoids CommonMark consuming syntax inside an atomic label.
    let encoded = if quoted {
        let mut out = String::from("\"");
        for unit in label.encode_utf16() {
            out.push_str(&format!("\\u{unit:04x}"));
        }
        out.push('"');
        out
    } else {
        label.to_owned()
    };
    Ok(format!("[[{kind}: {} | {encoded}]]", identity(entity_id)?))
}

fn tag_source(id: Option<&Value>, name: Option<&Value>) -> Result<String> {
    match name.and_then(Value::as_str) {
        Some(name) if tag_name(name) => Ok(format!("[[Tag: {} | #{name}]]", identity(id)?)),
        _ => bail!("Invalid authored tag name"),
    }
}

fn source_matches(expected: Result<String>, actual: Option<&Value>) -> bool {
    matches!((expected, actual.and_then(Value::as_str)), (Ok(expected), Some(actual)) if expected == actual)
}

pub fn map_atom(node: &Value) -> Result<Value> {
    keys(node, &["type", "attrs"], "atom")?;
    let attrs = node.get("attrs").unwrap_or(&Value::Null);
    match json::str_field(node, "type") {
        Some("relayReference") => {
            keys(attrs, &["entityType", "entityId", "label", "source", "status", "subtitle"], "reference attrs")?;
            let hydrated = !json::is_nullish(attrs.get("status")) || !json::is_nullish(attrs.get("subtitle"));
            let expected = build_entity_reference_source(attrs.get("entityType"), attrs.get("entityId"), attrs.get("label"));
            if hydrated || !source_matches(expected, attrs.get("source")) {
                bail!("Unsupported reference hydration or source");
            }
            Ok(json!({"type": "relay.entity_ref", "id": attrs["entityId"], "label": attrs["label"],
                "props": {"entityType": attrs["entityType"], "source": attrs["source"]}}))
        }
        Some("relayTag") => {
            keys(attrs, &["id", "name", "color", "source"], "tag attrs")?;
            if !json::is_nullish(attrs.get("color")) || !source_matches(tag_source(attrs.get("id"), attrs.get("name")), attrs.get("source")) {
                bail!("Unsupported tag color or source");
            }
            let name = attrs["name"].as_str().unwrap_or_default();
            Ok(json!({"type": "relay.tag_ref", "id": attrs["id"], "label": format!("#{name}"),
                "props": {"name": name, "source": attrs["source"]}}))
        }
        other => bail!("Unsupported inline atom {}", other.unwrap_or("undefined")),
    }
}

pub fn unmap_atom(node: &Value) -> Result<Value> {
    match json::str_field(node, "type") {
        Some("relay.entity_ref") => {
            keys(node, &["type", "id", "label", "props"], "reference")?;
            let props = node.get("props").unwrap_or(&Value::Null);
            keys(props, &["entityType", "source"], "reference props")?;
            if !source_matches(build_entity_reference_source(props.get("entityType"), node.get("id"), node.get("label")), props.get("source")) {
                bail!("Reference source mismatch");
            }
            Ok(json!({"type": "relayReference", "attrs": {"entityType": props["entityType"], "entityId": node["id"],
                "label": node["label"], "source": props["source"]}}))
        }
        Some("relay.tag_ref") => {
            keys(node, &["type", "id", "label", "props"], "tag")?;
            let props = node.get("props").unwrap_or(&Value::Null);
            keys(props, &["name", "source"], "tag props")?;
            let name = props.get("name").and_then(Value::as_str);
            let label_ok = matches!((name, node.get("label").and_then(Value::as_str)), (Some(n), Some(l)) if l == format!("#{n}"));
            if !label_ok || !source_matches(tag_source(node.get("id"), props.get("name")), props.get("source")) {
                bail!("Tag source mismatch");
            }
            Ok(json!({"type": "relayTag", "attrs": {"id": node["id"], "name": props["name"], "source": props["source"]}}))
        }
        other => bail!("Unsupported inline atom {}", other.unwrap_or("undefined")),
    }
}

/// Canonical `[[...]]` atom source to its AST node, or `None` when not canonical.
pub fn parse_atom_source(source: &str) -> Option<Value> {
    static TAG: OnceLock<Regex> = OnceLock::new();
    static REFERENCE: OnceLock<Regex> = OnceLock::new();
    if let Some(tag) = re(&TAG, r"^\[\[Tag: ([^ ]+) \| #([^\]]+)\]\]$").captures(source) {
        let node = json!({"type": "relayTag", "attrs": {"id": &tag[1], "name": &tag[2], "color": null, "source": source}});
        return map_atom(&node).ok();
    }
    let reference = re(&REFERENCE, r"^\[\[([^:]+): ([^ ]+) \| ([\s\S]+)\]\]$").captures(source)?;
    let raw = &reference[3];
    let label = if raw.starts_with('"') { serde_json::from_str::<Value>(raw).ok()? } else { Value::String(raw.to_owned()) };
    let node = json!({"type": "relayReference", "attrs": {"entityType": &reference[1], "entityId": &reference[2],
        "label": label, "source": source, "status": null, "subtitle": null}});
    map_atom(&node).ok()
}

pub fn source_for_atom(node: &Value) -> Result<String> {
    Ok(unmap_atom(node)?["attrs"]["source"].as_str().unwrap_or_default().to_owned())
}
