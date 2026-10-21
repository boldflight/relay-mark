//! Authored Paper controls (button, anchor, connection), block entity
//! references, and authored destinations. Execution, navigation targets and
//! hydration belong to hosts.

use serde_json::{Value, json};

use crate::error::{Result, bail};
use crate::json::{self, Map};
use crate::jsre::js_regex;

pub const CONTROLS: [(&str, &str, &str, &[&str]); 3] = [
    ("button", "Button", "relayButton", &["label", "kind", "target"]),
    ("anchor", "Anchor", "relayAnchor", &["name"]),
    ("connection", "Connection", "relayConnection", &["provider"]),
];

pub fn control_fields(control: &str) -> Option<&'static [&'static str]> {
    CONTROLS.iter().find(|c| c.0 == control).map(|c| c.3)
}

pub fn control_node_name(control: &str) -> Option<&'static str> {
    CONTROLS.iter().find(|c| c.0 == control).map(|c| c.2)
}

pub fn control_for_node(node_name: &str) -> Option<&'static str> {
    CONTROLS.iter().find(|c| c.2 == node_name).map(|c| c.0)
}

pub fn anchor_name(value: &str) -> bool {
    js_regex!(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$").is_match(value)
}

fn safe_control_link(value: &str) -> bool {
    if value.chars().any(|c| json::is_js_space(c) || (c as u32) < 0x20 || c == '\u{7f}' || c == '\\') {
        return false;
    }
    (value.starts_with('/') && !value.starts_with("//"))
        || js_regex!(r"^(?i:https?)://[^/?#]+").is_match(value)
        || js_regex!(r"^(?i:mailto):[^?]+").is_match(value)
}

/// The canonical one-line source of an authored control.
pub fn canonical_control_source(control: &str, authored: &Map) -> Result<String> {
    let Some(fields) = control_fields(control) else { bail!("Invalid paper control fields") };
    if authored.len() != fields.len()
        || authored.keys().any(|key| !fields.contains(&key.as_str()))
        || fields.iter().any(|key| !authored.get(*key).is_some_and(Value::is_string))
    {
        bail!("Invalid paper control fields");
    }
    let text = |key: &str| authored[key].as_str().unwrap_or_default();
    if control == "button" {
        let target = text("target");
        let valid_target = match text("kind") {
            "anchor" => anchor_name(target),
            "link" => safe_control_link(target),
            "command" => js_regex!(r"^/[a-z][a-z0-9._-]*(?: [^\x{0}-\x{1f}\x{7f}]+)?$").is_match(target),
            _ => false,
        };
        if json::js_trim(text("label")).is_empty() || !valid_target {
            bail!("Invalid paper button");
        }
    }
    if control == "anchor" && !anchor_name(text("name")) {
        bail!("Invalid paper anchor");
    }
    if control == "connection" && !js_regex!(r"^[a-z][a-z0-9_-]*$").is_match(text("provider")) {
        bail!("Invalid paper connection");
    }
    let name = CONTROLS.iter().find(|c| c.0 == control).map(|c| c.1).unwrap_or_default();
    let pairs: Vec<String> = fields.iter().map(|key| format!("{key}: {}", json::stringify(&authored[*key]))).collect();
    let source = format!("@{name}({})", pairs.join(", "));
    if json::utf16_len(&source) > 16_384 {
        bail!("Paper control source exceeds the draft limit");
    }
    Ok(source)
}

/// Control discriminant, authored fields and source, when they agree.
pub fn assert_control_props(props: Option<&Value>) -> Result<(String, Map, String)> {
    let Some(props) = props.and_then(Value::as_object) else { bail!("Invalid paper control") };
    let authored: Map = props.iter().filter(|(k, _)| *k != "control" && *k != "source").map(|(k, v)| (k.clone(), v.clone())).collect();
    let control = props.get("control").and_then(Value::as_str).unwrap_or("");
    let source = props.get("source").and_then(Value::as_str);
    let Some(source) = source else { bail!("Paper control source/fields mismatch") };
    let canonical = canonical_control_source(control, &authored)?;
    if source != canonical {
        bail!("Paper control source/fields mismatch");
    }
    Ok((control.to_owned(), authored, canonical))
}

/// Parse `@Button(...)`, `@Anchor(...)` or `@Connection(...)` source.
pub fn parse_control_source(source: &str) -> Option<(String, Map, String)> {
    if json::utf16_len(source) > 16_384 {
        return None;
    }
    let captures = js_regex!(r"^@(Button|Anchor|Connection)\s*\(([\s\S]*)\)$").captures(json::js_trim(source))?;
    let control = CONTROLS.iter().find(|c| c.1 == &captures[1]).map(|c| c.0)?;
    let mut attrs = Map::new();
    let mut rest = json::js_trim(&captures[2]);
    let pair = js_regex!(r#"^([a-z]+)\s*:\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')\s*"#);
    while !rest.is_empty() {
        let found = pair.captures(rest)?;
        let key = found[1].to_owned();
        if attrs.contains_key(&key) {
            return None;
        }
        let raw = &found[2];
        let value = if raw.starts_with('"') {
            serde_json::from_str::<Value>(raw).ok()?
        } else {
            Value::String(js_regex!(r"\\(['\\])").replace_all(&raw[1..raw.len() - 1], "$1").into_owned())
        };
        attrs.insert(key, value);
        rest = &rest[found[0].len()..];
        if rest.is_empty() {
            break;
        }
        rest = rest.strip_prefix(',')?.trim_start_matches(json::is_js_space);
        if rest.is_empty() {
            return None;
        }
    }
    let source = canonical_control_source(control, &attrs).ok()?;
    Some((control.to_owned(), attrs, source))
}

/// Authored destinations by canonical tree position: explicit anchors, then
/// headings with their explicit or derived names, made unique in order.
pub fn paper_destinations(document: &Value) -> Vec<Value> {
    fn visit<'a>(node: &'a Value, path: Vec<usize>, out: &mut Vec<(&'a Value, Vec<usize>)>) {
        out.push((node, path.clone()));
        if let Some(children) = node.get("content").and_then(Value::as_array) {
            for (index, child) in children.iter().enumerate() {
                let mut next = path.clone();
                next.push(index);
                visit(child, next, out);
            }
        }
    }
    fn text(node: &Value) -> String {
        if json::str_field(node, "type") == Some("text") {
            return node.get("text").and_then(Value::as_str).unwrap_or_default().to_owned();
        }
        node.get("content").and_then(Value::as_array).map(|c| c.iter().map(text).collect()).unwrap_or_default()
    }
    let mut nodes = Vec::new();
    visit(document, Vec::new(), &mut nodes);
    let anchors: Vec<Value> = nodes
        .iter()
        .filter_map(|(node, path)| {
            let name = json::field(node, "attrs").and_then(|a| a.get("name")).and_then(Value::as_str)?;
            (json::str_field(node, "type") == Some("relayAnchor") && anchor_name(name)).then(|| json!({"source_path": path, "kind": "anchor", "name": name}))
        })
        .collect();
    let mut used: std::collections::HashSet<String> = anchors.iter().filter_map(|a| a["name"].as_str().map(str::to_owned)).collect();
    let mut headings = Vec::new();
    for (node, path) in &nodes {
        if json::str_field(node, "type") != Some("heading") {
            continue;
        }
        let explicit = json::field(node, "attrs").and_then(|a| a.get("headingId")).and_then(Value::as_str).filter(|id| anchor_name(id));
        let name = match explicit {
            Some(id) => id.to_owned(),
            None => heading_slug(&text(node)),
        };
        let mut candidate = name.clone();
        let mut suffix = 2;
        while used.contains(&candidate) {
            candidate = format!("{name}-{suffix}");
            suffix += 1;
        }
        used.insert(candidate.clone());
        headings.push(json!({"source_path": path, "kind": "heading", "name": candidate}));
    }
    anchors.into_iter().chain(headings).collect()
}

fn heading_slug(text: &str) -> String {
    use unicode_normalization::UnicodeNormalization;
    let lowered = json::js_trim(text).to_lowercase();
    let stripped: String = lowered.nfkd().filter(|c| !('\u{300}'..='\u{36f}').contains(c)).collect();
    let replaced = js_regex!(r"[^a-z0-9_-]+").replace_all(&stripped, "-");
    let trimmed = replaced.trim_matches('-');
    let slug: String = trimmed.chars().take(110).collect();
    if slug.is_empty() { "section".to_owned() } else { slug }
}

// ---- Block entity references: `@EntityRef(id: "entity:<uuid>", ...) { label }` ----

pub struct EntityReference {
    pub id: String,
    pub entity_id: String,
    pub label: String,
    pub projection: String,
    pub body: String,
    pub source: String,
}

pub fn parse_entity_reference_source(source: &str) -> Option<EntityReference> {
    if json::utf16_len(source) > 16_384 {
        return None;
    }
    let found = js_regex!(r"^@EntityRef\s*\(([\s\S]*?)\)\s*\{(?:\r\n|\n|\r)  ([^\r\n{}]+)(?:\r\n|\n|\r)\}$").captures(source)?;
    let mut attrs = Map::new();
    let mut rest = json::js_trim(&found[1]);
    while !rest.is_empty() {
        let key = js_regex!(r"^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*").captures(rest)?;
        let name = key[1].to_owned();
        if !["id", "label", "projection"].contains(&name.as_str()) || attrs.contains_key(&name) {
            return None;
        }
        rest = &rest[key[0].len()..];
        let value = js_regex!(r#"^"(?:\\.|[^"\\])*""#).find(rest)?;
        let parsed: Value = serde_json::from_str(value.as_str()).ok()?;
        if !parsed.is_string() {
            return None;
        }
        attrs.insert(name, parsed);
        rest = rest[value.end()..].trim_start_matches(json::is_js_space);
        if rest.is_empty() {
            break;
        }
        rest = rest.strip_prefix(',')?.trim_start_matches(json::is_js_space);
        if rest.is_empty() {
            return None;
        }
    }
    let id = attrs.get("id").and_then(Value::as_str)?;
    let entity_id = id.strip_prefix("entity:")?;
    if !js_regex!(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$").is_match(entity_id) {
        return None;
    }
    let projection = attrs.get("projection").and_then(Value::as_str).filter(|p| !p.is_empty()).unwrap_or("link");
    if !["link", "chip", "card"].contains(&projection) {
        return None;
    }
    let body = &found[2];
    if body != json::js_trim(body) || js_regex!(r"\[\[|\]\]|\]\(relay:|^[@#]").is_match(body) {
        return None;
    }
    let label = attrs.get("label").and_then(Value::as_str).filter(|l| !l.is_empty()).unwrap_or(body);
    if label.is_empty() || label != json::js_trim(label) || label.contains(['\r', '\n']) {
        return None;
    }
    Some(EntityReference {
        id: id.to_owned(),
        entity_id: entity_id.to_owned(),
        label: label.to_owned(),
        projection: projection.to_owned(),
        body: body.to_owned(),
        source: source.to_owned(),
    })
}

/// Block reference properties whose fields agree with their authored source.
pub fn assert_entity_reference_props(props: Option<&Value>) -> Result<EntityReference> {
    let Some(map) = props.and_then(Value::as_object).filter(|p| p.keys().all(|k| ["id", "label", "projection", "source"].contains(&k.as_str()))) else {
        bail!("Unsupported entity reference props")
    };
    let parsed = map.get("source").and_then(Value::as_str).and_then(parse_entity_reference_source);
    match parsed {
        Some(parsed)
            if map.get("id").and_then(Value::as_str) == Some(parsed.id.as_str())
                && map.get("label").and_then(Value::as_str) == Some(parsed.label.as_str())
                && map.get("projection").and_then(Value::as_str) == Some(parsed.projection.as_str()) =>
        {
            Ok(parsed)
        }
        _ => bail!("Entity reference source/identity mismatch"),
    }
}

/// `JSON.stringify` of an optional value, spelling a missing one `undefined`.
fn js_literal(value: Option<&Value>) -> String {
    value.map(json::stringify).unwrap_or_else(|| "undefined".to_owned())
}

pub fn build_block_entity_reference_source(attrs: &Map, body: &str) -> Result<String> {
    if attrs.keys().any(|k| !["id", "label", "projection"].contains(&k.as_str())) {
        bail!("Invalid block reference source");
    }
    let body_value = Value::String(body.to_owned());
    let label = attrs.get("label").filter(|v| json::truthy(Some(v))).unwrap_or(&body_value);
    let projection_default = Value::String("link".into());
    let projection = attrs.get("projection").filter(|v| json::truthy(Some(v))).unwrap_or(&projection_default);
    let source = format!(
        "@EntityRef(id: {}, label: {}, projection: {}) {{\n  {body}\n}}",
        js_literal(attrs.get("id")),
        json::stringify(label),
        json::stringify(projection)
    );
    if parse_entity_reference_source(&source).is_none() {
        bail!("Invalid block reference source");
    }
    Ok(source)
}
