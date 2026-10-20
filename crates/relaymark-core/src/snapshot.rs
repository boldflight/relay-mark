//! Canonical semantic normalization and the portable XML snapshot: the
//! lossless JSON tree of the collaborative `Y.XmlFragment` that native and web
//! replicas exchange with source and rendering.

use base64::Engine as _;
use base64::engine::{DecodePaddingMode, GeneralPurpose, GeneralPurposeConfig};
use serde_json::{Value, json};

use crate::adapter::{to_prosemirror, to_relaymark, validate_json_value};
use crate::error::{Result, bail};
use crate::inline::{TEXT_MARKS, mark_rank};
use crate::json::Map;
use crate::links::link_defaults;
use crate::schema::{ATTRIBUTE_ENCODING_JSON, editor_schema};

const METADATA_KEYS: [&str; 4] = ["frontmatter", "annotations", "resources", "meta"];

/// Canonical semantic AST normalization: text segmentation carries no
/// identity, so adjacent equal runs join; block identities, marks, atom
/// boundaries and envelope values stay exact. Refuses invalid documents.
pub fn normalize_document(document: &Value) -> Result<Value> {
    let prosemirror = to_prosemirror(document)?;
    let normalized = editor_schema().normalize(&prosemirror)?;
    let blocks = to_relaymark(&normalized)?["blocks"].take();
    let mut result = document.as_object().cloned().unwrap_or_default();
    result.insert("blocks".into(), blocks);
    Ok(Value::Object(result))
}

/// Document AST to its portable XML snapshot.
pub fn document_to_snapshot(document: &Value) -> Result<Value> {
    let document = normalize_document(document)?;
    let prosemirror = to_prosemirror(&document)?;
    prosemirror_to_snapshot(&prosemirror, &document)
}

pub fn prosemirror_to_snapshot(prosemirror: &Value, document: &Value) -> Result<Value> {
    fn children(nodes: &[Value]) -> Result<Vec<Value>> {
        let mut result: Vec<Value> = Vec::with_capacity(nodes.len());
        for node in nodes {
            let next = node_snapshot(node)?;
            if next["kind"] == "text"
                && let Some(last) = result.last_mut().filter(|last| last["kind"] == "text")
            {
                let runs = next["delta"].as_array().cloned().unwrap_or_default();
                if let Some(delta) = last["delta"].as_array_mut() {
                    delta.extend(runs)
                }
                continue;
            }
            result.push(next);
        }
        Ok(result)
    }
    fn node_snapshot(node: &Value) -> Result<Value> {
        let kind = node["type"].as_str().unwrap_or_default();
        if kind == "text" {
            let mut attributes = Map::new();
            for mark in node.get("marks").and_then(Value::as_array).into_iter().flatten() {
                let attrs = mark.get("attrs").filter(|a| !a.is_null()).cloned().unwrap_or_else(|| json!({}));
                attributes.insert(mark["type"].as_str().unwrap_or_default().to_owned(), attrs);
            }
            return Ok(json!({"kind": "text", "delta": [{"insert": node["text"], "attributes": attributes}]}));
        }
        let mut attrs = node.get("attrs").and_then(Value::as_object).cloned().unwrap_or_default();
        if attrs.get("relaymarkId").is_some_and(Value::is_null) {
            attrs.shift_remove("relaymarkId");
        }
        let content = node.get("content").and_then(Value::as_array).map(Vec::as_slice).unwrap_or(&[]);
        Ok(json!({"kind": "element", "name": kind, "attributes": encode_attributes(kind, &attrs)?, "children": children(content)?}))
    }
    let content = prosemirror.get("content").and_then(Value::as_array).map(Vec::as_slice).unwrap_or(&[]);
    let mut fragment = Map::new();
    fragment.insert("kind".into(), json!("fragment"));
    fragment.insert("children".into(), Value::Array(content.iter().map(node_snapshot).collect::<Result<_>>()?));
    let metadata: Map = METADATA_KEYS.iter().filter_map(|k| document.get(*k).map(|v| ((*k).to_owned(), v.clone()))).collect();
    if !metadata.is_empty() {
        fragment.insert("metadata".into(), Value::Object(metadata));
    }
    Ok(Value::Object(fragment))
}

fn only(value: &Value, keys: &[&str], message: &str) -> Result<()> {
    match value.as_object() {
        Some(map) if map.keys().all(|key| keys.contains(&key.as_str())) => Ok(()),
        _ => bail!("{message}"),
    }
}

fn schema_defaults(name: &str) -> Vec<(&'static str, Value)> {
    match name {
        "heading" => vec![("headingId", Value::Null)],
        "orderedList" => vec![("start", json!(1)), ("type", Value::Null)],
        "taskItem" => vec![("checked", json!(false)), ("entityId", Value::Null)],
        "codeBlock" => vec![("language", Value::Null)],
        "tableCell" | "tableHeader" => vec![("colspan", json!(1)), ("rowspan", json!(1)), ("colwidth", Value::Null), ("align", Value::Null)],
        "image" => vec![("alt", Value::Null), ("title", Value::Null)],
        "callout" => vec![("tone", json!("neutral")), ("emphasis", json!("soft"))],
        "agentSuggestion" => vec![("confidence", Value::Null)],
        "questionBlock" => vec![("required", json!(false)), ("points", Value::Null), ("min", Value::Null), ("max", Value::Null), ("settings", json!({}))],
        "questionOption" => vec![("correct", json!(false)), ("points", Value::Null), ("settings", json!({}))],
        _ => Vec::new(),
    }
}

/// Snapshot to editor JSON, before any validation of meaning.
fn snapshot_prosemirror(snapshot: &Value) -> Result<Value> {
    only(snapshot, &["kind", "children", "metadata"], "Invalid portable snapshot shape")?;
    if snapshot["kind"] != "fragment" || !snapshot["children"].is_array() {
        bail!("Invalid portable fragment");
    }
    fn nodes(children: &Value, depth: usize) -> Result<Vec<Value>> {
        let Some(children) = children.as_array().filter(|_| depth <= 64) else { bail!("Invalid portable children") };
        let mut result = Vec::with_capacity(children.len());
        for node in children {
            if node.get("kind").and_then(Value::as_str) == Some("text") {
                only(node, &["kind", "delta"], "Invalid portable snapshot shape")?;
                let Some(delta) = node["delta"].as_array() else { bail!("Invalid text delta") };
                for run in delta {
                    only(run, &["insert", "attributes"], "Invalid portable snapshot shape")?;
                    let Some(insert) = run["insert"].as_str().filter(|text| !text.is_empty()) else { bail!("Invalid text insert") };
                    let empty = json!({});
                    let attributes = run.get("attributes").filter(|a| crate::json::truthy(Some(a))).unwrap_or(&empty);
                    only(attributes, &TEXT_MARKS, "Invalid portable snapshot shape")?;
                    let mut marks = Vec::new();
                    for (kind, attrs) in attributes.as_object().into_iter().flatten() {
                        let allowed: &[&str] = match kind.as_str() {
                            "link" => &["href", "target", "rel", "class", "title"],
                            "ai_authored" => &["run_id"],
                            _ => &[],
                        };
                        only(attrs, allowed, "Invalid portable snapshot shape")?;
                        marks.push(match kind.as_str() {
                            "link" => {
                                let mut merged: Map = link_defaults().iter().cloned().collect();
                                for (key, value) in attrs.as_object().into_iter().flatten() {
                                    merged.insert(key.clone(), value.clone());
                                }
                                json!({"type": "link", "attrs": merged})
                            }
                            "ai_authored" => json!({"type": "ai_authored", "attrs": attrs}),
                            other => json!({"type": other}),
                        });
                    }
                    marks.sort_by_key(|mark| mark_rank(mark["type"].as_str().unwrap_or_default()));
                    let mut text = Map::new();
                    text.insert("type".into(), json!("text"));
                    text.insert("text".into(), json!(insert));
                    if !marks.is_empty() {
                        text.insert("marks".into(), Value::Array(marks));
                    }
                    result.push(Value::Object(text));
                }
                continue;
            }
            only(node, &["kind", "name", "attributes", "children"], "Invalid portable snapshot shape")?;
            let Some(name) = node.get("name").and_then(Value::as_str).filter(|_| node["kind"] == "element") else { bail!("Invalid portable element") };
            let raw = node.get("attributes").unwrap_or(&Value::Null);
            if !raw.is_object() {
                bail!("Invalid portable snapshot shape");
            }
            let content = nodes(node.get("children").unwrap_or(&Value::Null), depth + 1)?;
            let mut attributes: Map = schema_defaults(name).into_iter().map(|(k, v)| (k.to_owned(), v)).collect();
            for (key, value) in decode_attributes(name, raw)? {
                attributes.insert(key, value);
            }
            let mut element = Map::new();
            element.insert("type".into(), json!(name));
            if !attributes.is_empty() {
                element.insert("attrs".into(), Value::Object(attributes));
            }
            if !content.is_empty() {
                element.insert("content".into(), Value::Array(content));
            }
            result.push(Value::Object(element));
        }
        Ok(result)
    }
    Ok(json!({"type": "doc", "content": nodes(&snapshot["children"], 0)?}))
}

/// Portable XML snapshot to the document AST, with its normalized editor JSON.
pub fn snapshot_to_document_with_prosemirror(snapshot: &Value) -> Result<(Value, Value)> {
    let prosemirror = snapshot_prosemirror(snapshot)?;
    to_relaymark(&prosemirror)?;
    let normalized = editor_schema().normalize(&prosemirror)?;
    let mut document = to_relaymark(&normalized)?;
    if let Some(metadata) = snapshot.get("metadata") {
        only(metadata, &METADATA_KEYS, "Invalid portable snapshot shape")?;
        for (key, value) in metadata.as_object().into_iter().flatten() {
            document[key.as_str()] = value.clone();
        }
    }
    let editor = to_prosemirror(&document)?;
    Ok((document, editor))
}

pub fn snapshot_to_document(snapshot: &Value) -> Result<Value> {
    Ok(snapshot_to_document_with_prosemirror(snapshot)?.0)
}

// ---- Physical XML attributes: form settings are encoded one field per attribute ----

struct AttributeEncoding {
    nodes: Vec<String>,
    logical: String,
    presence: Value,
    prefix: String,
}

fn encoding() -> &'static AttributeEncoding {
    static ENCODING: std::sync::OnceLock<AttributeEncoding> = std::sync::OnceLock::new();
    ENCODING.get_or_init(|| {
        let policy: Value = serde_json::from_str(ATTRIBUTE_ENCODING_JSON).expect("packaged attribute policy");
        AttributeEncoding {
            nodes: policy["nodes"].as_array().into_iter().flatten().filter_map(|n| n.as_str().map(str::to_owned)).collect(),
            logical: policy["logical_attribute"].as_str().unwrap_or("settings").to_owned(),
            presence: policy["presence"].clone(),
            prefix: policy["field_prefix"].as_str().unwrap_or("settings:").to_owned(),
        }
    })
}

const BASE64URL: GeneralPurpose = GeneralPurpose::new(
    &base64::alphabet::URL_SAFE,
    GeneralPurposeConfig::new().with_encode_padding(false).with_decode_padding_mode(DecodePaddingMode::RequireNone).with_decode_allow_trailing_bits(true),
);

pub fn settings_attribute_key(key: &str) -> String {
    format!("{}{}", encoding().prefix, BASE64URL.encode(key.as_bytes()))
}

fn original_settings_key(field: &str) -> Result<String> {
    let encoded = &field[encoding().prefix.len()..];
    if !encoded.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-') || encoded.len() % 4 == 1 {
        bail!("Invalid physical settings key");
    }
    let Some(key) = BASE64URL.decode(encoded).ok().and_then(|bytes| String::from_utf8(bytes).ok()) else { bail!("Invalid physical settings Unicode key") };
    if settings_attribute_key(&key) != field {
        bail!("Noncanonical physical settings key");
    }
    Ok(key)
}

fn unrelated(attributes: &Map) -> Result<()> {
    let policy = encoding();
    if attributes.keys().any(|key| key.starts_with(&policy.prefix)) || attributes.contains_key(&policy.logical) {
        bail!("Settings fields on unrelated node");
    }
    Ok(())
}

/// Authored attributes to physical XML attributes (nulls omitted).
pub fn encode_attributes(name: &str, attributes: &Map) -> Result<Map> {
    let policy = encoding();
    if !policy.nodes.iter().any(|n| n == name) {
        unrelated(attributes)?;
        return Ok(attributes.iter().filter(|(_, v)| !v.is_null()).map(|(k, v)| (k.clone(), v.clone())).collect());
    }
    let empty = json!({});
    let settings = attributes.get(&policy.logical).unwrap_or(&empty);
    let Some(settings_map) = settings.as_object() else { bail!("Invalid settings attributes") };
    validate_json_value(settings, 0)?;
    if attributes.keys().any(|key| key.starts_with(&policy.prefix)) {
        bail!("Physical field supplied as authored attribute");
    }
    let mut encoded: Map = attributes.iter().filter(|(k, v)| **k != policy.logical && !v.is_null()).map(|(k, v)| (k.clone(), v.clone())).collect();
    encoded.insert(policy.logical.clone(), policy.presence.clone());
    for (key, value) in settings_map {
        encoded.insert(settings_attribute_key(key), value.clone());
    }
    Ok(encoded)
}

/// Physical XML attributes to authored attributes.
pub fn decode_attributes(name: &str, attributes: &Value) -> Result<Map> {
    let policy = encoding();
    let Some(map) = attributes.as_object() else { bail!("Invalid settings attributes") };
    if !policy.nodes.iter().any(|n| n == name) {
        unrelated(map)?;
        return Ok(map.clone());
    }
    if map.get(&policy.logical) != Some(&policy.presence) {
        bail!("Aggregate or missing physical settings");
    }
    let mut plain = Map::new();
    let mut settings = Map::new();
    for (key, value) in map {
        if key.starts_with(&policy.prefix) {
            settings.insert(original_settings_key(key)?, value.clone());
        } else if *key != policy.logical {
            plain.insert(key.clone(), value.clone());
        }
    }
    let settings = Value::Object(settings);
    validate_json_value(&settings, 0)?;
    plain.insert(policy.logical.clone(), settings);
    Ok(plain)
}

pub fn is_settings_node(name: &str) -> bool {
    encoding().nodes.iter().any(|n| n == name)
}

pub fn settings_policy() -> (&'static str, &'static Value, &'static str) {
    let policy = encoding();
    (policy.logical.as_str(), &policy.presence, policy.prefix.as_str())
}
