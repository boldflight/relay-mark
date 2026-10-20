//! The portable composition grammar: plain RelayMark source (prose lines and
//! `@Directive(...) { ... }` blocks) compiled to the conformance AST with
//! sequential block ids, plus its deterministic source serializer.

use serde_json::{Value, json};

use crate::controls::{assert_control_props, assert_entity_reference_props, parse_control_source, parse_entity_reference_source};
use crate::error::{Result, bail};
use crate::inline::{parse_atom_source, source_for_atom};
use crate::json::{self, Map};
use crate::jsre::js_regex;
use crate::manifest::project_manifest;
use crate::node_kind::is_block_node;
use crate::registry::{directive_for_name, directive_for_type};
use crate::source::parse_attributes;
use crate::validate::validate_document;

enum Parsed {
    Control { control: String, attrs: Map, source: String },
    Heading { level: usize, text: String },
    Paragraph { text: String },
    Directive { name: String, attrs: Map, children: Vec<Parsed>, source: String, line: usize },
    Invalid,
}

struct State {
    diagnostics: Vec<Value>,
    raw_lines: Vec<String>,
}

fn critical(code: &str, message: &str, line: usize) -> Value {
    json!({"level": "critical", "code": code, "message": message, "location": {"line": line, "column": 1}})
}

/// `{document, manifest, diagnostics}` for RelayMark source.
pub fn compile(source: &str) -> Value {
    let normalized = crate::source::normalize_newlines(source);
    let (frontmatter, body_offset) = parse_frontmatter(&normalized);
    let body = &normalized[body_offset..];
    let lines: Vec<&str> = body.split('\n').collect();
    let skipped = normalized[..body_offset].matches('\n').count();
    let mut raw_lines: Vec<String> = js_regex!(r"[^\r\n]*(?:\r\n|\r|\n|$)").find_iter(source).map(|m| m.as_str().to_owned()).collect();
    if !source.is_empty() && raw_lines.last().is_none_or(|l| !l.is_empty()) {
        raw_lines.push(String::new());
    }
    let raw_lines = raw_lines.into_iter().skip(skipped).collect();
    let mut state = State { diagnostics: Vec::new(), raw_lines };
    let (blocks, _) = parse_blocks(&lines, 0, &mut state, false);
    let mut next_id = 0usize;
    let mut diagnostics = state.diagnostics;
    let compiled: Vec<Value> = blocks.iter().map(|block| compile_block(block, &mut next_id, &mut diagnostics)).collect();
    let resources = collect_resources(&compiled);
    let document = json!({"type": "relaymark.document", "frontmatter": frontmatter, "blocks": compiled, "annotations": [], "resources": resources});
    diagnostics.extend(validate_document(&document, &Value::Null));
    let manifest = project_manifest(&document, &diagnostics);
    json!({"document": document, "manifest": manifest, "diagnostics": diagnostics})
}

fn parse_frontmatter(source: &str) -> (Map, usize) {
    let mut frontmatter = Map::new();
    if !source.starts_with("---\n") {
        return (frontmatter, 0);
    }
    let Some(end) = source.get(4..).and_then(|rest| rest.find("\n---")).map(|i| i + 4) else { return (frontmatter, 0) };
    let raw = json::js_trim(&source[4..end]);
    let mut body = end + 4;
    if source[body..].starts_with('\n') {
        body += 1;
    }
    for line in raw.split('\n') {
        if let Some(found) = js_regex!(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$").captures(line) {
            let value = json::js_trim(&found[2]);
            let value = if value.len() >= 2 && value.starts_with('"') && value.ends_with('"') {
                serde_json::from_str(value).unwrap_or_else(|_| Value::String(value.to_owned()))
            } else {
                Value::String(value.to_owned())
            };
            frontmatter.insert(found[1].to_owned(), value);
        }
    }
    (frontmatter, body)
}

fn heading_line(text: &str) -> Option<(usize, String)> {
    js_regex!(r"^(#{1,6})\s+(.+)$").captures(text).map(|m| (m[1].len(), m[2].to_owned()))
}

fn parse_blocks(lines: &[&str], start: usize, state: &mut State, stop_on_close: bool) -> (Vec<Parsed>, usize) {
    let mut blocks = Vec::new();
    let mut index = start;
    while index < lines.len() {
        let trimmed = json::js_trim(lines[index]);
        if trimmed.is_empty() {
            index += 1;
            continue;
        }
        if trimmed == "}" {
            if stop_on_close {
                return (blocks, index + 1);
            }
            state.diagnostics.push(critical("relaymark.syntax.unexpected_closing", "Unexpected closing directive brace.", index + 1));
            index += 1;
            continue;
        }
        if trimmed.starts_with('@') {
            if let Some((control, attrs, source)) = parse_control_source(trimmed) {
                blocks.push(Parsed::Control { control, attrs, source });
                index += 1;
                continue;
            }
            let (block, next) = parse_directive(lines, index, state);
            blocks.push(block);
            index = next;
            continue;
        }
        if let Some((level, text)) = heading_line(trimmed) {
            blocks.push(Parsed::Heading { level, text });
            index += 1;
            continue;
        }
        let mut paragraph = Vec::new();
        while index < lines.len() {
            let candidate = json::js_trim(lines[index]);
            if candidate.is_empty() || candidate == "}" || candidate.starts_with('@') || js_regex!(r"^(#{1,6})\s+").is_match(candidate) {
                break;
            }
            paragraph.push(candidate);
            index += 1;
        }
        blocks.push(Parsed::Paragraph { text: paragraph.join(" ") });
    }
    if stop_on_close {
        state.diagnostics.push(critical("relaymark.syntax.missing_closing", "Directive is missing a closing brace.", lines.len()));
    }
    (blocks, index)
}

fn has_body_open(header: &str) -> bool {
    let (mut parentheses, mut quote, mut escape) = (0i64, false, false);
    for c in header.chars() {
        if escape {
            escape = false;
            continue;
        }
        if c == '\\' {
            escape = true;
            continue;
        }
        if c == '"' {
            quote = !quote;
            continue;
        }
        if quote {
            continue;
        }
        match c {
            '(' => parentheses += 1,
            ')' => parentheses -= 1,
            '{' if parentheses == 0 => return true,
            _ => {}
        }
    }
    false
}

fn parse_directive(lines: &[&str], start: usize, state: &mut State) -> (Parsed, usize) {
    let mut header_lines = Vec::new();
    let mut index = start;
    while index < lines.len() {
        header_lines.push(json::js_trim(lines[index]));
        if has_body_open(&header_lines.join(" ")) {
            break;
        }
        index += 1;
    }
    let header = header_lines.join(" ");
    let Some(found) = js_regex!(r"^@([A-Z][A-Za-z0-9]*)(?:\((.*)\))?\s*\{\s*$").captures(&header) else {
        state.diagnostics.push(critical("relaymark.syntax.invalid_directive", &format!("Invalid directive header '{header}'."), start + 1));
        return (Parsed::Invalid, index + 1);
    };
    let attrs = match parse_attributes(found.get(2).map_or("", |m| m.as_str())) {
        Ok(attrs) => attrs,
        Err(error) => {
            state.diagnostics.push(critical("relaymark.syntax.invalid_attributes", error.message(), start + 1));
            Map::new()
        }
    };
    let (children, next) = parse_blocks(lines, index + 1, state, true);
    let raw: String = state.raw_lines.get(start..next.min(state.raw_lines.len())).map(|l| l.concat()).unwrap_or_default();
    let source = js_regex!(r"(?:\r\n|\r|\n)$").replace(&raw, "").into_owned();
    (Parsed::Directive { name: found[1].to_owned(), attrs, children, source, line: start + 1 }, next)
}

fn allocate(next_id: &mut usize) -> String {
    *next_id += 1;
    format!("b{next_id}")
}

fn compile_block(block: &Parsed, next_id: &mut usize, diagnostics: &mut Vec<Value>) -> Value {
    match block {
        Parsed::Control { control, attrs, source } => {
            let mut props = Map::from_iter([("control".into(), json!(control))]);
            props.extend(attrs.clone());
            props.insert("source".into(), json!(source));
            json!({"id": allocate(next_id), "type": "relay.paper_control", "props": props, "content": []})
        }
        Parsed::Heading { level, text } => json!({"id": allocate(next_id), "type": "heading", "props": {"level": level}, "content": parse_inline(text)}),
        Parsed::Paragraph { text } => json!({"id": allocate(next_id), "type": "paragraph", "content": parse_inline(text)}),
        Parsed::Invalid => json!({"id": allocate(next_id), "type": "paragraph", "content": [{"type": "text", "text": ""}]}),
        Parsed::Directive { name, attrs, children, source, line } => {
            let directive = directive_for_name(name);
            if directive.is_none() {
                diagnostics.push(json!({"level": "critical", "code": "relaymark.directive.unknown", "message": format!("Unknown directive '{name}'."), "location": {"line": line, "column": 1}}));
            }
            let ast_type = directive.map_or_else(|| format!("relay.unknown_{}", name.to_lowercase()), |d| d.ast_type.clone());
            let mut props = attrs.clone();
            for (key, attribute) in directive.and_then(|d| d.attributes()).into_iter().flatten() {
                if !props.contains_key(key)
                    && let Some(default) = attribute.get("default")
                {
                    props.insert(key.clone(), default.clone());
                }
            }
            if ast_type == "relay.entity_reference"
                && let Some(authored) = parse_entity_reference_source(source)
            {
                let label_matches = match props.get("label").filter(|l| json::truthy(Some(l))) {
                    Some(label) => label.as_str() == Some(authored.label.as_str()),
                    None => authored.label == authored.body,
                };
                let body_matches = matches!(children.as_slice(), [Parsed::Paragraph { text }] if *text == authored.body);
                if props.get("id").and_then(Value::as_str) == Some(authored.id.as_str())
                    && label_matches
                    && props.get("projection").and_then(Value::as_str) == Some(authored.projection.as_str())
                    && body_matches
                {
                    props.insert("source".into(), json!(source));
                }
            }
            let id = allocate(next_id);
            let title = if ast_type == "relay.callout" { props.shift_remove("title") } else { None };
            let title_block = title.as_ref().and_then(Value::as_str).map(|title| {
                let content = if title.is_empty() { json!([]) } else { json!([{"type": "text", "text": title}]) };
                json!({"id": allocate(next_id), "type": "relay.callout_title", "content": content})
            });
            let flatten = ["relay.action_row", "relay.agent_suggestion", "relay.claim", "relay.comparison", "relay.evidence_ref", "relay.transcript_segment"]
                .contains(&ast_type.as_str());
            let mut content: Vec<Value> = match children.as_slice() {
                [Parsed::Paragraph { text }] if flatten => parse_inline(text),
                _ => children.iter().map(|child| compile_block(child, next_id, diagnostics)).collect(),
            };
            if let Some(title_block) = title_block {
                content.insert(0, title_block);
            }
            let evidence = props.get("evidence").and_then(Value::as_array).filter(|e| !e.is_empty()).cloned();
            let mut result = Map::from_iter([
                ("id".into(), json!(id)),
                ("type".into(), json!(ast_type)),
                ("props".into(), Value::Object(props)),
                ("content".into(), Value::Array(content)),
            ]);
            if let Some(evidence) = evidence {
                result.insert("evidence_refs".into(), Value::Array(evidence));
            }
            Value::Object(result)
        }
    }
}

/// Inline prose: canonical `[[...]]` atoms and `[label](relay:kind/id)` references.
fn parse_inline(text: &str) -> Vec<Value> {
    let pattern = js_regex!(r"\[\[[^\]\r\n]+\]\]|\[([^\]]+)\]\(relay:([a-z_]+)/([^)]+)\)");
    let mut nodes = Vec::new();
    let mut last = 0;
    let mut from = 0;
    while let Some(found) = pattern.captures_at(text, from) {
        let whole = found.get(0).map_or(0..0, |m| m.range());
        from = whole.end.max(whole.start + 1);
        let atom = if found[0].starts_with("[[") {
            match parse_atom_source(&found[0]) {
                Some(atom) => Some(atom),
                None => continue,
            }
        } else {
            None
        };
        if whole.start > last {
            nodes.push(json!({"type": "text", "text": &text[last..whole.start]}));
        }
        nodes.push(atom.unwrap_or_else(|| json!({"type": format!("relay.{}_ref", &found[2]), "id": &found[3], "label": &found[1]})));
        last = whole.end;
    }
    if last < text.len() || nodes.is_empty() {
        nodes.push(json!({"type": "text", "text": &text[last..]}));
    }
    nodes.retain(|node| node["type"] != "text" || node["text"].as_str().is_some_and(|t| !t.is_empty()));
    nodes
}

fn collect_resources(blocks: &[Value]) -> Vec<Value> {
    let mut resources: Vec<(String, Value)> = Vec::new();
    fn visit(blocks: &[Value], resources: &mut Vec<(String, Value)>) {
        for block in blocks {
            if block["type"] == "relay.transcript_segment"
                && let Some(source) = block["props"]["source"].as_str()
            {
                let id = source.strip_prefix("transcript:").unwrap_or(source).to_owned();
                let resource = json!({"id": id, "type": "transcript", "uri": source, "label": "Meeting transcript", "scope": "private"});
                match resources.iter_mut().find(|(existing, _)| *existing == id) {
                    Some(entry) => entry.1 = resource,
                    None => resources.push((id, resource)),
                }
            }
            let children: Vec<Value> = block["content"].as_array().into_iter().flatten().filter(|c| is_block_node(c)).cloned().collect();
            visit(&children, resources);
        }
    }
    visit(blocks, &mut resources);
    resources.into_iter().map(|(_, resource)| resource).collect()
}

// ---- Deterministic source serialization of the human-authored subset ----

/// Conformance AST back to one deterministic RelayMark source form.
pub fn serialize(document: &Value) -> Result<String> {
    let mut sections = Vec::new();
    if let Some(frontmatter) = document.get("frontmatter").and_then(Value::as_object).filter(|f| !f.is_empty()) {
        let mut entries: Vec<_> = frontmatter.iter().collect();
        entries.sort_by(|a, b| json::locale_compare(a.0, b.0));
        let lines: Vec<String> = entries.iter().map(|(key, value)| format!("{key}: {}", frontmatter_value(value))).collect();
        sections.push(format!("---\n{}\n---", lines.join("\n")));
    }
    let blocks = document.get("blocks").and_then(Value::as_array).map(Vec::as_slice).unwrap_or(&[]);
    sections.push(blocks.iter().map(serialize_block).collect::<Result<Vec<_>>>()?.join("\n\n"));
    Ok(sections.into_iter().filter(|s| !s.is_empty()).collect::<Vec<_>>().join("\n\n") + "\n")
}

fn frontmatter_value(value: &Value) -> String {
    match value.as_str() {
        Some(text) if js_regex!(r"^[A-Za-z0-9._:-]+$").is_match(text) => text.to_owned(),
        _ => json::stringify(value),
    }
}

fn serialize_value(value: &Value) -> String {
    match value {
        Value::Array(items) => format!("[{}]", items.iter().map(serialize_value).collect::<Vec<_>>().join(", ")),
        Value::Object(map) => {
            let mut entries: Vec<_> = map.iter().collect();
            entries.sort_by(|a, b| json::locale_compare(a.0, b.0));
            format!("{{{}}}", entries.iter().map(|(k, v)| format!("{}: {}", json::stringify(&json!(k)), serialize_value(v))).collect::<Vec<_>>().join(", "))
        }
        other => json::stringify(other),
    }
}

fn serialize_block(block: &Value) -> Result<String> {
    let kind = block["type"].as_str().unwrap_or_default();
    let content = block.get("content").and_then(Value::as_array).map(Vec::as_slice).unwrap_or(&[]);
    if kind == "relay.paper_control" {
        let (_, _, source) = assert_control_props(block.get("props"))?;
        if !block.get("content").and_then(Value::as_array).is_some_and(Vec::is_empty) {
            bail!("Paper control cannot have children");
        }
        return Ok(source);
    }
    if kind == "relay.entity_reference" && block.get("props").and_then(|p| p.get("source")).is_some() {
        let authored = assert_entity_reference_props(block.get("props"))?;
        let parsed_body = content.len() == 1
            && content[0]["type"] == "paragraph"
            && content[0]["content"].as_array().is_some_and(|c| c.len() == 1 && c[0]["type"] == "text" && c[0]["text"] == authored.body.as_str());
        if !content.is_empty() && !parsed_body {
            bail!("Entity reference source/content mismatch");
        }
        return Ok(authored.source);
    }
    if kind == "heading" {
        let level = block["props"]["level"].as_f64().filter(|l| *l != 0.0).unwrap_or(1.0) as usize;
        return Ok(format!("{} {}", "#".repeat(level), serialize_inline(content)?));
    }
    if kind == "paragraph" {
        return serialize_inline(content);
    }
    let Some(directive) = directive_for_type(kind) else { bail!("Cannot serialize unknown RelayMark block type '{kind}'.") };
    let mut entries: Vec<_> = block.get("props").and_then(Value::as_object).into_iter().flatten().collect();
    entries.sort_by(|a, b| json::locale_compare(a.0, b.0));
    let attributes = entries.iter().map(|(k, v)| format!("{k}: {}", serialize_value(v))).collect::<Vec<_>>().join(", ");
    let header = if attributes.is_empty() { format!("@{}", directive.name) } else { format!("@{}({attributes})", directive.name) };
    let child_blocks: Vec<&Value> = content.iter().filter(|c| is_block_node(c)).collect();
    let body = if child_blocks.is_empty() {
        serialize_inline(content)?
    } else {
        child_blocks.into_iter().map(serialize_block).collect::<Result<Vec<_>>>()?.join("\n\n")
    };
    let indented = body.split('\n').map(|line| if line.is_empty() { String::new() } else { format!("  {line}") }).collect::<Vec<_>>().join("\n");
    Ok(format!("{header} {{\n{indented}\n}}"))
}

fn serialize_inline(nodes: &[Value]) -> Result<String> {
    let mut out = String::new();
    for node in nodes {
        let kind = node["type"].as_str().unwrap_or_default();
        if kind == "text" {
            out.push_str(node["text"].as_str().unwrap_or_default());
            continue;
        }
        let has_props = node.get("props").and_then(Value::as_object).is_some_and(|p| !p.is_empty());
        if (kind == "relay.entity_ref" || kind == "relay.tag_ref") && has_props {
            out.push_str(&source_for_atom(node)?);
            continue;
        }
        if kind.starts_with("relay.") && kind.ends_with("_ref") {
            let reference_kind = &kind["relay.".len()..kind.len() - "_ref".len()];
            let truthy = |key: &str| {
                node.get(key).filter(|v| json::truthy(Some(v))).map(|v| match v.as_str() {
                    Some(text) => text.to_owned(),
                    None => json::stringify(v),
                })
            };
            let label = truthy("label").or_else(|| truthy("id")).unwrap_or_else(|| "reference".into());
            out.push_str(&format!("[{label}](relay:{reference_kind}/{})", truthy("id").unwrap_or_default()));
            continue;
        }
        bail!("Cannot losslessly serialize inline type '{}' to RelayMark source.", if kind.is_empty() { "undefined" } else { kind });
    }
    Ok(out)
}
