//! The canonical editor projection (ProseMirror JSON) of the RelayMark AST and
//! its strict, lossless inverse. Both directions refuse anything they cannot
//! represent exactly.

use std::collections::HashSet;

use serde_json::{Value, json};

use crate::controls::{
    assert_control_props, assert_entity_reference_props, canonical_control_source, control_fields, control_for_node, control_node_name,
    parse_entity_reference_source,
};
use crate::error::{Result, bail};
use crate::inline::{map_inline, unmap_inline};
use crate::json::{self, Map};
use crate::jsre::js_regex;
use crate::links::safe_image_source;
use crate::registry::{DirectiveNode, authored_directive_props, directive_node_for_name, directive_node_for_type};

const MAX_ROWS: usize = 256;
const MAX_COLUMNS: u64 = 256;
const MAX_CELLS: usize = 4096;
const MAX_TASK_DEPTH: usize = 16;
const MAX_LIST_DEPTH: usize = 16;
pub const MAX_DOCUMENT_DEPTH: usize = 64;
const MAX_TASK_CHILDREN: usize = 4096;
const METADATA_KEYS: [&str; 4] = ["frontmatter", "annotations", "resources", "meta"];

/// Editor node names that carry a `relaymarkId`.
pub fn identified_node_names() -> Vec<&'static str> {
    let mut names = vec![
        "paragraph",
        "calloutTitle",
        "blockquote",
        "bulletList",
        "horizontalRule",
        "orderedList",
        "listItem",
        "heading",
        "taskList",
        "taskItem",
        "table",
        "tableRow",
        "tableHeader",
        "tableCell",
        "codeBlock",
        "image",
        "videoEmbed",
        "relayEntityReference",
        "agentSuggestion",
        "callout",
        "questionBlock",
        "questionLabel",
        "questionOption",
        "relayButton",
        "relayAnchor",
        "relayConnection",
        "relayDataView",
    ];
    names.extend(crate::registry::registry().nodes.iter().map(|node| node.name));
    names
}

type Seen = HashSet<String>;

fn is_block_id(id: &str) -> bool {
    js_regex!(r"^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$").is_match(id)
}

fn type_of(value: &Value) -> Option<&str> {
    json::str_field(value, "type")
}

fn assert_object<'a>(value: &'a Value, label: &str) -> Result<&'a Map> {
    match value.as_object() {
        Some(map) => Ok(map),
        None => bail!("{label} must be an object"),
    }
}

fn only_keys(value: &Value, allowed: &[&str], label: &str) -> Result<()> {
    if let Some(map) = value.as_object() {
        for key in map.keys() {
            if !allowed.contains(&key.as_str()) {
                bail!("Unsupported {label} field: {key}");
            }
        }
    }
    Ok(())
}

fn require_type(node: &Value, expected: &str) -> Result<()> {
    if type_of(node) != Some(expected) {
        bail!("Expected {expected}, got {}", type_of(node).unwrap_or("undefined"));
    }
    Ok(())
}

fn check_id(id: Option<&Value>, seen: &mut Seen) -> Result<String> {
    let Some(id) = id.and_then(Value::as_str).filter(|id| is_block_id(id)) else { bail!("Missing or invalid relaymarkId") };
    if !seen.insert(id.to_owned()) {
        bail!("Duplicate relaymarkId: {id}");
    }
    Ok(id.to_owned())
}

fn check_node(node: &Value, kind: &str, seen: &mut Seen, additional: &[&str]) -> Result<String> {
    assert_object(node, kind)?;
    only_keys(node, &["type", "attrs", "content"], kind)?;
    require_type(node, kind)?;
    let attrs = node.get("attrs").unwrap_or(&Value::Null);
    assert_object(attrs, &format!("{kind}.attrs"))?;
    let mut allowed = vec!["relaymarkId"];
    allowed.extend_from_slice(additional);
    only_keys(attrs, &allowed, &format!("{kind}.attrs"))?;
    check_id(attrs.get("relaymarkId"), seen)
}

fn check_block(block: &Value, kind: &str, seen: &mut Seen, has_props: bool) -> Result<String> {
    assert_object(block, kind)?;
    let allowed: &[&str] = if has_props { &["id", "type", "props", "content"] } else { &["id", "type", "content"] };
    only_keys(block, allowed, kind)?;
    require_type(block, kind)?;
    check_id(block.get("id"), seen)
}

fn children<'a>(node: &'a Value, label: &str, minimum: usize) -> Result<&'a Vec<Value>> {
    match node.get("content").and_then(Value::as_array) {
        Some(items) if items.len() >= minimum => Ok(items),
        _ => bail!("{label} requires an array of at least {minimum} children"),
    }
}

fn inline_children<'a>(node: &'a Value, label: &str) -> Result<&'a [Value]> {
    if node.get("content").is_none() {
        return Ok(&[]);
    }
    Ok(children(node, label, 0)?)
}

fn attr<'a>(node: &'a Value, key: &str) -> &'a Value {
    node.get("attrs").and_then(|attrs| attrs.get(key)).unwrap_or(&Value::Null)
}

fn attr_opt<'a>(node: &'a Value, key: &str) -> Option<&'a Value> {
    node.get("attrs").and_then(|attrs| attrs.get(key))
}

fn has_attr(node: &Value, key: &str) -> bool {
    node.get("attrs").and_then(Value::as_object).is_some_and(|attrs| attrs.contains_key(key))
}

fn prop<'a>(block: &'a Value, key: &str) -> Option<&'a Value> {
    block.get("props").and_then(|props| props.get(key))
}

fn block_value(id: String, kind: &str, props: Option<Map>, content: Vec<Value>) -> Value {
    let mut block = Map::new();
    block.insert("id".into(), Value::String(id));
    block.insert("type".into(), Value::String(kind.to_owned()));
    if let Some(props) = props {
        block.insert("props".into(), Value::Object(props));
    }
    block.insert("content".into(), Value::Array(content));
    Value::Object(block)
}

fn pm_node(kind: &str, attrs: Map, content: Option<Vec<Value>>) -> Value {
    let mut node = Map::new();
    node.insert("type".into(), Value::String(kind.to_owned()));
    node.insert("attrs".into(), Value::Object(attrs));
    if let Some(content) = content {
        node.insert("content".into(), Value::Array(content));
    }
    Value::Object(node)
}

fn id_attrs(id: &str) -> Map {
    let mut attrs = Map::new();
    attrs.insert("relaymarkId".into(), Value::String(id.to_owned()));
    attrs
}

fn map_from(pairs: Vec<(&str, Value)>) -> Map {
    pairs.into_iter().map(|(k, v)| (k.to_owned(), v)).collect()
}

/// Cross-container nesting has one physical depth bound.
fn assert_content_depth(node: &Value, depth: usize) -> Result<()> {
    if depth > MAX_DOCUMENT_DEPTH {
        bail!(" document nesting limit exceeded");
    }
    if let Some(items) = node.get("content").and_then(Value::as_array) {
        for child in items {
            assert_content_depth(child, depth + 1)?;
        }
    }
    Ok(())
}

/// The exact authored envelope: frontmatter, annotations, resources, meta.
pub fn assert_authored_metadata(value: &Value) -> Result<()> {
    assert_object(value, "authored metadata")?;
    only_keys(value, &METADATA_KEYS, "authored metadata")?;
    for key in ["frontmatter", "meta"] {
        if let Some(item) = value.get(key) {
            assert_object(item, key)?;
        }
    }
    for key in ["annotations", "resources"] {
        if value.get(key).is_some_and(|item| !item.is_array()) {
            bail!("Invalid {key}");
        }
    }
    let mut budget: i64 = 1_000_000;
    fn visit(value: &Value, depth: usize, budget: &mut i64) -> Result<()> {
        *budget -= 1;
        if *budget < 0 || depth > 128 {
            bail!("Authored metadata resource limit");
        }
        match value {
            Value::Array(items) => items.iter().try_for_each(|item| visit(item, depth + 1, budget)),
            Value::Object(map) => map.values().try_for_each(|item| visit(item, depth + 1, budget)),
            _ => Ok(()),
        }
    }
    visit(value, 0, &mut budget)
}

// ---------------------------------------------------------------------------
// Editor → AST
// ---------------------------------------------------------------------------

/// `proseMirrorToRelayMark`: strict editor JSON to the canonical AST.
pub fn to_relaymark(prosemirror: &Value) -> Result<Value> {
    assert_object(prosemirror, "doc")?;
    only_keys(prosemirror, &["type", "content", "attrs"], "doc")?;
    let empty = Value::Object(Map::new());
    let metadata = match prosemirror.get("attrs") {
        Some(attrs) => {
            assert_object(attrs, "doc attributes")?;
            only_keys(attrs, &["relaymark"], "doc attributes")?;
            attrs.get("relaymark").unwrap_or(&empty)
        }
        None => &empty,
    };
    assert_authored_metadata(metadata)?;
    require_type(prosemirror, "doc")?;
    assert_content_depth(prosemirror, 0)?;
    let mut seen = Seen::new();
    let blocks = children(prosemirror, "doc", 1)?.iter().map(|node| map_block(node, &mut seen, 0)).collect::<Result<Vec<_>>>()?;
    let mut document = Map::new();
    document.insert("type".into(), Value::String("relaymark.document".into()));
    document.insert("blocks".into(), Value::Array(blocks));
    for (key, value) in metadata.as_object().into_iter().flatten() {
        document.insert(key.clone(), value.clone());
    }
    Ok(Value::Object(document))
}

fn map_block(node: &Value, seen: &mut Seen, callout_depth: usize) -> Result<Value> {
    if let Some(shape) = type_of(node).and_then(directive_node_for_name) {
        return map_directive(node, shape, seen, callout_depth);
    }
    match type_of(node) {
        Some("paragraph") => map_paragraph(node, seen),
        Some("questionBlock") => map_question(node, seen),
        Some("relayDataView") => map_data_view(node, seen),
        Some("heading") => map_heading(node, seen),
        Some("blockquote") => {
            let id = check_node(node, "blockquote", seen, &[])?;
            let content = children(node, "blockquote", 1)?.iter().map(|c| map_block(c, seen, callout_depth)).collect::<Result<_>>()?;
            Ok(block_value(id, "quote", None, content))
        }
        Some("bulletList") => map_list(node, seen, false, 0),
        Some("orderedList") => map_list(node, seen, true, 0),
        Some("taskList") => map_task_list(node, seen, 0),
        Some("codeBlock") => {
            let id = check_node(node, "codeBlock", seen, &["language"])?;
            check_language(attr_opt(node, "language"))?;
            let content = inline_children(node, "codeBlock")?.iter().map(plain_text_node).collect::<Result<_>>()?;
            Ok(block_value(id, "code", Some(map_from(vec![("language", attr(node, "language").clone())])), content))
        }
        Some("horizontalRule") => {
            let id = check_node(node, "horizontalRule", seen, &[])?;
            if node.get("content").is_some() && !children(node, "horizontalRule", 0)?.is_empty() {
                bail!("Horizontal rule cannot have children");
            }
            Ok(block_value(id, "horizontal_rule", None, Vec::new()))
        }
        Some("image") => map_image(node, seen),
        Some("videoEmbed") => {
            let id = check_node(node, "videoEmbed", seen, &["videoId"])?;
            if node.get("content").is_some() && !children(node, "videoEmbed", 0)?.is_empty() {
                bail!("Video cannot have children");
            }
            check_video_id(attr(node, "videoId"))?;
            Ok(block_value(id, "relay.video_embed", Some(map_from(vec![("videoId", attr(node, "videoId").clone())])), Vec::new()))
        }
        Some("relayEntityReference") => map_entity_reference(node, seen),
        Some(name @ ("relayButton" | "relayAnchor" | "relayConnection")) => {
            let control = control_for_node(name).unwrap_or_default();
            let fields = control_fields(control).unwrap_or_default();
            let id = check_node(node, name, seen, fields)?;
            if node.get("content").is_some() && !children(node, name, 0)?.is_empty() {
                bail!("Paper control cannot have children");
            }
            let authored: Map = fields.iter().map(|f| ((*f).to_owned(), attr(node, f).clone())).collect();
            let source = canonical_control_source(control, &authored)?;
            let mut props = map_from(vec![("control", Value::String(control.to_owned()))]);
            props.extend(authored);
            props.insert("source".into(), Value::String(source));
            Ok(block_value(id, "relay.paper_control", Some(props), Vec::new()))
        }
        Some("agentSuggestion") => {
            let id = check_node(node, "agentSuggestion", seen, &["review", "kind", "confidence", "evidence", "content"])?;
            if node.get("content").is_some() && !children(node, "agentSuggestion", 0)?.is_empty() {
                bail!("AgentSuggestion atom cannot have children");
            }
            let (review, kind, confidence, evidence, content) = assert_agent_suggestion(
                attr(node, "review"),
                attr(node, "kind"),
                node.get("attrs").and_then(|a| a.get("confidence")),
                attr(node, "evidence"),
                attr(node, "content"),
            )?;
            let mut props = map_from(vec![("review", review), ("kind", kind), ("evidence", evidence)]);
            if !confidence.is_null() {
                props.insert("confidence".into(), confidence);
            }
            Ok(block_value(id, "relay.agent_suggestion", Some(props), vec![json!({"type": "text", "text": content})]))
        }
        Some("callout") => map_callout(node, seen, callout_depth),
        Some("table") => {
            let table = map_table(node, seen)?;
            validate_grid(&table)?;
            Ok(table)
        }
        other => bail!("Unsupported canonical block: {}", other.unwrap_or("undefined")),
    }
}

fn map_directive(node: &Value, shape: &DirectiveNode, seen: &mut Seen, callout_depth: usize) -> Result<Value> {
    let attributes: Vec<&str> = shape.attributes.keys().map(String::as_str).collect();
    let id = check_node(node, shape.name, seen, &attributes)?;
    let props = authored_directive_props(shape, node.get("attrs").unwrap_or(&Value::Null))?;
    let items: &[Value] = if shape.minimum_children == 0 { inline_children(node, shape.name)? } else { children(node, shape.name, shape.minimum_children)? };
    let content = items.iter().map(|child| map_block(child, seen, callout_depth)).collect::<Result<Vec<_>>>()?;
    if content.iter().any(|child| !shape.allowed_children.iter().any(|t| Some(t.as_str()) == type_of(child))) {
        bail!("Unsupported authored directive child");
    }
    Ok(block_value(id, shape.ast_type, Some(props), content))
}

fn check_callout_props(tone: &Value, emphasis: &Value) -> Result<()> {
    let tones = ["neutral", "primary", "secondary", "accent", "info", "success", "warning", "error"];
    let tone_ok = tone.as_str().is_some_and(|t| tones.contains(&t));
    let emphasis_ok = emphasis.as_str().is_some_and(|e| e == "soft" || e == "strong");
    if !tone_ok || !emphasis_ok {
        bail!("Unsupported callout tone or emphasis");
    }
    Ok(())
}

fn map_callout(node: &Value, seen: &mut Seen, depth: usize) -> Result<Value> {
    if depth >= 8 {
        bail!("Callout nesting exceeds the draft limit");
    }
    let id = check_node(node, "callout", seen, &["tone", "emphasis"])?;
    let (tone, emphasis) = (attr(node, "tone"), attr(node, "emphasis"));
    check_callout_props(tone, emphasis)?;
    let items = children(node, "callout", 1)?;
    if type_of(&items[0]) == Some("calloutTitle") && items.len() < 2 {
        bail!("Callout requires a body block");
    }
    let mut content = Vec::with_capacity(items.len());
    for (index, item) in items.iter().enumerate() {
        content.push(if index == 0 && type_of(item) == Some("calloutTitle") {
            let title_id = check_node(item, "calloutTitle", seen, &[])?;
            let parts = inline_children(item, "calloutTitle")?;
            if parts.iter().any(|part| type_of(part) != Some("text")) {
                bail!("Unsupported callout title inline node");
            }
            block_value(title_id, "relay.callout_title", None, parts.iter().map(map_inline).collect::<Result<_>>()?)
        } else {
            map_block(item, seen, depth + 1)?
        });
    }
    Ok(block_value(id, "relay.callout", Some(map_from(vec![("tone", tone.clone()), ("emphasis", emphasis.clone())])), content))
}

fn check_heading(level: Option<&Value>, anchor: Option<&Value>) -> Result<()> {
    let level_ok = level.is_some_and(|l| json::is_integer(l) && (1.0..=6.0).contains(&l.as_f64().unwrap_or(0.0)));
    let anchor_ok = anchor.is_some_and(|a| a.is_null() || a.as_str().is_some_and(heading_id));
    if !level_ok || !anchor_ok {
        bail!("Invalid heading level or headingId");
    }
    Ok(())
}

fn heading_id(value: &str) -> bool {
    js_regex!(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$").is_match(value)
}

fn map_heading(node: &Value, seen: &mut Seen) -> Result<Value> {
    let id = check_node(node, "heading", seen, &["level", "headingId"])?;
    let (level, anchor) = (attr(node, "level"), attr(node, "headingId"));
    check_heading(attr_opt(node, "level"), attr_opt(node, "headingId"))?;
    let content = inline_children(node, "heading")?.iter().map(map_inline).collect::<Result<_>>()?;
    Ok(block_value(id, "heading", Some(map_from(vec![("level", level.clone()), ("headingId", anchor.clone())])), content))
}

fn check_list_start(start: &Value) -> Result<()> {
    if !json::is_safe_integer(start) || start.as_f64().unwrap_or(0.0) < 1.0 {
        bail!("Invalid ordered-list start");
    }
    Ok(())
}

fn map_list(node: &Value, seen: &mut Seen, ordered: bool, depth: usize) -> Result<Value> {
    if depth >= MAX_LIST_DEPTH {
        bail!("Unsupported nested list depth");
    }
    let kind = if ordered { "orderedList" } else { "bulletList" };
    let id = check_node(node, kind, seen, if ordered { &["start", "type"] } else { &[] })?;
    if ordered && !matches!(attr_opt(node, "type"), Some(Value::Null)) {
        bail!("Unsupported ordered-list type");
    }
    let props = if ordered {
        check_list_start(attr(node, "start"))?;
        map_from(vec![("kind", json!("ordered")), ("start", attr(node, "start").clone())])
    } else {
        map_from(vec![("kind", json!("bullet"))])
    };
    let content = children(node, kind, 1)?.iter().map(|item| map_list_item(item, seen, depth)).collect::<Result<_>>()?;
    Ok(block_value(id, "list", Some(props), content))
}

fn map_list_item(node: &Value, seen: &mut Seen, depth: usize) -> Result<Value> {
    let id = check_node(node, "listItem", seen, &[])?;
    let items = children(node, "listItem", 1)?;
    if type_of(&items[0]) != Some("paragraph") {
        bail!("List item must start with a paragraph");
    }
    let mut content = vec![map_paragraph(&items[0], seen)?];
    for item in &items[1..] {
        content.push(match type_of(item) {
            Some("bulletList") => map_list(item, seen, false, depth + 1)?,
            Some("orderedList") => map_list(item, seen, true, depth + 1)?,
            _ => map_block(item, seen, 0)?,
        });
    }
    Ok(block_value(id, "list_item", None, content))
}

fn check_task_props(checked: &Value, entity: &Value) -> Result<()> {
    let entity_ok = entity.is_null() || entity.as_str().is_some_and(uuid_any);
    if !checked.is_boolean() || !entity_ok {
        bail!("Invalid task checked state or entityId");
    }
    Ok(())
}

fn uuid_any(value: &str) -> bool {
    js_regex!(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$").is_match(value)
}

fn map_task_list(node: &Value, seen: &mut Seen, depth: usize) -> Result<Value> {
    if depth >= MAX_TASK_DEPTH {
        bail!("Task list nesting exceeds the draft limit");
    }
    let id = check_node(node, "taskList", seen, &[])?;
    let items = children(node, "taskList", 1)?;
    if items.len() > MAX_TASK_CHILDREN {
        bail!("Task list exceeds the draft child limit");
    }
    let content = items.iter().map(|item| map_task_item(item, seen, depth)).collect::<Result<_>>()?;
    Ok(block_value(id, "task_list", None, content))
}

fn map_task_item(node: &Value, seen: &mut Seen, depth: usize) -> Result<Value> {
    let id = check_node(node, "taskItem", seen, &["checked", "entityId"])?;
    if !has_attr(node, "checked") || !has_attr(node, "entityId") {
        bail!("Task item requires normalized checked and entityId attributes");
    }
    check_task_props(attr(node, "checked"), attr(node, "entityId"))?;
    let items = children(node, "taskItem", 1)?;
    if items.len() > MAX_TASK_CHILDREN {
        bail!("Task item exceeds the draft child limit");
    }
    if type_of(&items[0]) != Some("paragraph") {
        bail!("Unsupported task item children");
    }
    let content = items
        .iter()
        .map(|item| if type_of(item) == Some("taskList") { map_task_list(item, seen, depth + 1) } else { map_block(item, seen, 0) })
        .collect::<Result<_>>()?;
    let props = map_from(vec![("checked", attr(node, "checked").clone()), ("entityId", attr(node, "entityId").clone())]);
    Ok(block_value(id, "task_item", Some(props), content))
}

fn check_language(language: Option<&Value>) -> Result<()> {
    if !language.is_some_and(|l| l.is_null() || l.as_str().is_some_and(|l| !l.contains(['\r', '\n']))) {
        bail!("Invalid code language");
    }
    Ok(())
}

fn plain_text_node(node: &Value) -> Result<Value> {
    assert_object(node, "text")?;
    only_keys(node, &["type", "text"], "text")?;
    require_type(node, "text")?;
    match node.get("text").and_then(Value::as_str) {
        Some(text) if !text.is_empty() => Ok(json!({"type": "text", "text": text})),
        _ => bail!("Text must be a nonempty string"),
    }
}

fn check_image_props(src: Option<&Value>, alt: Option<&Value>, title: Option<&Value>) -> Result<()> {
    if !src.and_then(Value::as_str).is_some_and(safe_image_source) {
        bail!("Image src must be durable local media or HTTPS");
    }
    for (name, value) in [("alt", alt), ("title", title)] {
        let valid = value.is_some_and(|v| v.is_null() || v.as_str().is_some_and(|t| json::utf16_len(t) <= 4096 && !t.contains(['\r', '\n'])));
        if !valid {
            bail!("Invalid image {name}");
        }
    }
    Ok(())
}

fn check_dimensions(width: Option<&Value>, height: Option<&Value>) -> Result<()> {
    for value in [width, height] {
        if !json::is_nullish(value) {
            let value = value.unwrap_or(&Value::Null);
            if !json::is_safe_integer(value) || value.as_f64().unwrap_or(0.0) <= 0.0 {
                bail!("Image dimensions must be positive safe integers");
            }
        }
    }
    Ok(())
}

fn map_image(node: &Value, seen: &mut Seen) -> Result<Value> {
    let id = check_node(node, "image", seen, &["src", "alt", "title", "width", "height"])?;
    if node.get("content").is_some() && !children(node, "image", 0)?.is_empty() {
        bail!("Image cannot have children");
    }
    check_image_props(attr_opt(node, "src"), attr_opt(node, "alt"), attr_opt(node, "title"))?;
    let attrs = node.get("attrs");
    check_dimensions(attrs.and_then(|a| a.get("width")), attrs.and_then(|a| a.get("height")))?;
    let mut props = map_from(vec![("src", attr(node, "src").clone()), ("alt", attr(node, "alt").clone()), ("title", attr(node, "title").clone())]);
    for key in ["width", "height"] {
        if !attr(node, key).is_null() {
            props.insert(key.into(), attr(node, key).clone());
        }
    }
    Ok(block_value(id, "image", Some(props), Vec::new()))
}

fn map_entity_reference(node: &Value, seen: &mut Seen) -> Result<Value> {
    let id = check_node(node, "relayEntityReference", seen, &["entityRef", "entityId", "entityType", "label", "projection", "source"])?;
    if node.get("content").is_some() && !children(node, "relayEntityReference", 0)?.is_empty() {
        bail!("Entity reference atom cannot have children");
    }
    let authored = attr(node, "source").as_str().and_then(parse_entity_reference_source);
    let agrees = authored.as_ref().is_some_and(|a| {
        attr(node, "entityRef").as_str() == Some(a.id.as_str())
            && attr(node, "entityId").as_str() == Some(a.entity_id.as_str())
            && attr(node, "entityType").as_str() == Some("Entity")
            && attr(node, "label").as_str() == Some(a.label.as_str())
            && attr(node, "projection").as_str() == Some(a.projection.as_str())
    });
    if !agrees {
        bail!("Entity reference source/identity mismatch");
    }
    let props = map_from(vec![
        ("id", attr(node, "entityRef").clone()),
        ("label", attr(node, "label").clone()),
        ("projection", attr(node, "projection").clone()),
        ("source", attr(node, "source").clone()),
    ]);
    Ok(block_value(id, "relay.entity_reference", Some(props), Vec::new()))
}

fn check_video_id(value: &Value) -> Result<()> {
    if !value.as_str().is_some_and(uuid_any) {
        bail!("Video ID must be a canonical lowercase UUID");
    }
    Ok(())
}

/// An authored AgentSuggestion: review, kind, confidence, evidence, content.
pub fn assert_agent_suggestion(
    review: &Value,
    kind: &Value,
    confidence: Option<&Value>,
    evidence: &Value,
    content: &Value,
) -> Result<(Value, Value, Value, Value, String)> {
    let review_ok = review.as_str().is_some_and(|r| r == "draft" || r == "ready");
    let kind_ok = kind.as_str().is_some_and(|k| ["note", "action", "match", "journey", "source", "share"].contains(&k));
    let confidence_ok = confidence.is_some_and(|c| c.is_null() || c.as_f64().is_some_and(|c| c.is_finite() && (0.0..=1.0).contains(&c)));
    let confidence = confidence.cloned().unwrap_or(Value::Null);
    let evidence_ok = evidence.as_array().is_some_and(|items| {
        let unique: HashSet<&Value> = items.iter().collect::<Vec<_>>().into_iter().collect();
        items.len() <= 64
            && unique.len() == items.len()
            && items
                .iter()
                .all(|id| id.as_str().is_some_and(|id| !id.is_empty() && json::utf16_len(id) <= 128 && !id.chars().any(|c| (c as u32) < 0x20 || c == '\u{7f}')))
    });
    let text = content.as_str().filter(|t| !t.is_empty() && json::utf16_len(t) <= 32_768 && *t == json::js_trim(t) && !t.contains('\r') && !t.contains('\0'));
    match text {
        Some(text) if review_ok && kind_ok && confidence_ok && evidence_ok => Ok((review.clone(), kind.clone(), confidence, evidence.clone(), text.to_owned())),
        _ => bail!("Invalid authored AgentSuggestion"),
    }
}

fn assert_agent_suggestion_block(block: &Value) -> Result<(Value, Value, Value, Value, String)> {
    let props = block.get("props");
    let content = block.get("content").and_then(Value::as_array);
    let shape_ok = props.and_then(Value::as_object).is_some_and(|p| {
        (p.len() == 3 || p.len() == 4)
            && p.keys().all(|k| ["review", "kind", "confidence", "evidence"].contains(&k.as_str()))
            && !(p.contains_key("confidence") && p["confidence"].is_null())
    }) && content
        .is_some_and(|c| c.len() == 1 && type_of(&c[0]) == Some("text") && c[0].as_object().is_some_and(|t| t.keys().all(|k| k == "type" || k == "text")));
    if !shape_ok {
        bail!("Invalid authored AgentSuggestion block");
    }
    let props = props.unwrap_or(&Value::Null);
    let text = &content.unwrap_or(&Vec::new()).first().cloned().unwrap_or(Value::Null)["text"];
    let text = text.clone();
    assert_agent_suggestion(
        &props["review"],
        &props["kind"],
        Some(props.get("confidence").unwrap_or(&Value::Null)),
        props.get("evidence").unwrap_or(&Value::Null),
        &text,
    )
}

fn map_table(node: &Value, seen: &mut Seen) -> Result<Value> {
    let id = check_node(node, "table", seen, &[])?;
    let mut rows = Vec::new();
    for row in children(node, "table", 1)? {
        let row_id = check_node(row, "tableRow", seen, &[])?;
        let mut cells = Vec::new();
        for cell in children(row, "tableRow", 1)? {
            assert_object(cell, "table cell")?;
            let cell_type = type_of(cell).unwrap_or("");
            if cell_type != "tableCell" && cell_type != "tableHeader" {
                bail!("Unsupported table child: {}", type_of(cell).unwrap_or("undefined"));
            }
            let cell_id = check_node(cell, cell_type, seen, &["colspan", "rowspan", "colwidth", "align"])?;
            let mut props = map_from(vec![("header", Value::Bool(cell_type == "tableHeader"))]);
            for key in ["colspan", "rowspan", "colwidth", "align"] {
                if let Some(value) = attr_opt(cell, key) {
                    props.insert(key.into(), value.clone());
                }
            }
            check_cell_props(&props)?;
            let content = children(cell, cell_type, 1)?.iter().map(|child| map_block(child, seen, 0)).collect::<Result<_>>()?;
            cells.push(block_value(cell_id, "table_cell", Some(props), content));
        }
        rows.push(block_value(row_id, "table_row", None, cells));
    }
    Ok(block_value(id, "table", None, rows))
}

fn check_cell_props(props: &Map) -> Result<()> {
    let span = |key: &str| props.get(key).is_some_and(|v| json::is_safe_integer(v) && v.as_f64().unwrap_or(0.0) >= 1.0);
    if !span("colspan") || !span("rowspan") {
        bail!("Cell spans must be positive safe integers");
    }
    let colwidth = props.get("colwidth");
    if !matches!(colwidth, Some(Value::Null)) {
        let colspan = props["colspan"].as_f64().unwrap_or(0.0);
        let valid = colwidth
            .and_then(Value::as_array)
            .is_some_and(|widths| widths.len() as f64 == colspan && widths.iter().all(|w| json::is_safe_integer(w) && w.as_f64().unwrap_or(-1.0) >= 0.0));
        if !valid {
            bail!("Cell colwidth must be null or one non-negative width per spanned column");
        }
    }
    let align = props.get("align");
    if !align.is_some_and(|a| a.is_null() || a.as_str().is_some_and(|a| ["left", "center", "right"].contains(&a))) {
        bail!("Cell align must be null, left, center, or right");
    }
    Ok(())
}

/// Spans must tile a complete rectangle within the draft size limits.
fn validate_grid(table: &Value) -> Result<()> {
    let empty = Vec::new();
    let rows = table.get("content").and_then(Value::as_array).unwrap_or(&empty);
    let cell_count: usize = rows.iter().map(|row| row.get("content").and_then(Value::as_array).map_or(0, Vec::len)).sum();
    if rows.len() > MAX_ROWS || cell_count > MAX_CELLS {
        bail!("Table exceeds the draft row/cell limit");
    }
    let mut occupied: Vec<Vec<bool>> = vec![Vec::new(); rows.len()];
    let mut expected_width: Option<usize> = None;
    for (row_index, row) in rows.iter().enumerate() {
        let mut column = 0usize;
        for cell in row.get("content").and_then(Value::as_array).unwrap_or(&empty) {
            while occupied[row_index].get(column).copied().unwrap_or(false) {
                column += 1;
            }
            let colspan = prop(cell, "colspan").and_then(Value::as_f64).unwrap_or(0.0);
            let rowspan = prop(cell, "rowspan").and_then(Value::as_f64).unwrap_or(0.0);
            if colspan > MAX_COLUMNS as f64 || column as f64 + colspan > MAX_COLUMNS as f64 {
                bail!("Table exceeds the draft column limit");
            }
            if row_index as f64 + rowspan > rows.len() as f64 {
                bail!("Cell rowspan exceeds table rows");
            }
            let (colspan, rowspan) = (colspan as usize, rowspan as usize);
            for slots in &mut occupied[row_index..row_index + rowspan] {
                if slots.len() < column + colspan {
                    slots.resize(column + colspan, false);
                }
                for slot in &mut slots[column..column + colspan] {
                    if *slot {
                        bail!("Overlapping table cells");
                    }
                    *slot = true;
                }
            }
            column += colspan;
        }
        let width = occupied[row_index].len();
        let expected = *expected_width.get_or_insert(width);
        if width != expected || occupied[row_index].iter().any(|slot| !slot) {
            bail!("Table rows must form a complete rectangle");
        }
    }
    Ok(())
}

fn map_paragraph(node: &Value, seen: &mut Seen) -> Result<Value> {
    let id = check_node(node, "paragraph", seen, &[])?;
    let content = inline_children(node, "paragraph")?.iter().map(map_inline).collect::<Result<_>>()?;
    Ok(block_value(id, "paragraph", None, content))
}

const QUESTION_FIELDS: [&str; 7] = ["id", "type", "required", "points", "min", "max", "settings"];
const OPTION_FIELDS: [&str; 4] = ["id", "correct", "points", "settings"];
const QUESTION_TYPES: [&str; 24] = [
    "short_text",
    "long_text",
    "email",
    "phone",
    "number",
    "multiple_choice",
    "checkboxes",
    "dropdown",
    "linear_scale",
    "date",
    "file_upload",
    "page_break",
    "single_select",
    "multi_select",
    "entity_ref",
    "file",
    "slot_picker",
    "hidden_field",
    "calculated_field",
    "video_question",
    "video_response",
    "payment",
    "payment_block",
    "lightning_payment",
];

/// Authored form question or option properties.
pub fn validate_question_props(props: &Value, option: bool) -> Result<()> {
    assert_object(props, "form authored props")?;
    only_keys(props, if option { &OPTION_FIELDS } else { &QUESTION_FIELDS }, "form authored props")?;
    let identity_ok = props.get("id").and_then(Value::as_str).is_some_and(|id| !json::js_trim(id).is_empty() && !id.contains(['\r', '\n', '\0']));
    if !identity_ok {
        bail!("Invalid form identity");
    }
    let kind_ok = if option {
        props.get("correct").is_some_and(Value::is_boolean)
    } else {
        props.get("type").and_then(Value::as_str).is_some_and(|t| QUESTION_TYPES.contains(&t)) && props.get("required").is_some_and(Value::is_boolean)
    };
    if !kind_ok {
        bail!("Invalid form type or boolean");
    }
    let numeric: &[&str] = if option { &["points"] } else { &["points", "min", "max"] };
    for key in numeric {
        if !json::is_nullish(props.get(*key)) && !props.get(*key).is_some_and(json::is_finite_number) {
            bail!("Invalid form numeric setting");
        }
    }
    let settings = props.get("settings").unwrap_or(&Value::Null);
    assert_object(settings, "form authored settings")?;
    validate_json_value(settings, 0)
}

pub fn validate_json_value(value: &Value, depth: usize) -> Result<()> {
    if depth > 32 {
        bail!("Authored settings nesting exceeds bound");
    }
    match value {
        Value::Array(items) => items.iter().try_for_each(|item| validate_json_value(item, depth + 1)),
        Value::Object(map) => map.values().try_for_each(|item| validate_json_value(item, depth + 1)),
        _ => Ok(()),
    }
}

fn form_props(attrs: &Value, option: bool) -> Result<Map> {
    let mut result = if option {
        map_from(vec![("correct", json!(false)), ("points", Value::Null), ("settings", json!({}))])
    } else {
        map_from(vec![("required", json!(false)), ("points", Value::Null), ("min", Value::Null), ("max", Value::Null), ("settings", json!({}))])
    };
    for key in if option { &OPTION_FIELDS[..] } else { &QUESTION_FIELDS[..] } {
        if let Some(value) = attrs.get(*key) {
            result.insert((*key).to_owned(), value.clone());
        }
    }
    let value = Value::Object(result);
    validate_question_props(&value, option)?;
    Ok(match value {
        Value::Object(map) => map,
        _ => Map::new(),
    })
}

fn map_question(node: &Value, seen: &mut Seen) -> Result<Value> {
    let id = check_node(node, "questionBlock", seen, &QUESTION_FIELDS)?;
    let props = form_props(node.get("attrs").unwrap_or(&Value::Null), false)?;
    let parts = children(node, "questionBlock", 1)?;
    let label_id = check_node(&parts[0], "questionLabel", seen, &[])?;
    let label_content = inline_children(&parts[0], "questionLabel")?.iter().map(map_inline).collect::<Result<_>>()?;
    let mut content = vec![block_value(label_id, "paragraph", None, label_content)];
    let mut option_ids = HashSet::new();
    for option in &parts[1..] {
        let option_id = check_node(option, "questionOption", seen, &OPTION_FIELDS)?;
        let option_props = form_props(option.get("attrs").unwrap_or(&Value::Null), true)?;
        if !option_ids.insert(json::stringify(&option_props["id"])) {
            bail!("Duplicate option identity");
        }
        let option_content = inline_children(option, "questionOption")?.iter().map(map_inline).collect::<Result<_>>()?;
        content.push(block_value(option_id, "relay.form_option", Some(option_props), option_content));
    }
    Ok(block_value(id, "relay.form_question", Some(props), content))
}

const DATA_VIEW_FIELDS: [&str; 8] = ["source", "projection", "columns", "filter", "sort", "group", "limit", "title"];

fn data_view_props(attrs: &Value) -> Result<Map> {
    let mut props = Map::new();
    for key in DATA_VIEW_FIELDS {
        if let Some(value) = attrs.get(key).filter(|v| !v.is_null()) {
            props.insert(key.to_owned(), value.clone());
        }
    }
    let source_ok = props.get("source").and_then(Value::as_str).is_some_and(|s| js_regex!(r"^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$").is_match(s));
    let projection_ok = props.get("projection").and_then(Value::as_str).is_some_and(|p| ["list", "table", "feed", "calendar", "kanban", "chart"].contains(&p));
    if !source_ok || !projection_ok {
        bail!("Invalid data view source/projection");
    }
    for key in ["columns", "sort"] {
        if let Some(value) = props.get(key)
            && !value.as_array().is_some_and(|items| items.iter().all(Value::is_string))
        {
            bail!("Invalid data view keys");
        }
    }
    if let Some(filter) = props.get("filter") {
        let filter = assert_object(filter, "data view filter")?;
        let scalar = |v: &Value| v.is_null() || v.is_string() || v.is_boolean() || json::is_finite_number(v);
        for (key, value) in filter {
            let valid_value = scalar(value) || value.as_array().is_some_and(|items| items.iter().all(scalar));
            if !js_regex!(r"^[a-z][a-z0-9_]*$").is_match(key) || !valid_value {
                bail!("Invalid declarative data view filter");
            }
        }
    }
    if let Some(group) = props.get("group")
        && !group.as_str().is_some_and(|g| js_regex!(r"^[a-z][a-z0-9_]*$").is_match(g))
    {
        bail!("Invalid data view group");
    }
    if let Some(limit) = props.get("limit")
        && (!json::is_safe_integer(limit) || !(1.0..=1000.0).contains(&limit.as_f64().unwrap_or(0.0)))
    {
        bail!("Invalid data view limit");
    }
    if props.get("title").is_some_and(|t| !t.is_string()) {
        bail!("Invalid data view title");
    }
    Ok(props)
}

fn map_data_view(node: &Value, seen: &mut Seen) -> Result<Value> {
    let id = check_node(node, "relayDataView", seen, &DATA_VIEW_FIELDS)?;
    if node.get("content").is_some() && !children(node, "relayDataView", 0)?.is_empty() {
        bail!("Data view cannot carry records/children");
    }
    let props = data_view_props(node.get("attrs").unwrap_or(&Value::Null))?;
    Ok(block_value(id, "relay.data_view", Some(props), Vec::new()))
}

// ---------------------------------------------------------------------------
// AST → editor
// ---------------------------------------------------------------------------

/// `relayMarkToProseMirror`: canonical AST to strict editor JSON.
pub fn to_prosemirror(document: &Value) -> Result<Value> {
    assert_object(document, "document")?;
    only_keys(document, &["type", "blocks", "frontmatter", "annotations", "resources", "meta"], "document")?;
    for key in ["frontmatter", "meta"] {
        if let Some(value) = document.get(key) {
            assert_object(value, key)?;
        }
    }
    for key in ["annotations", "resources"] {
        if document.get(key).is_some_and(|v| !v.is_array()) {
            bail!("Invalid {key}");
        }
    }
    if type_of(document) != Some("relaymark.document") {
        bail!("Expected a canonical RelayMark AST document");
    }
    let wrapper = json!({"content": document.get("blocks").cloned().unwrap_or(Value::Null)});
    assert_content_depth(&wrapper, 0)?;
    let blocks = children(&wrapper, "document", 1)?;
    let metadata: Map = METADATA_KEYS.iter().filter_map(|k| document.get(*k).map(|v| ((*k).to_owned(), v.clone()))).collect();
    let metadata = Value::Object(metadata);
    assert_authored_metadata(&metadata)?;
    let mut seen = Seen::new();
    let content = blocks.iter().map(|block| unmap_block(block, &mut seen, 0)).collect::<Result<Vec<_>>>()?;
    let mut doc = Map::new();
    doc.insert("type".into(), Value::String("doc".into()));
    if metadata.as_object().is_some_and(|m| !m.is_empty()) {
        doc.insert("attrs".into(), json!({"relaymark": metadata}));
    }
    doc.insert("content".into(), Value::Array(content));
    Ok(Value::Object(doc))
}

fn unmap_block(block: &Value, seen: &mut Seen, callout_depth: usize) -> Result<Value> {
    if let Some(shape) = type_of(block).and_then(directive_node_for_type) {
        let id = check_block(block, shape.ast_type, seen, true)?;
        let empty = Value::Object(Map::new());
        let props = authored_directive_props(shape, block.get("props").unwrap_or(&empty))?;
        let body = children(block, shape.ast_type, shape.minimum_children)?;
        if body.iter().any(|child| !shape.allowed_children.iter().any(|t| Some(t.as_str()) == type_of(child))) {
            bail!("Unsupported authored directive child");
        }
        let mut attrs = id_attrs(&id);
        attrs.extend(props);
        let content = body.iter().map(|child| unmap_block(child, seen, callout_depth)).collect::<Result<_>>()?;
        return Ok(pm_node(shape.name, attrs, Some(content)));
    }
    match type_of(block) {
        Some("paragraph") => unmap_paragraph(block, seen),
        Some("relay.form_question") => unmap_question(block, seen),
        Some("relay.data_view") => {
            let id = check_block(block, "relay.data_view", seen, true)?;
            only_keys(block.get("props").unwrap_or(&Value::Null), &DATA_VIEW_FIELDS, "relay.data_view.props")?;
            if !children(block, "relay.data_view", 0)?.is_empty() {
                bail!("Data view cannot carry records/children");
            }
            let mut attrs = id_attrs(&id);
            attrs.extend(data_view_props(block.get("props").unwrap_or(&Value::Null))?);
            Ok(pm_node("relayDataView", attrs, None))
        }
        Some("heading") => {
            let id = check_block(block, "heading", seen, true)?;
            let props = block.get("props").unwrap_or(&Value::Null);
            assert_object(props, "heading.props")?;
            only_keys(props, &["level", "headingId"], "heading.props")?;
            check_heading(props.get("level"), props.get("headingId"))?;
            let (level, anchor) = (&props["level"], &props["headingId"]);
            let mut attrs = id_attrs(&id);
            attrs.insert("level".into(), level.clone());
            attrs.insert("headingId".into(), anchor.clone());
            let content = inline_children(block, "heading")?.iter().map(unmap_inline).collect::<Result<_>>()?;
            Ok(pm_node("heading", attrs, Some(content)))
        }
        Some("quote") => {
            let id = check_block(block, "quote", seen, false)?;
            let content = children(block, "quote", 1)?.iter().map(|c| unmap_block(c, seen, callout_depth)).collect::<Result<_>>()?;
            Ok(pm_node("blockquote", id_attrs(&id), Some(content)))
        }
        Some("list") => unmap_list(block, seen, 0),
        Some("task_list") => unmap_task_list(block, seen, 0),
        Some("code") => {
            let id = check_block(block, "code", seen, true)?;
            let props = block.get("props").unwrap_or(&Value::Null);
            assert_object(props, "code.props")?;
            only_keys(props, &["language"], "code.props")?;
            check_language(props.get("language"))?;
            let language = &props["language"];
            let mut attrs = id_attrs(&id);
            attrs.insert("language".into(), language.clone());
            let content = inline_children(block, "code")?.iter().map(plain_text_node).collect::<Result<_>>()?;
            Ok(pm_node("codeBlock", attrs, Some(content)))
        }
        Some("horizontal_rule") => {
            let id = check_block(block, "horizontal_rule", seen, false)?;
            if block.get("content").is_some() && !children(block, "horizontal_rule", 0)?.is_empty() {
                bail!("Horizontal rule cannot have children");
            }
            Ok(pm_node("horizontalRule", id_attrs(&id), None))
        }
        Some("image") => {
            let id = check_block(block, "image", seen, true)?;
            let props = block.get("props").unwrap_or(&Value::Null);
            assert_object(props, "image.props")?;
            only_keys(props, &["src", "alt", "title", "width", "height"], "image.props")?;
            if block.get("content").is_some() && !children(block, "image", 0)?.is_empty() {
                bail!("Image cannot have children");
            }
            check_image_props(props.get("src"), props.get("alt"), props.get("title"))?;
            check_dimensions(props.get("width"), props.get("height"))?;
            let mut attrs = id_attrs(&id);
            attrs.insert("width".into(), Value::Null);
            attrs.insert("height".into(), Value::Null);
            for (key, value) in props.as_object().into_iter().flatten() {
                attrs.insert(key.clone(), value.clone());
            }
            Ok(pm_node("image", attrs, None))
        }
        Some("relay.video_embed") => {
            let id = check_block(block, "relay.video_embed", seen, true)?;
            let props = block.get("props").unwrap_or(&Value::Null);
            assert_object(props, "relay.video_embed.props")?;
            only_keys(props, &["videoId"], "relay.video_embed.props")?;
            if block.get("content").is_some() && !children(block, "relay.video_embed", 0)?.is_empty() {
                bail!("Video cannot have children");
            }
            let video = props.get("videoId").unwrap_or(&Value::Null);
            check_video_id(video)?;
            let mut attrs = id_attrs(&id);
            attrs.insert("videoId".into(), video.clone());
            Ok(pm_node("videoEmbed", attrs, None))
        }
        Some("relay.entity_reference") => {
            let id = check_block(block, "relay.entity_reference", seen, true)?;
            if block.get("content").is_some() && !children(block, "relay.entity_reference", 0)?.is_empty() {
                bail!("Entity reference atom cannot have children");
            }
            let reference = assert_entity_reference_props(block.get("props"))?;
            let mut attrs = id_attrs(&id);
            attrs.insert("entityRef".into(), Value::String(reference.id));
            attrs.insert("entityId".into(), Value::String(reference.entity_id));
            attrs.insert("entityType".into(), Value::String("Entity".into()));
            attrs.insert("label".into(), Value::String(reference.label));
            attrs.insert("projection".into(), Value::String(reference.projection));
            attrs.insert("source".into(), Value::String(reference.source));
            Ok(pm_node("relayEntityReference", attrs, None))
        }
        Some("relay.paper_control") => {
            let id = check_block(block, "relay.paper_control", seen, true)?;
            if block.get("content").is_some() && !children(block, "relay.paper_control", 0)?.is_empty() {
                bail!("Paper control cannot have children");
            }
            let (control, authored, _) = assert_control_props(block.get("props"))?;
            let mut attrs = id_attrs(&id);
            attrs.extend(authored);
            Ok(pm_node(control_node_name(&control).unwrap_or_default(), attrs, None))
        }
        Some("relay.agent_suggestion") => {
            let id = check_block(block, "relay.agent_suggestion", seen, true)?;
            let (review, kind, confidence, evidence, content) = assert_agent_suggestion_block(block)?;
            let mut attrs = id_attrs(&id);
            attrs.extend(map_from(vec![
                ("review", review),
                ("kind", kind),
                ("confidence", confidence),
                ("evidence", evidence),
                ("content", Value::String(content)),
            ]));
            Ok(pm_node("agentSuggestion", attrs, None))
        }
        Some("relay.callout") => unmap_callout(block, seen, callout_depth),
        Some("table") => {
            validate_grid_input(block)?;
            unmap_table(block, seen)
        }
        other => bail!("Unsupported canonical block: {}", other.unwrap_or("undefined")),
    }
}

/// The JS reference validates the grid of the raw AST before checking cells,
/// reading `cell.props` spans as given.
fn validate_grid_input(block: &Value) -> Result<()> {
    if block.get("content").and_then(Value::as_array).is_none() {
        bail!("table requires an array of at least 1 children");
    }
    for row in block["content"].as_array().into_iter().flatten() {
        if row.get("content").and_then(Value::as_array).is_none() {
            bail!("table_row requires an array of at least 1 children");
        }
    }
    validate_grid(block)
}

fn unmap_callout(block: &Value, seen: &mut Seen, depth: usize) -> Result<Value> {
    if depth >= 8 {
        bail!("Callout nesting exceeds the draft limit");
    }
    let id = check_block(block, "relay.callout", seen, true)?;
    let props = block.get("props").unwrap_or(&Value::Null);
    assert_object(props, "relay.callout.props")?;
    only_keys(props, &["tone", "emphasis"], "relay.callout.props")?;
    let (tone, emphasis) = (props.get("tone").unwrap_or(&Value::Null), props.get("emphasis").unwrap_or(&Value::Null));
    check_callout_props(tone, emphasis)?;
    let items = children(block, "relay.callout", 1)?;
    if type_of(&items[0]) == Some("relay.callout_title") && items.len() < 2 {
        bail!("Callout requires a body block");
    }
    if items[1..].iter().any(|item| type_of(item) == Some("relay.callout_title")) {
        bail!("Callout title must be first");
    }
    let mut content = Vec::with_capacity(items.len());
    for (index, item) in items.iter().enumerate() {
        content.push(if index == 0 && type_of(item) == Some("relay.callout_title") {
            let title_id = check_block(item, "relay.callout_title", seen, false)?;
            let parts = inline_children(item, "relay.callout_title")?.iter().map(unmap_inline).collect::<Result<Vec<_>>>()?;
            if parts.iter().any(|part| type_of(part) != Some("text")) {
                bail!("Unsupported callout title inline node");
            }
            pm_node("calloutTitle", id_attrs(&title_id), Some(parts))
        } else {
            unmap_block(item, seen, depth + 1)?
        });
    }
    let mut attrs = id_attrs(&id);
    attrs.insert("tone".into(), tone.clone());
    attrs.insert("emphasis".into(), emphasis.clone());
    Ok(pm_node("callout", attrs, Some(content)))
}

fn unmap_list(block: &Value, seen: &mut Seen, depth: usize) -> Result<Value> {
    if depth >= MAX_LIST_DEPTH {
        bail!("Unsupported nested list depth");
    }
    let id = check_block(block, "list", seen, true)?;
    let props = block.get("props").unwrap_or(&Value::Null);
    assert_object(props, "list.props")?;
    only_keys(props, &["kind", "start"], "list.props")?;
    let ordered = props.get("kind").and_then(Value::as_str) == Some("ordered");
    if !ordered && props.get("kind").and_then(Value::as_str) != Some("bullet") {
        bail!("Invalid list kind");
    }
    let mut attrs = id_attrs(&id);
    if ordered {
        let start = props.get("start").unwrap_or(&Value::Null);
        check_list_start(start)?;
        attrs.insert("start".into(), start.clone());
        attrs.insert("type".into(), Value::Null);
    } else if props.get("start").is_some() {
        bail!("Bullet list has a start");
    }
    let mut content = Vec::new();
    for item in children(block, "list", 1)? {
        let item_id = check_block(item, "list_item", seen, false)?;
        let parts = children(item, "list_item", 1)?;
        if type_of(&parts[0]) != Some("paragraph") {
            bail!("List item must start with a paragraph");
        }
        let mut item_content = vec![unmap_paragraph(&parts[0], seen)?];
        for part in &parts[1..] {
            item_content.push(if type_of(part) == Some("list") { unmap_list(part, seen, depth + 1)? } else { unmap_block(part, seen, 0)? });
        }
        content.push(pm_node("listItem", id_attrs(&item_id), Some(item_content)));
    }
    Ok(pm_node(if ordered { "orderedList" } else { "bulletList" }, attrs, Some(content)))
}

fn unmap_task_list(block: &Value, seen: &mut Seen, depth: usize) -> Result<Value> {
    if depth >= MAX_TASK_DEPTH {
        bail!("Task list nesting exceeds the draft limit");
    }
    let id = check_block(block, "task_list", seen, false)?;
    let items = children(block, "task_list", 1)?;
    if items.len() > MAX_TASK_CHILDREN {
        bail!("Task list exceeds the draft child limit");
    }
    let mut content = Vec::new();
    for item in items {
        let item_id = check_block(item, "task_item", seen, true)?;
        let props = item.get("props").unwrap_or(&Value::Null);
        assert_object(props, "task_item.props")?;
        only_keys(props, &["checked", "entityId"], "task_item.props")?;
        if props.get("checked").is_none() || props.get("entityId").is_none() {
            bail!("Task item requires checked and entityId props");
        }
        check_task_props(&props["checked"], &props["entityId"])?;
        let parts = children(item, "task_item", 1)?;
        if parts.len() > MAX_TASK_CHILDREN {
            bail!("Task item exceeds the draft child limit");
        }
        if type_of(&parts[0]) != Some("paragraph") {
            bail!("Unsupported task item children");
        }
        let item_content = parts
            .iter()
            .map(|part| if type_of(part) == Some("task_list") { unmap_task_list(part, seen, depth + 1) } else { unmap_block(part, seen, 0) })
            .collect::<Result<_>>()?;
        let mut attrs = id_attrs(&item_id);
        attrs.extend(props.as_object().cloned().unwrap_or_default());
        content.push(pm_node("taskItem", attrs, Some(item_content)));
    }
    Ok(pm_node("taskList", id_attrs(&id), Some(content)))
}

fn unmap_table(block: &Value, seen: &mut Seen) -> Result<Value> {
    let id = check_block(block, "table", seen, false)?;
    let mut rows = Vec::new();
    for row in children(block, "table", 1)? {
        let row_id = check_block(row, "table_row", seen, false)?;
        let mut cells = Vec::new();
        for cell in children(row, "table_row", 1)? {
            let cell_id = check_block(cell, "table_cell", seen, true)?;
            let props = cell.get("props").unwrap_or(&Value::Null);
            let map = assert_object(props, "table_cell.props")?;
            only_keys(props, &["header", "colspan", "rowspan", "colwidth", "align"], "table_cell.props")?;
            let Some(header) = props.get("header").and_then(Value::as_bool) else { bail!("table_cell.header must be boolean") };
            check_cell_props(map)?;
            let mut attrs = id_attrs(&cell_id);
            for key in ["colspan", "rowspan", "colwidth", "align"] {
                attrs.insert(key.into(), props.get(key).cloned().unwrap_or(Value::Null));
            }
            let content = children(cell, "table_cell", 1)?.iter().map(|child| unmap_block(child, seen, 0)).collect::<Result<_>>()?;
            cells.push(pm_node(if header { "tableHeader" } else { "tableCell" }, attrs, Some(content)));
        }
        rows.push(pm_node("tableRow", id_attrs(&row_id), Some(cells)));
    }
    Ok(pm_node("table", id_attrs(&id), Some(rows)))
}

fn unmap_paragraph(block: &Value, seen: &mut Seen) -> Result<Value> {
    let id = check_block(block, "paragraph", seen, false)?;
    let content = inline_children(block, "paragraph")?.iter().map(unmap_inline).collect::<Result<_>>()?;
    Ok(pm_node("paragraph", id_attrs(&id), Some(content)))
}

fn unmap_question(block: &Value, seen: &mut Seen) -> Result<Value> {
    let id = check_block(block, "relay.form_question", seen, true)?;
    let props = form_props(block.get("props").unwrap_or(&Value::Null), false)?;
    let parts = children(block, "relay.form_question", 1)?;
    let mut label = unmap_paragraph(&parts[0], seen)?;
    label["type"] = Value::String("questionLabel".into());
    let mut content = vec![label];
    let mut option_ids = HashSet::new();
    for option in &parts[1..] {
        let option_id = check_block(option, "relay.form_option", seen, true)?;
        let option_props = form_props(option.get("props").unwrap_or(&Value::Null), true)?;
        if !option_ids.insert(json::stringify(&option_props["id"])) {
            bail!("Duplicate option identity");
        }
        let mut attrs = id_attrs(&option_id);
        attrs.extend(option_props);
        let option_content = inline_children(option, "relay.form_option")?.iter().map(unmap_inline).collect::<Result<_>>()?;
        content.push(pm_node("questionOption", attrs, Some(option_content)));
    }
    let mut attrs = id_attrs(&id);
    attrs.extend(props);
    Ok(pm_node("questionBlock", attrs, Some(content)))
}
