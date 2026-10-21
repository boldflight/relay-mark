//! Finite historical conversions. Each runs once at a recorded boundary with a
//! retained namespace, so a retry allocates the same identities. Ordinary
//! editing never calls these.

use std::collections::{HashMap, HashSet};

use serde_json::{Value, json};

use crate::adapter::{identified_node_names, validate_question_props};
use crate::error::{Result, bail};
use crate::json::{self, Map};
use crate::jsre::js_regex;
use crate::node_kind::is_block_node;
use crate::registry::directive_node_for_type;
use crate::snapshot::{decode_attributes, encode_attributes, is_settings_node, normalize_document, settings_policy, snapshot_to_document};
use crate::source::{block_id, normalize_newlines, parse_document};

fn is_canonical_id(id: &str) -> bool {
    js_regex!(r"^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$").is_match(id)
}

fn require_namespace(namespace: &str) -> Result<()> {
    if namespace.is_empty() {
        bail!("Migration requires retained namespace");
    }
    Ok(())
}

fn path_strings(prefix: &[&str], path: &[usize]) -> Vec<String> {
    prefix.iter().map(|s| (*s).to_owned()).chain(path.iter().map(usize::to_string)).collect()
}

fn mapping() -> Map {
    Map::from_iter([("retained".into(), json!([])), ("remapped".into(), json!([])), ("added".into(), json!([]))])
}

fn push(mapping: &mut Map, key: &str, value: Value) {
    if let Some(items) = mapping.get_mut(key).and_then(Value::as_array_mut) {
        items.push(value);
    }
}

/// Historical AST (prerelease lineage) to the canonical document. Returns
/// `{document, identity_mapping}`.
pub fn import_document(original: &Value, namespace: &str) -> Result<Value> {
    if !original.is_object() || namespace.is_empty() {
        bail!("Migration requires document and retained namespace");
    }
    let mut document = original.clone();
    let mut identity = mapping();
    let mut ids: HashMap<String, String> = HashMap::new();
    let mut seen: HashSet<String> = HashSet::new();
    if let Some(version) = document.as_object_mut().and_then(|d| d.shift_remove("version"))
        && version.as_f64() != Some(1.0)
    {
        bail!("Unknown historical document version");
    }
    rename_profiles(&mut document);
    struct Walk<'a> {
        namespace: &'a str,
        identity: &'a mut Map,
        ids: &'a mut HashMap<String, String>,
        seen: &'a mut HashSet<String>,
    }
    fn visit(walk: &mut Walk<'_>, node: &mut Value) -> Result<()> {
        if !is_block_node(node) {
            bail!("Historical block shape");
        }
        let old = node["id"].as_str().filter(|id| !id.is_empty() && !walk.seen.contains(*id)).map(str::to_owned);
        let Some(old) = old else { bail!("Historical block identity") };
        walk.seen.insert(old.clone());
        if is_canonical_id(&old) {
            push(walk.identity, "retained", json!(old));
            walk.ids.insert(old.clone(), old.clone());
        } else {
            let next = block_id(walk.namespace, &["migration".into(), "block".into(), old.clone()]);
            node["id"] = json!(next);
            push(walk.identity, "remapped", json!({"from": old, "to": next}));
            walk.ids.insert(old.clone(), next);
        }
        if let Some(object) = node.as_object_mut()
            && let Some(evidence_refs) = object.get("evidence_refs")
        {
            let props_evidence = object.get("props").and_then(|p| p.get("evidence"));
            if !evidence_refs.is_array() || Some(json::stringify(evidence_refs)) != props_evidence.map(json::stringify) {
                bail!("Ambiguous historical evidence");
            }
            object.shift_remove("evidence_refs");
        }
        let children = match node.get("content") {
            None | Some(Value::Null) => Vec::new(),
            Some(Value::Array(items)) => items.clone(),
            Some(_) => bail!("Historical content"),
        };
        let mut content = Vec::with_capacity(children.len());
        for mut child in children {
            if is_block_node(&child) {
                visit(walk, &mut child)?;
            }
            content.push(child);
        }
        if node["type"].as_str().and_then(directive_node_for_type).is_some() {
            let parent = node["id"].clone();
            let mut normalized: Vec<Value> = Vec::new();
            let mut pending: Vec<Value> = Vec::new();
            let flush = |normalized: &mut Vec<Value>, pending: &mut Vec<Value>, identity: &mut Map| {
                if !pending.is_empty() {
                    let index = normalized.len();
                    let wrapper = block_id(walk.namespace, &["migration".into(), old.clone(), "inline".into(), index.to_string()]);
                    push(identity, "added", json!({"id": wrapper, "parent": parent, "role": "inline_body", "index": index}));
                    normalized.push(json!({"id": wrapper, "type": "paragraph", "content": std::mem::take(pending)}));
                }
            };
            for child in content {
                if is_block_node(&child) {
                    flush(&mut normalized, &mut pending, walk.identity);
                    normalized.push(child);
                } else {
                    pending.push(child);
                }
            }
            flush(&mut normalized, &mut pending, walk.identity);
            content = normalized;
        }
        node["content"] = Value::Array(content);
        Ok(())
    }
    let Some(blocks) = document.get_mut("blocks").and_then(Value::as_array_mut) else { bail!("Historical document blocks") };
    let mut walk = Walk { namespace, identity: &mut identity, ids: &mut ids, seen: &mut seen };
    for block in blocks.iter_mut() {
        visit(&mut walk, block)?;
    }
    remap_references(&mut document, &ids);
    let normalized = normalize_document(&document)?;
    document["blocks"] = normalized["blocks"].clone();
    Ok(json!({"document": document, "identity_mapping": identity}))
}

fn rename_profiles(value: &mut Value) {
    match value {
        Value::Array(items) => items.iter_mut().for_each(rename_profiles),
        Value::Object(map) => {
            for (key, child) in map.iter_mut() {
                let renamed = match (key.as_str(), child.as_str()) {
                    ("profile", Some("relaymark.agent_answer.v1")) => Some("relaymark.agent_answer"),
                    ("profile", Some("relaymark.scripture_release.v1")) => Some("relaymark.scripture_release"),
                    ("profile", Some("relaymark.scripture_span.v1")) => Some("relaymark.scripture_span"),
                    _ => None,
                };
                match renamed {
                    Some(name) => *child = json!(name),
                    None => rename_profiles(child),
                }
            }
        }
        _ => {}
    }
}

/// Only known AST block references move; host identities stay exact.
fn remap_references(value: &mut Value, ids: &HashMap<String, String>) {
    match value {
        Value::Array(items) => items.iter_mut().for_each(|item| remap_references(item, ids)),
        Value::Object(map) => {
            for (key, child) in map.iter_mut() {
                if matches!(key.as_str(), "block_id" | "start_block_id" | "end_block_id")
                    && let Some(next) = child.as_str().and_then(|id| ids.get(id))
                {
                    *child = json!(next);
                } else if key == "evidence" && child.is_array() {
                    for item in child.as_array_mut().into_iter().flatten() {
                        if let Some(next) = item.as_str().and_then(|id| ids.get(id)) {
                            *item = json!(next);
                        }
                    }
                } else {
                    remap_references(child, ids);
                }
            }
        }
        _ => {}
    }
}

/// Finite historical source (exact or Markdown) through the same grammar.
pub fn import_document_source(source: &str, namespace: &str) -> Result<Value> {
    if namespace.is_empty() {
        bail!("Migration requires source and retained namespace");
    }
    let normalized = normalize_newlines(source);
    let document = match crate::source::exact_interchange(&normalized) {
        Some(exact) => exact?,
        None => parse_document(&normalized, Some(namespace))?,
    };
    import_document(&document, namespace)
}

/// Finite XML migration. Returns edits for the host's existing CRDT
/// transaction; it never allocates a replica or rewrites text, items or history.
pub fn import_document_snapshot(original: &Value, namespace: &str) -> Result<Value> {
    import_owned_document_snapshot(original.clone(), namespace)
}

/// [`import_document_snapshot`] of a snapshot the caller gives up.
pub fn import_owned_document_snapshot(original: Value, namespace: &str) -> Result<Value> {
    require_namespace(namespace)?;
    let mut snapshot = original;
    let mut changes: Vec<Value> = Vec::new();
    let mut identity = mapping();
    let mut seen: HashSet<String> = HashSet::new();
    let identified = identified_node_names();
    fn visit(node: &mut Value, path: Vec<usize>, depth: usize, context: &mut (&str, &[&str], &mut Vec<Value>, &mut Map, &mut HashSet<String>)) -> Result<()> {
        if depth > 64 || !node.is_object() {
            bail!("Invalid historical XML");
        }
        if node["kind"] == "text" {
            return Ok(());
        }
        if node["kind"] != "element" || !node["children"].is_array() {
            bail!("Invalid historical XML element");
        }
        let name = node["name"].as_str().unwrap_or_default().to_owned();
        let (namespace, identified, changes, identity, seen) = context;
        if identified.contains(&name.as_str()) {
            if !node["attributes"].is_object() {
                bail!("Invalid historical XML attributes");
            }
            let old = node["attributes"].get("relaymarkId").cloned();
            if let Some(old) = &old {
                match old.as_str() {
                    Some(id) if !id.is_empty() && !seen.contains(id) => {
                        seen.insert(id.to_owned());
                    }
                    _ => bail!("Historical XML identity"),
                }
            }
            match old.as_ref().and_then(Value::as_str).filter(|id| is_canonical_id(id)) {
                Some(id) => push(identity, "retained", json!(id)),
                None => {
                    let next = block_id(namespace, &path_strings(&["migration", "xml"], &path));
                    node["attributes"]["relaymarkId"] = json!(next);
                    let mut change = Map::from_iter([
                        ("path".into(), json!(path)),
                        ("operation".into(), json!(if old.is_none() { "add_attribute" } else { "set_attribute" })),
                        ("name".into(), json!("relaymarkId")),
                    ]);
                    if let Some(old) = &old {
                        change.insert("before".into(), old.clone());
                    }
                    change.insert("value".into(), json!(next));
                    changes.push(Value::Object(change));
                    match old {
                        None => push(identity, "added", json!({"id": next, "path": path, "attribute": "relaymarkId"})),
                        Some(old) => push(identity, "remapped", json!({"from": old, "to": next, "path": path})),
                    }
                }
            }
        }
        if name == "videoEmbed" {
            let defaults = [
                ("playbackId", Value::Null),
                ("title", Value::Null),
                ("source", json!("mux")),
                ("thumbnailUrl", Value::Null),
                ("status", json!("ready")),
                ("youtubeId", Value::Null),
                ("uploadPercent", Value::Null),
            ];
            for (key, default) in defaults {
                if let Some(value) = node["attributes"].get(key).cloned() {
                    if value != default {
                        bail!("Historical video requires retained domain presentation evidence");
                    }
                    changes.push(json!({"path": path, "operation": "remove_attribute", "name": key, "before": value}));
                    node["attributes"].as_object_mut().map(|a| a.shift_remove(key));
                }
            }
        }
        let obsolete: &[&str] = match name.as_str() {
            "relayReference" => &["status", "subtitle"],
            "relayTag" => &["color"],
            _ => &[],
        };
        for key in obsolete {
            if let Some(value) = node["attributes"].get(*key).cloned() {
                if !value.is_null() {
                    bail!("Historical inline atom requires retained presentation evidence");
                }
                changes.push(json!({"path": path, "operation": "remove_attribute", "name": key, "before": null}));
                node["attributes"].as_object_mut().map(|a| a.shift_remove(*key));
            }
        }
        let count = node["children"].as_array().map_or(0, Vec::len);
        for index in 0..count {
            let mut child_path = path.clone();
            child_path.push(index);
            visit(&mut node["children"][index], child_path, depth + 1, context)?;
        }
        Ok(())
    }
    if snapshot["kind"] != "fragment" || !snapshot["children"].is_array() {
        bail!("Historical XML root");
    }
    {
        let mut context = (namespace, identified.as_slice(), &mut changes, &mut identity, &mut seen);
        let count = snapshot["children"].as_array().map_or(0, Vec::len);
        for index in 0..count {
            visit(&mut snapshot["children"][index], vec![index], 0, &mut context)?;
        }
    }
    let document = snapshot_to_document(&snapshot)?;
    Ok(json!({"snapshot": snapshot, "document": document, "identity_mapping": identity, "normalizations": changes, "requires_reconstruction": false}))
}

/// Detached preview of an archive whose form settings are one aggregate
/// attribute. The caller keeps the original bytes and qualifies any cut.
pub fn import_aggregate_settings_snapshot(snapshot: &Value) -> Result<Value> {
    let only = |value: &Value, keys: &[&str]| -> Result<()> {
        match value.as_object() {
            Some(map) if map.keys().all(|k| keys.contains(&k.as_str())) => Ok(()),
            _ => bail!("Invalid finite snapshot shape"),
        }
    };
    only(snapshot, &["kind", "children", "metadata"])?;
    if snapshot["kind"] != "fragment" {
        bail!("Invalid finite fragment");
    }
    let (logical, presence, prefix) = settings_policy();
    let mut normalizations: Vec<Value> = Vec::new();
    let mut encoding: Option<&str> = None;
    fn nodes(
        children: &Value,
        path: &[usize],
        depth: usize,
        state: &mut (&mut Vec<Value>, &mut Option<&'static str>, &str, &Value, &str),
        only: &dyn Fn(&Value, &[&str]) -> Result<()>,
    ) -> Result<Vec<Value>> {
        let Some(children) = children.as_array().filter(|_| depth <= 64) else { bail!("Invalid finite children") };
        let mut result = Vec::with_capacity(children.len());
        for (index, node) in children.iter().enumerate() {
            let mut current = path.to_vec();
            current.push(index);
            if node.get("kind").and_then(Value::as_str) == Some("text") {
                result.push(node.clone());
                continue;
            }
            only(node, &["kind", "name", "attributes", "children"])?;
            let Some(name) = node["name"].as_str().filter(|_| node["kind"] == "element") else { bail!("Invalid finite element") };
            let Some(original) = node["attributes"].as_object() else { bail!("Invalid finite attributes") };
            let (normalizations, encoding, logical, presence, prefix) = state;
            let attributes = if is_settings_node(name) {
                let current_encoding = original.get(*logical) == Some(*presence);
                let kind = if current_encoding { "canonical" } else { "aggregate" };
                if encoding.is_some_and(|known| known != kind) {
                    bail!("Mixed settings encoding");
                }
                **encoding = Some(kind);
                if current_encoding {
                    decode_attributes(name, &node["attributes"])?;
                    original.clone()
                } else {
                    let aggregate = original.get(*logical).filter(|v| v.is_object());
                    let Some(aggregate) = aggregate else { bail!("Aggregate settings required") };
                    if original.keys().any(|k| k.starts_with(*prefix)) {
                        bail!("Mixed settings encoding");
                    }
                    let encoded = encode_attributes(name, original)?;
                    normalizations.push(json!({"path": current, "operation": "set_attribute", "name": logical, "before": aggregate, "value": presence}));
                    let mut fields: Vec<&String> = encoded.keys().filter(|k| k.starts_with(*prefix)).collect();
                    fields.sort();
                    for field in fields {
                        normalizations.push(json!({"path": current, "operation": "add_attribute", "name": field, "value": encoded[field]}));
                    }
                    encoded
                }
            } else {
                original.clone()
            };
            let mut copy = node.as_object().cloned().unwrap_or_default();
            copy.insert("attributes".into(), Value::Object(attributes));
            copy.insert("children".into(), Value::Array(nodes(&node["children"], &current, depth + 1, state, only)?));
            result.push(Value::Object(copy));
        }
        Ok(result)
    }
    let mut state = (&mut normalizations, &mut encoding, logical, presence, prefix);
    let children = nodes(&snapshot["children"], &[], 0, &mut state, &only)?;
    let mut normalized = Map::from_iter([("kind".into(), json!("fragment")), ("children".into(), Value::Array(children))]);
    if let Some(metadata) = snapshot.get("metadata") {
        normalized.insert("metadata".into(), metadata.clone());
    }
    let normalized = Value::Object(normalized);
    let document = snapshot_to_document(&normalized)?;
    let cut = !normalizations.is_empty();
    Ok(json!({"snapshot": normalized, "document": document, "normalizations": normalizations, "requires_physical_history_cut": cut}))
}

// ---- Saved form publications ----

fn same(left: &Value, right: &Value) -> bool {
    json::stable_stringify(left) == json::stable_stringify(right)
}

fn object(value: &Value) -> Result<&Map> {
    match value.as_object() {
        Some(map) => Ok(map),
        None => bail!("Invalid historical publication object"),
    }
}

/// Semantic projection without AST block identities.
fn semantic(value: &Value) -> Value {
    match value {
        Value::Array(items) => Value::Array(items.iter().map(semantic).collect()),
        Value::Object(map) => {
            let block_identity = is_block_node(value) && map.get("id").is_some_and(Value::is_string);
            Value::Object(
                map.iter()
                    .filter(|(k, _)| !(*k == "id" && block_identity))
                    .map(|(k, v)| (k.clone(), if k == "props" { v.clone() } else { semantic(v) }))
                    .collect(),
            )
        }
        other => other.clone(),
    }
}

fn publication_settings(block: &Map, known: &[&str]) -> Result<Map> {
    let mut value = object(block.get("settings").unwrap_or(&json!({})))?.clone();
    for (key, item) in block {
        if known.contains(&key.as_str()) || key == "settings" {
            continue;
        }
        if value.get(key).is_some_and(|existing| !same(existing, item)) {
            bail!("Conflicting historical setting");
        }
        value.insert(key.clone(), item.clone());
    }
    Ok(value)
}

fn js_sorted(values: &mut [Value]) {
    values.sort_by_key(|v| match v {
        Value::String(text) => text.encode_utf16().collect::<Vec<_>>(),
        other => json::stringify(other).encode_utf16().collect(),
    });
}

fn grading(question: &Value) -> Result<()> {
    let props = &question["props"];
    let key = &props["settings"]["answer_key"];
    if key.is_null() {
        return Ok(());
    }
    object(key)?;
    let points = &props["points"];
    if !key["points"].is_null() && !points.is_null() && !same(&key["points"], points) {
        bail!("Conflicting grading points");
    }
    let kind = props["type"].as_str().unwrap_or_default();
    if kind == "multiple_choice" || kind == "checkboxes" {
        let mut correct: Vec<Value> =
            question["content"].as_array().into_iter().flatten().skip(1).filter(|n| n["props"]["correct"] == true).map(|n| n["props"]["id"].clone()).collect();
        let expected = if kind == "multiple_choice" {
            if correct.len() == 1 { correct[0].clone() } else { Value::Null }
        } else {
            js_sorted(&mut correct);
            Value::Array(correct)
        };
        let actual = match &key["correct_answer"] {
            Value::Array(items) => {
                let mut items = items.clone();
                js_sorted(&mut items);
                Value::Array(items)
            }
            other => other.clone(),
        };
        if !same(&expected, &actual) {
            bail!("Conflicting grading answer");
        }
    }
    Ok(())
}

fn merge_settings(saved: &Value, retained: &Value, path: Vec<Value>, normalizations: &mut Vec<Value>) -> Result<Value> {
    let mut result = saved.as_object().cloned().unwrap_or_default();
    for (key, value) in retained.as_object().into_iter().flatten() {
        let mut child_path = path.clone();
        child_path.push(json!(key));
        match result.get(key) {
            None => {
                result.insert(key.clone(), value.clone());
                normalizations.push(json!({"path": child_path, "operation": "recover_retained_source_setting"}));
            }
            Some(existing) if existing.is_object() && value.is_object() => {
                let merged = merge_settings(existing, value, child_path, normalizations)?;
                result.insert(key.clone(), merged);
            }
            Some(existing) if !same(existing, value) => bail!("Conflicting retained publication setting"),
            Some(_) => {}
        }
    }
    Ok(Value::Object(result))
}

/// Saved form publication to the canonical document. `source`, when given, is
/// only the same immutable release body.
pub fn import_form_publication(original: &Value, namespace: &str, retained_source: Option<&str>) -> Result<Value> {
    let publication = object(original)?;
    let Some(raw_blocks) = publication.get("blocks").and_then(Value::as_array).filter(|_| !namespace.is_empty()) else {
        bail!("Historical publication requires blocks and retained namespace")
    };
    let canonical = match publication.get("document") {
        Some(document) => {
            let normalized = normalize_document(document)?;
            if !same(&normalized, document) {
                bail!("Current published document must already be canonical");
            }
            Some(normalized)
        }
        None => None,
    };
    let mut normalizations: Vec<Value> = Vec::new();
    let mut identity = mapping();
    let mut blocks: Vec<Value> = Vec::new();
    let mut question_ids: HashSet<String> = HashSet::new();
    let imported = |text: Option<&Value>, role: &str, identity: &mut Map| -> Result<Vec<Value>> {
        let Some(text) = text.and_then(Value::as_str) else { bail!("Historical label must retain source text") };
        let result = import_document_source(text, &format!("{namespace}:publication:{role}"))?;
        if result["document"].as_object().is_some_and(|d| d.keys().any(|k| k != "type" && k != "blocks")) {
            bail!("Publication fragment cannot silently drop source metadata");
        }
        for key in ["retained", "remapped", "added"] {
            for item in result["identity_mapping"][key].as_array().into_iter().flatten() {
                push(identity, key, item.clone());
            }
        }
        Ok(result["document"]["blocks"].as_array().cloned().unwrap_or_default())
    };
    let empty_text = json!("");
    if canonical.is_none() {
        for (position, raw) in raw_blocks.iter().enumerate() {
            let b = object(raw)?;
            let path = json!(["blocks", position]);
            if b.get("type").and_then(Value::as_str) == Some("paragraph") {
                if b.keys().any(|k| k != "type" && k != "label") {
                    bail!("Unknown historical prose block fields");
                }
                let parsed = imported(b.get("label"), &format!("prose:{position}"), &mut identity)?;
                let ids: Vec<Value> = parsed.iter().map(|n| n["id"].clone()).collect();
                blocks.extend(parsed);
                normalizations.push(json!({"path": path, "operation": "import_source", "block_ids": ids}));
                continue;
            }
            let Some(question_id) = b.get("id").and_then(Value::as_str).filter(|id| !id.is_empty() && !question_ids.contains(*id)) else {
                bail!("Invalid historical question identity")
            };
            question_ids.insert(question_id.to_owned());
            let id = block_id(namespace, &["publication".into(), position.to_string(), "question".into()]);
            let inline = |text: Option<&Value>, role: Value, identity: &mut Map| -> Result<Value> {
                let nodes = imported(text, &json::stringify(&role), identity)?;
                if nodes.len() != 1 || nodes[0]["type"] != "paragraph" {
                    bail!("Rich question/option label requires canonical inline content");
                }
                Ok(nodes[0].clone())
            };
            let label = inline(Some(b.get("label").filter(|v| !v.is_null()).unwrap_or(&empty_text)), json!(["label", question_id]), &mut identity)?;
            let nullish = |key: &str, default: Value| b.get(key).filter(|v| !v.is_null()).cloned().unwrap_or(default);
            let props = Map::from_iter([
                ("id".into(), json!(question_id)),
                ("type".into(), b.get("type").cloned().unwrap_or(Value::Null)),
                ("required".into(), nullish("required", json!(false))),
                ("points".into(), nullish("points", Value::Null)),
                ("min".into(), nullish("min", Value::Null)),
                ("max".into(), nullish("max", Value::Null)),
                ("settings".into(), Value::Object(publication_settings(b, &["id", "type", "label", "required", "points", "min", "max", "options"])?)),
            ]);
            validate_question_props(&Value::Object(props.clone()), false)?;
            let options_value = b.get("options");
            if options_value.is_some_and(|o| !o.is_array()) {
                bail!("Historical options must retain their order");
            }
            let mut option_ids: HashSet<String> = HashSet::new();
            let mut options = Vec::new();
            for (index, option) in options_value.and_then(Value::as_array).into_iter().flatten().enumerate() {
                let o = object(option)?;
                let Some(option_id) = o.get("id").and_then(Value::as_str).filter(|id| !id.is_empty() && !option_ids.contains(*id)) else {
                    bail!("Invalid historical option identity")
                };
                option_ids.insert(option_id.to_owned());
                if let (Some(label), Some(text)) = (o.get("label"), o.get("text"))
                    && label != text
                {
                    bail!("Ambiguous historical option label");
                }
                let text = o.get("label").filter(|v| !v.is_null()).or_else(|| o.get("text").filter(|v| !v.is_null())).unwrap_or(&empty_text);
                let label = inline(Some(text), json!(["option", question_id, option_id]), &mut identity)?;
                let option_block = block_id(namespace, &["publication".into(), position.to_string(), "option".into(), index.to_string()]);
                let option_props = Map::from_iter([
                    ("id".into(), json!(option_id)),
                    ("correct".into(), o.get("correct").filter(|v| !v.is_null()).cloned().unwrap_or(json!(false))),
                    ("points".into(), o.get("points").filter(|v| !v.is_null()).cloned().unwrap_or(Value::Null)),
                    ("settings".into(), Value::Object(publication_settings(o, &["id", "label", "text", "correct", "points"])?)),
                ]);
                validate_question_props(&Value::Object(option_props.clone()), true)?;
                push(&mut identity, "added", json!({"id": option_block, "parent": question_id, "role": "option", "option_id": option_id}));
                options.push(json!({"id": option_block, "type": "relay.form_option", "props": option_props, "content": label["content"]}));
            }
            let option_block_ids: Vec<Value> = options.iter().map(|n| n["id"].clone()).collect();
            let label_id = label["id"].clone();
            let mut content = vec![label];
            content.extend(options);
            let question = json!({"id": id, "type": "relay.form_question", "props": props, "content": content});
            grading(&question)?;
            blocks.push(question);
            push(&mut identity, "added", json!({"id": id, "role": "question", "question_id": question_id}));
            normalizations.push(json!({"path": path, "operation": "form_question", "block_id": id, "label_id": label_id, "option_ids": option_block_ids}));
        }
    }
    let mut document = match &canonical {
        Some(document) => document.clone(),
        None => {
            let blocks = if blocks.is_empty() { imported(Some(&empty_text), "empty", &mut identity)? } else { blocks };
            normalize_document(&json!({"type": "relaymark.document", "blocks": blocks}))?
        }
    };
    if let Some(retained) = retained_source {
        let result = import_document_source(retained, &format!("{namespace}:retained-publication-source"))?;
        let mut retained_document = result["document"].clone();
        let is_question = |n: &&Value| n["type"] == "relay.form_question";
        let saved_blocks = document["blocks"].as_array().cloned().unwrap_or_default();
        let saved_questions: Vec<&Value> = saved_blocks.iter().filter(is_question).collect();
        let retained_blocks = retained_document["blocks"].as_array().cloned().unwrap_or_default();
        let saved_prose: Vec<Value> = saved_blocks.iter().filter(|n| !is_question(n)).cloned().collect();
        let retained_prose: Vec<Value> = retained_blocks.iter().filter(|n| !is_question(n)).cloned().collect();
        let retained_question_count = retained_blocks.iter().filter(is_question).count();
        if saved_questions.len() != retained_question_count || !same(&semantic(&Value::Array(saved_prose)), &semantic(&Value::Array(retained_prose))) {
            bail!("Conflicting retained publication prose or question structure");
        }
        let mut question_index = 0;
        for block in retained_document["blocks"].as_array_mut().into_iter().flatten() {
            if block["type"] != "relay.form_question" {
                continue;
            }
            let saved = saved_questions[question_index];
            question_index += 1;
            let q = block;
            let saved_content = saved["content"].as_array().map(Vec::as_slice).unwrap_or(&[]);
            let q_len = q["content"].as_array().map_or(0, Vec::len);
            if saved["props"]["id"] != q["props"]["id"]
                || saved["props"]["type"] != q["props"]["type"]
                || saved_content.len() != q_len
                || !same(&semantic(&saved_content[0]), &semantic(&q["content"][0]))
            {
                bail!("Conflicting retained publication question/option identity or labels");
            }
            let question_id = q["props"]["id"].clone();
            for index in 1..q_len {
                let old = &saved_content[index];
                let option = &mut q["content"][index];
                if old["props"]["id"] != option["props"]["id"]
                    || old["props"]["correct"] != option["props"]["correct"]
                    || !same(&old["content"], &option["content"])
                {
                    bail!("Conflicting retained option identity/label/correctness");
                }
                if !old["props"]["points"].is_null() && !same(&old["props"]["points"], &option["props"]["points"]) {
                    bail!("Conflicting retained option points");
                }
                let path = vec![json!("question"), question_id.clone(), json!("option"), option["props"]["id"].clone(), json!("settings")];
                option["props"]["settings"] = merge_settings(&old["props"]["settings"], &option["props"]["settings"], path, &mut normalizations)?;
            }
            for key in ["required", "points", "min", "max"] {
                if saved["props"][key].is_null() && !q["props"][key].is_null() {
                    normalizations.push(json!({"path": ["question", question_id, key], "operation": "recover_retained_source_setting"}));
                } else if !same(&saved["props"][key], &q["props"][key]) {
                    bail!("Conflicting retained question setting");
                } else {
                    q["props"][key] = saved["props"][key].clone();
                }
            }
            let path = vec![json!("question"), question_id.clone(), json!("settings")];
            q["props"]["settings"] = merge_settings(&saved["props"]["settings"], &q["props"]["settings"], path, &mut normalizations)?;
            grading(q)?;
        }
        document = normalize_document(&retained_document)?;
        identity = result["identity_mapping"].as_object().cloned().unwrap_or_else(mapping);
        normalizations.push(json!({"path": [], "operation": "use_retained_publication_source"}));
    }
    if let Some(canonical) = canonical {
        if !same(&semantic(&canonical), &semantic(&document)) {
            bail!("Conflicting current published document and retained source");
        }
        document = canonical;
        normalizations.clear();
        identity = mapping();
    }
    let mut used: Vec<String> = Vec::new();
    fn collect(node: &Value, used: &mut Vec<String>) {
        if is_block_node(node)
            && let Some(id) = node["id"].as_str()
            && !used.iter().any(|u| u == id)
        {
            used.push(id.to_owned());
        }
        for child in node.get("content").and_then(Value::as_array).into_iter().flatten() {
            collect(child, used);
        }
    }
    for block in document["blocks"].as_array().into_iter().flatten() {
        collect(block, &mut used);
    }
    let used_set: HashSet<&str> = used.iter().map(String::as_str).collect();
    if publication.contains_key("document") {
        identity.insert("retained".into(), json!(used));
    }
    let keep = |items: &Value, key: Option<&str>| -> Value {
        Value::Array(
            items
                .as_array()
                .into_iter()
                .flatten()
                .filter(|item| {
                    let id = match key {
                        None => item.as_str(),
                        Some(field) => item[field].as_str(),
                    };
                    id.is_some_and(|id| used_set.contains(id))
                })
                .cloned()
                .collect(),
        )
    };
    let retained = keep(&identity["retained"], None);
    let added = keep(&identity["added"], Some("id"));
    let remapped = keep(&identity["remapped"], Some("to"));
    identity.insert("retained".into(), retained);
    identity.insert("remapped".into(), remapped);
    identity.insert("added".into(), added);
    Ok(json!({"document": document, "identity_mapping": identity, "normalizations": normalizations}))
}
