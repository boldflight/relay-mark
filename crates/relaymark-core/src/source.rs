//! Canonical source: CommonMark (via comrak) plus authored directives import to
//! the strict rich AST; `relaymark-ast` fences are the exact identity- and
//! metadata-bearing interchange. Readable Markdown is a derived projection.

use comrak::nodes::{AstNode, ListType, NodeValue, TableAlignment};
use comrak::{Arena, Options};
use serde_json::{Value, json};

use crate::controls::{build_block_entity_reference_source, parse_control_source, parse_entity_reference_source};
use crate::error::{Error, Result, bail};
use crate::inline::{TEXT_MARKS, build_entity_reference_source, map_inline, parse_atom_source};
use crate::json::{self, Map};
use crate::jsre::js_regex;
use crate::links::{link_attributes, safe_image_source, safe_link_href};
use crate::mdurl;
use crate::registry::{directive_for_name, directive_for_type, directive_node_for_type};
use crate::snapshot::normalize_document;

/// Deterministic stable-once block identity for a source position.
pub fn block_id(namespace: &str, path: &[String]) -> String {
    let hash = json::sha256_hex(format!("{namespace}\0{}", path.join(".")).as_bytes());
    format!("b{}4{}8{}", &hash[..12], &hash[13..16], &hash[17..32])
}

fn block(namespace: &str, path: &[String], kind: &str, content: Vec<Value>, props: Option<Map>) -> Value {
    let mut node = Map::new();
    node.insert("id".into(), Value::String(block_id(namespace, path)));
    node.insert("type".into(), Value::String(kind.to_owned()));
    if let Some(props) = props {
        node.insert("props".into(), Value::Object(props));
    }
    node.insert("content".into(), Value::Array(content));
    Value::Object(node)
}

fn child_path(path: &[String], segment: impl ToString) -> Vec<String> {
    let mut next = path.to_vec();
    next.push(segment.to_string());
    next
}

fn longest_ticks(text: &str) -> usize {
    text.split(|c| c != '`').map(str::len).max().unwrap_or(0)
}

/// The exact interchange: one `relaymark-ast` fence holding the document JSON.
pub fn serialize_document(document: &Value) -> Result<String> {
    let normalized = normalize_document(document)?;
    let encoded = json::stringify(&normalized);
    let fence = "`".repeat(3.max(longest_ticks(&encoded) + 1));
    Ok(format!("{fence}relaymark-ast\n{encoded}\n{fence}\n"))
}

pub fn exact_interchange(source: &str) -> Option<Result<Value>> {
    let fence_length = source.bytes().take_while(|b| *b == b'`').count();
    if fence_length < 3 {
        return None;
    }
    let fence = &source[..fence_length];
    let body = source[fence_length..].strip_prefix("relaymark-ast\n")?;
    let closing = format!("\n{fence}");
    let mut offset = 0;
    while let Some(found) = body[offset..].find(&closing) {
        let at = offset + found;
        if body[at + closing.len()..].chars().all(json::is_js_space) {
            return Some(json::parse(&body[..at]));
        }
        offset = at + 1;
    }
    None
}

/// Source text to the canonical document AST. Markdown blocks receive stable
/// identities derived from `namespace` (the source itself when omitted).
pub fn parse_document(source: &str, namespace: Option<&str>) -> Result<Value> {
    let source = normalize_newlines(source);
    if let Some(exact) = exact_interchange(&source) {
        return normalize_document(&exact?);
    }
    let namespace = namespace.unwrap_or(&source).to_owned();
    let mut body = source.as_str();
    let mut frontmatter: Option<Map> = None;
    if let Some((fields, rest)) = frontmatter_split(body) {
        let mut map = Map::new();
        for line in fields.split('\n') {
            let Some(found) = js_regex!(r"^([^:]+):\s*(.*)$").captures(line) else { bail!("Invalid frontmatter") };
            let value = serde_json::from_str::<Value>(&found[2]).unwrap_or_else(|_| Value::String(found[2].to_owned()));
            map.insert(found[1].to_owned(), value);
        }
        frontmatter = Some(map);
        body = rest;
    }
    let mut blocks = source_blocks(body, &namespace, &[])?;
    if blocks.is_empty() {
        blocks.push(block(&namespace, &["0".into()], "paragraph", Vec::new(), None));
    }
    let mut document = Map::new();
    document.insert("type".into(), json!("relaymark.document"));
    if let Some(frontmatter) = frontmatter {
        document.insert("frontmatter".into(), Value::Object(frontmatter));
    }
    document.insert("blocks".into(), Value::Array(blocks));
    normalize_document(&Value::Object(document))
}

pub fn normalize_newlines(source: &str) -> String {
    if source.contains('\r') { source.replace("\r\n", "\n").replace('\r', "\n") } else { source.to_owned() }
}

/// `^---\n([\s\S]*?)\n---(?:\n|$)`: the fields and the remaining body.
fn frontmatter_split(source: &str) -> Option<(&str, &str)> {
    let rest = source.strip_prefix("---\n")?;
    let mut offset = 0;
    while let Some(found) = rest[offset..].find("\n---") {
        let at = offset + found;
        let after = &rest[at + 4..];
        if after.is_empty() {
            return Some((&rest[..at], after));
        }
        if let Some(body) = after.strip_prefix('\n') {
            return Some((&rest[..at], body));
        }
        offset = at + 1;
    }
    None
}

enum Segment {
    Markdown(String),
    Directive { name: String, attrs: Map, source: String },
    HistoricalQuestion { header: String, source: String },
    Control { control: String, attrs: Map, source: String },
}

struct OpenDirective {
    historical: bool,
    name: String,
    attrs: Map,
    header: String,
    body: Vec<String>,
    depth: usize,
}

fn bare_linked_task_line(line: &str) -> String {
    if js_regex!(r"^ {0,3}\[[ xX]\]\s+.*\[\[Task:").is_match(line) {
        let indent = line.len() - line.trim_start_matches(' ').len();
        format!("{}- {}", &line[..indent], &line[indent..])
    } else {
        line.to_owned()
    }
}

fn source_blocks(source: &str, namespace: &str, prefix: &[String]) -> Result<Vec<Value>> {
    let mut segments: Vec<Segment> = Vec::new();
    let mut plain: Vec<String> = Vec::new();
    let mut directive: Option<OpenDirective> = None;
    let mut fence: Option<String> = None;
    let flush = |segments: &mut Vec<Segment>, plain: &mut Vec<String>| {
        if !plain.is_empty() {
            segments.push(Segment::Markdown(plain.join("\n")));
            plain.clear();
        }
    };
    for line in source.split('\n') {
        let trimmed = json::js_trim(line);
        if fence.is_none() && directive.is_none() && (line.starts_with("    ") || line.starts_with('\t')) {
            plain.push(line.to_owned());
            continue;
        }
        if let Some(open) = &fence {
            match directive.as_mut() {
                Some(d) => d.body.push(line.to_owned()),
                None => plain.push(line.to_owned()),
            }
            let marker = open.chars().next().unwrap_or('`');
            let run = trimmed.chars().take_while(|c| *c == marker).count();
            if run >= open.chars().count() && trimmed[run * marker.len_utf8()..].chars().all(json::is_js_space) {
                fence = None;
            }
            continue;
        }
        if let Some(found) = js_regex!(r"^(`{3,}|~{3,})").find(trimmed) {
            fence = Some(found.as_str().to_owned());
            match directive.as_mut() {
                Some(d) => d.body.push(line.to_owned()),
                None => plain.push(line.to_owned()),
            }
            continue;
        }
        let header = js_regex!(r"^@([A-Z][A-Za-z0-9]*)(?:\((.*)\))?\s*\{\s*$").captures(trimmed);
        if let Some(open) = directive.as_mut() {
            if open.historical {
                if js_regex!(r"^<!--\s*/relay:question\s*-->$").is_match(trimmed) {
                    let open = directive.take().unwrap_or_else(|| unreachable!());
                    segments.push(Segment::HistoricalQuestion { header: open.header, source: open.body.join("\n") });
                } else {
                    open.body.push(line.to_owned());
                }
                continue;
            }
            if trimmed == "}" {
                open.depth -= 1;
                if open.depth == 0 {
                    let open = directive.take().unwrap_or_else(|| unreachable!());
                    segments.push(Segment::Directive { name: open.name, attrs: open.attrs, source: open.body.join("\n") });
                    continue;
                }
            } else if header.is_some() {
                open.depth += 1;
            }
            open.body.push(line.to_owned());
            continue;
        }
        if js_regex!(r"^<!--\s*relay:question\s+.*?\s*-->$").is_match(trimmed) {
            flush(&mut segments, &mut plain);
            directive =
                Some(OpenDirective { historical: true, name: String::new(), attrs: Map::new(), header: trimmed.to_owned(), body: Vec::new(), depth: 1 });
            continue;
        }
        if js_regex!(r"^<!--\s*/relay:question\s*-->$").is_match(trimmed) {
            bail!("Unexpected historical question closing");
        }
        if let Some(header) = header {
            flush(&mut segments, &mut plain);
            let attrs = parse_attributes(header.get(2).map_or("", |m| m.as_str()))?;
            directive = Some(OpenDirective { historical: false, name: header[1].to_owned(), attrs, header: trimmed.to_owned(), body: Vec::new(), depth: 1 });
            continue;
        }
        if let Some(found) = js_regex!(r"^@DataView\((.*)\)\s*$").captures(trimmed) {
            flush(&mut segments, &mut plain);
            segments.push(Segment::Directive { name: "DataView".into(), attrs: parse_attributes(&found[1])?, source: String::new() });
            continue;
        }
        if let Some((control, attrs, source)) = parse_control_source(trimmed) {
            flush(&mut segments, &mut plain);
            segments.push(Segment::Control { control, attrs, source });
            continue;
        }
        if trimmed == "}" {
            bail!("Unexpected directive closing");
        }
        plain.push(bare_linked_task_line(line));
    }
    if directive.is_some() {
        bail!("Missing directive closing");
    }
    flush(&mut segments, &mut plain);
    let mut blocks = Vec::new();
    for (index, segment) in segments.into_iter().enumerate() {
        let path = child_path(prefix, index);
        match segment {
            Segment::Markdown(text) => blocks.extend(markdown_blocks(&text, namespace, &path)?),
            Segment::HistoricalQuestion { header, source } => blocks.push(historical_question(&header, &source, namespace, &path)?),
            Segment::Control { control, attrs, source } => {
                let mut props = Map::new();
                props.insert("control".into(), Value::String(control));
                props.extend(attrs);
                props.insert("source".into(), Value::String(source));
                blocks.push(block(namespace, &path, "relay.paper_control", Vec::new(), Some(props)));
            }
            Segment::Directive { name, attrs, source } => blocks.push(directive_block(&name, attrs, &source, namespace, &path)?),
        }
    }
    Ok(blocks)
}

fn directive_block(name: &str, attrs: Map, source: &str, namespace: &str, path: &[String]) -> Result<Value> {
    let Some(spec) = directive_for_name(name) else { bail!("Unknown directive") };
    let mut props = attrs.clone();
    for (key, attribute) in spec.attributes().into_iter().flatten() {
        if !props.contains_key(key)
            && let Some(default) = attribute.get("default")
        {
            props.insert(key.clone(), default.clone());
        }
    }
    let mut content = source_blocks(source, namespace, &child_path(path, 0))?;
    let ast_type = spec.ast_type.as_str();
    if ast_type == "relay.callout" && content.is_empty() {
        content.push(block(namespace, &child_path(&child_path(path, 0), 0), "paragraph", Vec::new(), None));
    }
    if ast_type == "relay.callout"
        && let Some(title) = props.shift_remove("title")
    {
        let title = match title {
            Value::String(text) => text,
            other => js_string(&other),
        };
        content.insert(0, block(namespace, &child_path(path, 1), "relay.callout_title", parse_inline(&title)?, None));
    }
    if ast_type == "relay.form_option" || ast_type == "relay.agent_suggestion" {
        if content.len() > 1 || content.first().and_then(|c| c["type"].as_str()) != Some("paragraph") {
            bail!("Inline directive requires a paragraph");
        }
        content = content[0]["content"].as_array().cloned().unwrap_or_default();
    }
    if ast_type == "relay.entity_reference" {
        let mut input = attrs;
        if let Some(id) = input.get("id").and_then(Value::as_str).filter(|id| !id.starts_with("entity:")).map(|id| format!("entity:{id}")) {
            input.insert("id".into(), Value::String(id));
        }
        let body = source.strip_prefix("  ").unwrap_or(source);
        let reference_source = build_block_entity_reference_source(&input, body)?;
        let parsed = parse_entity_reference_source(&reference_source).ok_or_else(|| Error::new("Invalid block reference source"))?;
        props.insert("id".into(), Value::String(parsed.id));
        props.insert("label".into(), Value::String(parsed.label));
        props.insert("projection".into(), Value::String(parsed.projection));
        props.insert("source".into(), Value::String(reference_source));
        content = Vec::new();
    }
    Ok(block(namespace, path, ast_type, content, Some(props)))
}

/// `String(value)` for an attribute value.
fn js_string(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        Value::Null => "null".into(),
        Value::Array(items) => items.iter().map(|item| if item.is_null() { String::new() } else { js_string(item) }).collect::<Vec<_>>().join(","),
        Value::Object(_) => "[object Object]".into(),
        other => json::stringify(other),
    }
}

// ---- Authored attribute lists: `key: value, ...` ----

pub fn parse_attributes(raw: &str) -> Result<Map> {
    let text = json::js_trim(raw);
    let mut attributes = Map::new();
    if text.is_empty() {
        return Ok(attributes);
    }
    for part in split_top_level(text, ',') {
        let trimmed = json::js_trim(part);
        if trimmed.is_empty() {
            continue;
        }
        let Some(colon) = find_top_level_colon(trimmed) else { bail!("Invalid attribute '{trimmed}'") };
        let key = json::js_trim(&trimmed[..colon]);
        let value = json::js_trim(&trimmed[colon + 1..]);
        if !js_regex!(r"^[A-Za-z_][A-Za-z0-9_]*$").is_match(key) {
            bail!("Invalid attribute name '{key}'");
        }
        if attributes.contains_key(key) {
            bail!("Duplicate authored attribute");
        }
        attributes.insert(key.to_owned(), parse_attribute_value(value)?);
    }
    Ok(attributes)
}

fn parse_attribute_value(value: &str) -> Result<Value> {
    match value {
        "true" => return Ok(Value::Bool(true)),
        "false" => return Ok(Value::Bool(false)),
        "null" => return Ok(Value::Null),
        _ => {}
    }
    if js_regex!(r"^-?\d+(\.\d+)?$").is_match(value) {
        let number: f64 = value.parse().map_err(|_| Error::new("Invalid number"))?;
        return Ok(js_number(number));
    }
    if value.len() >= 2 && value.starts_with('"') && value.ends_with('"') {
        return json::parse(value);
    }
    if value.len() >= 2 && value.starts_with('[') && value.ends_with(']') {
        let inner = json::js_trim(&value[1..value.len() - 1]);
        if inner.is_empty() {
            return Ok(Value::Array(Vec::new()));
        }
        return split_top_level(inner, ',').into_iter().map(|item| parse_attribute_value(json::js_trim(item))).collect::<Result<Vec<_>>>().map(Value::Array);
    }
    if value.len() >= 2 && value.starts_with('{') && value.ends_with('}') {
        let inner = json::js_trim(&value[1..value.len() - 1]);
        let mut object = Map::new();
        if !inner.is_empty() {
            for part in split_top_level(inner, ',') {
                let Some(colon) = find_top_level_colon(part) else { bail!("Invalid object entry '{part}'") };
                let raw_key = json::js_trim(&part[..colon]);
                let key = raw_key.strip_prefix('"').unwrap_or(raw_key);
                let key = key.strip_suffix('"').unwrap_or(key);
                if object.contains_key(key) {
                    bail!("Duplicate authored attribute");
                }
                object.insert(key.to_owned(), parse_attribute_value(json::js_trim(&part[colon + 1..]))?);
            }
        }
        return Ok(Value::Object(object));
    }
    bail!("Unsupported attribute value '{value}'")
}

/// A JavaScript number as JSON: integral values become integers.
pub fn js_number(number: f64) -> Value {
    if number.fract() == 0.0 && number.abs() < 9.007_199_254_740_992e15 {
        Value::from(number as i64)
    } else {
        serde_json::Number::from_f64(number).map_or(Value::Null, Value::Number)
    }
}

fn scan_top_level(text: &str, mut visit: impl FnMut(usize, char, i64) -> bool) {
    let (mut depth, mut quote, mut escape) = (0i64, false, false);
    for (index, c) in text.char_indices() {
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
        if matches!(c, '[' | '{' | '(') {
            depth += 1;
        }
        if matches!(c, ']' | '}' | ')') {
            depth -= 1;
        }
        if !visit(index, c, depth) {
            return;
        }
    }
}

fn split_top_level(text: &str, delimiter: char) -> Vec<&str> {
    let mut parts = Vec::new();
    let mut start = 0;
    scan_top_level(text, |index, c, depth| {
        if c == delimiter && depth == 0 {
            parts.push(&text[start..index]);
            start = index + 1;
        }
        true
    });
    parts.push(&text[start..]);
    parts
}

fn find_top_level_colon(text: &str) -> Option<usize> {
    let mut found = None;
    scan_top_level(text, |index, c, depth| {
        if c == ':' && depth == 0 {
            found = Some(index);
            return false;
        }
        true
    });
    found
}

// ---- CommonMark through comrak ----

fn comrak_options() -> Options<'static> {
    let mut options = Options::default();
    options.extension.table = true;
    options.extension.strikethrough = true;
    options.extension.wikilinks_title_after_pipe = true;
    options
}

/// comrak 0.56 positions a wiki link that spans lines as if it were one
/// line, and every later inline of its paragraph after it. Correct them
/// from the source: the link ends at the first `]]` after its start.
fn fix_wikilink_positions<'a>(root: &'a AstNode<'a>, lines: &Lines<'_>) {
    for paragraph in root.descendants().filter(|n| matches!(value_of(n), NodeValue::Paragraph | NodeValue::Heading(_) | NodeValue::TableCell)) {
        // (reported line, column of reported end, line shift, column shift)
        let mut shifts: Vec<(usize, usize, usize, isize)> = Vec::new();
        for node in paragraph.descendants().skip(1) {
            let mut data = node.data.borrow_mut();
            let sourcepos = &mut data.sourcepos;
            for (line, column, line_shift, column_shift) in &shifts {
                for point in [&mut sourcepos.start, &mut sourcepos.end] {
                    if point.line == *line && point.column > *column {
                        point.column = point.column.saturating_add_signed(*column_shift);
                        point.line += line_shift;
                    } else if point.line > *line {
                        point.line += line_shift;
                    }
                }
            }
            if !matches!(data.value, NodeValue::WikiLink(_)) {
                continue;
            }
            let Some(start) = lines.offset(data.sourcepos.start.line, data.sourcepos.start.column) else { continue };
            let Some(close) = lines.source.get(start + 2..).and_then(|rest| rest.find("]]")) else { continue };
            if !lines.source[start..start + 2 + close].contains('\n') {
                continue;
            }
            let (line, column) = lines.position(start + 2 + close + 1);
            let reported = data.sourcepos.end;
            shifts.push((reported.line, reported.column, line - reported.line, column as isize - reported.column as isize));
            data.sourcepos.end.line = line;
            data.sourcepos.end.column = column;
        }
    }
}

/// Byte offsets of each source line, for raw slices from comrak positions.
struct Lines<'s> {
    source: &'s str,
    starts: Vec<usize>,
}

impl<'s> Lines<'s> {
    fn new(source: &'s str) -> Self {
        let mut starts = vec![0];
        starts.extend(source.match_indices('\n').map(|(i, _)| i + 1));
        Self { source, starts }
    }

    fn offset(&self, line: usize, column: usize) -> Option<usize> {
        let start = *self.starts.get(line.checked_sub(1)?)?;
        let offset = start + column.checked_sub(1)?;
        (offset <= self.source.len()).then_some(offset)
    }

    /// Raw source covered by an inclusive start/end position.
    fn slice(&self, node: &AstNode<'_>) -> Option<&'s str> {
        let pos = node.data.borrow().sourcepos;
        let start = self.offset(pos.start.line, pos.start.column)?;
        let end = self.offset(pos.end.line, pos.end.column)? + 1;
        self.source.get(start..end.min(self.source.len()))
    }

    /// The 1-based line and column of a byte offset.
    fn position(&self, offset: usize) -> (usize, usize) {
        let line = self.starts.partition_point(|start| *start <= offset);
        (line, offset - self.starts[line - 1] + 1)
    }

    fn line(&self, number: usize) -> &'s str {
        let start = self.starts.get(number.wrapping_sub(1)).copied().unwrap_or(self.source.len());
        let end = self.starts.get(number).map_or(self.source.len(), |next| next - 1);
        self.source.get(start..end).unwrap_or("")
    }
}

struct Converter<'s> {
    namespace: &'s str,
    lines: Lines<'s>,
}

fn value_of<'a>(node: &'a AstNode<'a>) -> NodeValue {
    node.data.borrow().value.clone()
}

fn markdown_blocks(source: &str, namespace: &str, prefix: &[String]) -> Result<Vec<Value>> {
    // markdown-it replaces NUL before parsing, and never reads a final
    // unterminated line holding only spaces and tabs (its line scanner skips
    // the end check while still indenting).
    let source = source.replace('\0', "\u{fffd}");
    let kept = source.rfind('\n').map_or(0, |at| at + 1);
    let mut source = if source[kept..].bytes().all(|b| b == b' ' || b == b'\t') { source[..kept].to_owned() } else { source };
    // Each repair pass fixes at least one construct. The bound only limits
    // pathological input (one pass per unmatched backtick run of a paragraph);
    // past it the remaining repairs are skipped.
    const PASSES: usize = 1024;
    for pass in 1.. {
        let arena = Arena::new();
        let root = comrak::parse_document(&arena, &source, &comrak_options());
        let lines = Lines::new(&source);
        fix_wikilink_positions(root, &lines);
        let repairs = if pass < PASSES { repairs(root, &lines) } else { Vec::new() };
        if repairs.is_empty() {
            let converter = Converter { namespace, lines };
            return converter.sequence(root, prefix);
        }
        source = apply_repairs(&source, &lines, repairs);
    }
    unreachable!()
}

/// A source edit after which comrak parses what markdown-it (the reference
/// runtime's parser) parses. Repairs never change text that reaches the
/// document; they only move block and link boundaries.
enum Repair {
    /// Insert an empty line (keeping this container prefix) before this
    /// line. markdown-it reads link reference definitions as a block of their
    /// own, so whatever follows them starts a new block; comrak strips them
    /// from the start of a paragraph that continues (and then misplaces the
    /// source positions of that paragraph's inlines).
    Break(usize, String),
    /// Make this whitespace-only line empty. CommonMark (and markdown-it) end
    /// a list item that starts with a blank line at a second blank line;
    /// comrak 0.56 does not count a whitespace-only line as that blank line.
    Blank(usize),
    /// Insert a backslash at this byte offset so a link, image or autolink
    /// opener is literal text: markdown-it refuses destinations that fail
    /// `validateLink` and then reads the opener as text.
    Escape(usize),
}

/// The repairs for one parse, most structural first: definition breaks,
/// then one blank-start list item (fixing it can change every later block),
/// and only then escapes, whose offsets need a final block structure.
fn repairs<'a>(root: &'a AstNode<'a>, lines: &Lines<'_>) -> Vec<Repair> {
    let breaks: Vec<Repair> = root.descendants().filter_map(|node| definition_break(node, lines)).collect();
    if !breaks.is_empty() {
        return breaks;
    }
    if let Some(line) = root.descendants().find_map(|node| blank_start_item(node, lines)) {
        return vec![Repair::Blank(line)];
    }
    let tables: Vec<Repair> = root.descendants().filter_map(|node| pipeless_table(node, lines)).collect();
    if !tables.is_empty() {
        return tables;
    }
    let mut escapes = refused_definitions(root, lines);
    escapes.extend(root.descendants().filter_map(|node| unmatched_backticks(node, lines)).flatten());
    escapes.extend(root.descendants().filter_map(|node| {
        let opener = match value_of(node) {
            NodeValue::Link(link) if !mdurl::validate_link(&mdurl::normalize_link(&link.url)) => 0,
            NodeValue::Image(link) if !mdurl::validate_link(&mdurl::normalize_link(&link.url)) => 1,
            _ => return None,
        };
        let pos = node.data.borrow().sourcepos;
        lines.offset(pos.start.line, pos.start.column).map(|at| Repair::Escape(at + opener))
    }));
    escapes
}

/// markdown-it needs a `|` in a table's header line; without one the
/// delimiter row is paragraph text, so escape its first character.
fn pipeless_table<'a>(node: &'a AstNode<'a>, lines: &Lines<'_>) -> Option<Repair> {
    if !matches!(value_of(node), NodeValue::Table(_)) {
        return None;
    }
    let pos = node.data.borrow().sourcepos;
    let header = lines.line(pos.start.line).get(pos.start.column.saturating_sub(1)..).unwrap_or("");
    if header.contains('|') {
        return None;
    }
    let delimiter = lines.offset(pos.start.line + 1, pos.start.column)?;
    let indent = lines.source[delimiter..].bytes().take_while(|b| *b == b' ' || *b == b'\t').count();
    Some(Repair::Escape(delimiter + indent))
}

/// After an unmatched backtick run, comrak 0.56 matches only the next code
/// span of a paragraph and leaves later ones literal; markdown-it (and
/// CommonMark) match them all. Escaping the first unmatched run of an inline
/// container (it stays literal text) avoids that, one run per pass.
fn unmatched_backticks<'a>(node: &'a AstNode<'a>, lines: &Lines<'_>) -> Option<Vec<Repair>> {
    if !matches!(value_of(node), NodeValue::Paragraph | NodeValue::Heading(_) | NodeValue::TableCell) {
        return None;
    }
    for child in node.descendants() {
        if !matches!(value_of(child), NodeValue::Text(ref text) if text.contains('`')) {
            continue;
        }
        // Backslashes are literal in an autolink's raw destination, and an
        // image's raw label is its alt text.
        let raw_context = child.ancestors().any(|a| match value_of(a) {
            NodeValue::Image(_) | NodeValue::WikiLink(_) => true,
            NodeValue::Link(_) => lines.slice(a).is_some_and(|raw| raw.starts_with('<')),
            _ => false,
        });
        if raw_context {
            continue;
        }
        let pos = child.data.borrow().sourcepos;
        let start = lines.offset(pos.start.line, pos.start.column)?;
        let end = (lines.offset(pos.end.line, pos.end.column)? + 1).min(lines.source.len());
        let raw = lines.source.as_bytes();
        let mut at = start;
        while at < end {
            // markdown-it's reference rule reads `[[` to `]]` as one token.
            if raw[at..end].starts_with(b"[[")
                && let Some(close) = lines.source[at + 2..].find("]]")
            {
                at += close + 4;
                continue;
            }
            if raw[at] == b'`' {
                let backslashes = raw[..at].iter().rev().take_while(|b| **b == b'\\').count();
                if backslashes % 2 == 0 {
                    let run = raw[at..end].iter().take_while(|b| **b == b'`').count();
                    return Some((at..at + run).map(Repair::Escape).collect());
                }
            }
            at += 1;
        }
    }
    None
}

/// The offset of the `[` opening a link reference definition on this line
/// whose destination markdown-it refuses.
fn refused_definition(line: &str) -> Option<usize> {
    let pattern =
        js_regex!(r"^(?:[ \t]*>)*[ \t]*(?:(?:[-+*]|\d{1,9}[.)])[ \t]+)?[ ]{0,3}(\[)(?:[^\]\\]|\\.)+\]:[ \t]*<?[ \t]*(?i:javascript|vbscript|file|data):");
    let found = pattern.captures(line)?.get(1)?;
    let destination = line[found.end()..].split_once("]:").map_or("", |(_, rest)| rest).trim_start_matches([' ', '\t', '<']);
    (!mdurl::validate_link(&mdurl::normalize_link(destination))).then_some(found.start())
}

/// Link reference definitions whose destination markdown-it refuses
/// (`validateLink`): markdown-it keeps their line as paragraph text, comrak
/// consumes it. Only a destination on the label's line is recognized.
fn refused_definitions<'a>(root: &'a AstNode<'a>, lines: &Lines<'_>) -> Vec<Repair> {
    if !lines.source.contains("]:") {
        return Vec::new();
    }
    let candidates: Vec<(usize, usize)> = (1..=lines.starts.len()).filter_map(|number| Some((number, refused_definition(lines.line(number))?))).collect();
    if candidates.is_empty() {
        return Vec::new();
    }
    let mut covered = vec![false; lines.starts.len() + 2];
    for node in root.descendants() {
        if matches!(
            value_of(node),
            NodeValue::Paragraph | NodeValue::Heading(_) | NodeValue::CodeBlock(_) | NodeValue::HtmlBlock(_) | NodeValue::Table(_) | NodeValue::ThematicBreak
        ) {
            let pos = node.data.borrow().sourcepos;
            for line in pos.start.line..=pos.end.line.min(covered.len() - 1) {
                covered[line] = true;
            }
        }
    }
    candidates.into_iter().filter(|(number, _)| !covered[*number]).map(|(number, column)| Repair::Escape(lines.starts[number - 1] + column)).collect()
}

/// For a paragraph that begins with link reference definitions and then
/// continues: where its remaining content starts.
fn definition_break<'a>(node: &'a AstNode<'a>, lines: &Lines<'_>) -> Option<Repair> {
    if !matches!(value_of(node), NodeValue::Paragraph) {
        return None;
    }
    let pos = node.data.borrow().sourcepos;
    let column = pos.start.column.checked_sub(1)?;
    let content = |number: usize| -> &str {
        let line = lines.line(number);
        match line.get(..column) {
            Some(_) if number == pos.start.line => &line[column..],
            Some(prefix) if prefix.bytes().all(|b| matches!(b, b' ' | b'\t' | b'>')) => &line[column..],
            _ => line,
        }
    };
    if !content(pos.start.line).starts_with('[') {
        return None;
    }
    let span = pos.end.line - pos.start.line + 1;
    if !(0..span).any(|k| content(pos.start.line + k).contains("]:")) {
        return None;
    }
    // The longest prefix of the paragraph's lines that parses to nothing (only
    // definitions). Definitions may span lines, so look a few lines past the
    // last such prefix before stopping.
    let mut defined = 0;
    let mut text = String::new();
    for k in 1..span {
        if k > defined + 8 {
            break;
        }
        text.push_str(content(pos.start.line + k - 1));
        text.push('\n');
        let arena = Arena::new();
        if comrak::parse_document(&arena, &text, &comrak_options()).first_child().is_none() {
            defined = k;
        }
    }
    // markdown-it's definitions end at the first one it refuses.
    defined = (0..defined).find(|k| refused_definition(content(pos.start.line + k)).is_some()).unwrap_or(defined);
    if defined == 0 {
        return None;
    }
    let line = pos.start.line + defined;
    let prefix = lines.line(line).get(..column).filter(|p| p.bytes().all(|b| matches!(b, b' ' | b'\t' | b'>'))).unwrap_or("");
    Some(Repair::Break(line, prefix.trim_end().to_owned()))
}

/// A list item whose marker line is empty, followed by a whitespace-only line
/// and then content that comrak wrongly keeps inside the item.
fn blank_start_item<'a>(node: &'a AstNode<'a>, lines: &Lines<'_>) -> Option<usize> {
    if !matches!(value_of(node), NodeValue::Item(_) | NodeValue::TaskItem(_)) {
        return None;
    }
    let pos = node.data.borrow().sourcepos;
    let column = pos.start.column.checked_sub(1)?;
    let next = pos.start.line + 1;
    let first_child_line = node.first_child()?.data.borrow().sourcepos.start.line;
    let blank = |text: &str| text.bytes().all(|b| b == b' ' || b == b'\t');
    let marker_only = lines
        .line(pos.start.line)
        .get(column..)
        .is_some_and(|rest| blank(rest.trim_start_matches(|c: char| c.is_ascii_digit() || matches!(c, '-' | '+' | '*' | '.' | ')'))));
    let whitespace_line = lines.line(next).get(column..).is_some_and(|rest| !rest.is_empty() && blank(rest));
    (marker_only && first_child_line > next && whitespace_line).then_some(next)
}

fn apply_repairs(source: &str, lines: &Lines<'_>, repairs: Vec<Repair>) -> String {
    let mut edits: Vec<(usize, usize, String)> = repairs
        .into_iter()
        .map(|repair| match repair {
            Repair::Break(line, prefix) => {
                let start = lines.starts[line - 1];
                (start, start, format!("{prefix}\n"))
            }
            Repair::Blank(line) => {
                let start = lines.starts[line - 1];
                let text = lines.line(line);
                (start + text.trim_end_matches([' ', '\t']).len(), start + text.len(), String::new())
            }
            Repair::Escape(at) => (at, at, "\\".to_owned()),
        })
        .collect();
    edits.sort_by_key(|edit| std::cmp::Reverse(edit.0));
    edits.dedup_by_key(|edit| edit.0);
    let mut out = source.to_owned();
    for (start, end, text) in edits {
        out.replace_range(start..end, &text);
    }
    out
}

impl Converter<'_> {
    fn sequence<'a>(&self, parent: &'a AstNode<'a>, path: &[String]) -> Result<Vec<Value>> {
        let mut nodes: Vec<Value> = Vec::new();
        for child in parent.children() {
            let p = child_path(path, nodes.len());
            let converted = self.block(child, &p)?;
            nodes.extend(converted.into_iter().map(|value| if value["type"] == "paragraph" { historical_media(value) } else { value }));
        }
        Ok(nodes)
    }

    fn block<'a>(&self, node: &'a AstNode<'a>, p: &[String]) -> Result<Vec<Value>> {
        let ns = self.namespace;
        Ok(match value_of(node) {
            NodeValue::Paragraph => self.inline_media_blocks(node, p, "paragraph", None)?,
            NodeValue::Heading(heading) => {
                let (runs, heading_id) = self.heading_runs(node)?;
                let props = json!({"level": heading.level, "headingId": heading_id});
                self.media_blocks_from_runs(runs, p, "heading", props.as_object().cloned())?
            }
            NodeValue::BlockQuote => vec![block(ns, p, "quote", self.sequence(node, p)?, None)],
            NodeValue::List(list) => vec![self.list(node, &list, p)?],
            NodeValue::CodeBlock(code) => {
                if code.info.starts_with("relaymark-ast") {
                    bail!("Mixed exact source");
                }
                let content = if code.literal.is_empty() { Vec::new() } else { vec![json!({"type": "text", "text": code.literal})] };
                let language = if code.fenced { self.fence_info(node, code.fence_char) } else { String::new() };
                let language = if language.is_empty() { Value::Null } else { Value::String(language) };
                vec![block(ns, p, "code", content, Some(Map::from_iter([("language".into(), language)])))]
            }
            NodeValue::HtmlBlock(html) => vec![block(ns, p, "paragraph", vec![json!({"type": "text", "text": html.literal})], None)],
            NodeValue::ThematicBreak => vec![block(ns, p, "horizontal_rule", Vec::new(), None)],
            NodeValue::Table(table) => vec![self.table(node, &table.alignments, p)?],
            other => bail!("Unsupported CommonMark block {other:?}"),
        })
    }

    /// The raw rest of an opening fence line, as markdown-it keeps it (not
    /// trimmed, not unescaped): the stored `language`.
    fn fence_info<'a>(&self, node: &'a AstNode<'a>, fence_char: u8) -> String {
        let pos = node.data.borrow().sourcepos;
        let line = self.lines.line(pos.start.line);
        let rest = line.get(pos.start.column.saturating_sub(1)..).unwrap_or("");
        rest.trim_start_matches([' ', '\t']).trim_start_matches(char::from(fence_char)).to_owned()
    }

    fn list<'a>(&self, node: &'a AstNode<'a>, list: &comrak::nodes::NodeList, p: &[String]) -> Result<Value> {
        let mut items = Vec::new();
        for (index, item) in node.children().enumerate() {
            let item_path = child_path(p, index);
            let mut content = self.sequence(item, &item_path)?;
            if content.first().map(|c| &c["type"]) != Some(&json!("paragraph")) {
                content.insert(0, block(self.namespace, &child_path(&item_path, "leading-paragraph"), "paragraph", Vec::new(), None));
            }
            items.push(block(self.namespace, &item_path, "list_item", content, None));
        }
        let mut task = false;
        for item in &mut items {
            let marker = item["content"][0]["content"]
                .get(0)
                .filter(|node| node["type"] == "text")
                .and_then(|node| node["text"].as_str())
                .and_then(|text| js_regex!(r"^\[([ xX])\]\s+").captures(text).map(|m| (m[1].to_lowercase() == "x", m[0].len())));
            if let Some((checked, length)) = marker {
                task = true;
                item["type"] = json!("task_item");
                item["props"] = json!({"checked": checked, "entityId": null});
                let first = &mut item["content"][0]["content"];
                let text = first[0]["text"].as_str().unwrap_or_default()[length..].to_owned();
                if text.is_empty() {
                    if let Some(nodes) = first.as_array_mut() {
                        nodes.remove(0);
                    }
                } else {
                    first[0]["text"] = Value::String(text);
                }
            }
        }
        if task {
            for item in &mut items {
                item["type"] = json!("task_item");
                if item.get("props").is_none() {
                    let object = item.as_object_mut().unwrap_or_else(|| unreachable!());
                    let content = object.shift_remove("content").unwrap_or(Value::Null);
                    object.insert("props".into(), json!({"checked": false, "entityId": null}));
                    object.insert("content".into(), content);
                }
                linked_task(item);
            }
            return Ok(block(self.namespace, p, "task_list", items, None));
        }
        let props = match list.list_type {
            // markdown-it omits `start` for 1 and the reference reads `start || 1`.
            ListType::Ordered => Map::from_iter([("kind".into(), json!("ordered")), ("start".into(), json!(list.start.max(1)))]),
            ListType::Bullet => Map::from_iter([("kind".into(), json!("bullet"))]),
        };
        Ok(block(self.namespace, p, "list", items, Some(props)))
    }

    fn table<'a>(&self, node: &'a AstNode<'a>, alignments: &[TableAlignment], p: &[String]) -> Result<Value> {
        let mut rows = Vec::new();
        for (r, row) in node.children().enumerate() {
            let header = matches!(value_of(row), NodeValue::TableRow(true));
            let row_path = child_path(p, r);
            let mut cells = Vec::new();
            for (c, cell) in row.children().enumerate() {
                let cell_path = child_path(&row_path, c);
                let align = match alignments.get(c) {
                    Some(TableAlignment::Left) => json!("left"),
                    Some(TableAlignment::Center) => json!("center"),
                    Some(TableAlignment::Right) => json!("right"),
                    _ => Value::Null,
                };
                // markdown-it trims each cell with JavaScript's whitespace set.
                let mut runs = self.runs(cell, &[])?;
                trim_runs(&mut runs);
                let content = self.media_blocks_from_runs(runs, &child_path(&cell_path, 0), "paragraph", None)?;
                let props = json!({"header": header, "colspan": 1, "rowspan": 1, "colwidth": null, "align": align});
                cells.push(block(self.namespace, &cell_path, "table_cell", content, props.as_object().cloned()));
            }
            rows.push(block(self.namespace, &row_path, "table_row", cells, None));
        }
        Ok(block(self.namespace, p, "table", rows, None))
    }

    /// Heading runs, without a trailing unmarked `{#id}` identity marker.
    fn heading_runs<'a>(&self, node: &'a AstNode<'a>) -> Result<(Vec<Run>, Value)> {
        let mut runs = self.runs(node, &[])?;
        let marker_pattern = js_regex!(r"\s+\{#([A-Za-z0-9][A-Za-z0-9_-]{0,127})\}$");
        if let Some(Run::Text { text, marks, end, .. }) = runs.last()
            && marks.is_empty()
            && let Some((line, column)) = *end
            && let Some(raw) = self.lines.line(line).get(..column)
            && let (Some(raw_marker), Some(marker)) = (marker_pattern.captures(raw), marker_pattern.captures(text))
            && raw_marker[1] == marker[1]
        {
            let id = marker[1].to_owned();
            let kept = text[..text.len() - marker[0].len()].to_owned();
            if kept.is_empty() {
                runs.pop();
            } else if let Some(Run::Text { text, .. }) = runs.last_mut() {
                *text = kept;
            }
            return Ok((runs, Value::String(id)));
        }
        Ok((runs, Value::Null))
    }

    fn inline_media_blocks<'a>(&self, node: &'a AstNode<'a>, path: &[String], kind: &str, props: Option<Map>) -> Result<Vec<Value>> {
        let runs = self.runs(node, &[])?;
        self.media_blocks_from_runs(runs, path, kind, props)
    }

    /// One finite source boundary repair: top-level images become image blocks
    /// between the surrounding text blocks.
    fn media_blocks_from_runs(&self, runs: Vec<Run>, path: &[String], kind: &str, props: Option<Map>) -> Result<Vec<Value>> {
        if !runs.iter().any(|run| matches!(run, Run::Image { .. })) {
            return Ok(vec![block(self.namespace, path, kind, inline(runs)?, props)]);
        }
        let mut output: Vec<Value> = Vec::new();
        let mut pending: Vec<Run> = Vec::new();
        let next_path = |output: &Vec<Value>| if output.is_empty() { path.to_vec() } else { child_path(path, output.len()) };
        for run in runs {
            match run {
                Run::Image { src, alt, title, nested } => {
                    if nested {
                        bail!("Marked or linked inline image requires explicit authored media semantics");
                    }
                    if !pending.is_empty() {
                        let content = inline(std::mem::take(&mut pending))?;
                        output.push(block(self.namespace, &next_path(&output), kind, content, props.clone()));
                    }
                    let image_props = json!({"src": src, "alt": alt, "title": title});
                    output.push(block(self.namespace, &next_path(&output), "image", Vec::new(), image_props.as_object().cloned()));
                }
                other => pending.push(other),
            }
        }
        if !pending.is_empty() {
            let content = inline(pending)?;
            output.push(block(self.namespace, &next_path(&output), kind, content, props));
        }
        Ok(output)
    }

    /// Flatten comrak inlines into runs carrying their enclosing marks, with
    /// the reference runtime's literal treatment of unsafe links and images.
    fn runs<'a>(&self, parent: &'a AstNode<'a>, marks: &[Value]) -> Result<Vec<Run>> {
        let mut runs: Vec<Run> = Vec::new();
        for node in parent.children() {
            match value_of(node) {
                NodeValue::Text(text) => {
                    let pos = node.data.borrow().sourcepos;
                    let (text, spans) = self.read_text(node, &text);
                    push_spans(&mut runs, &text, marks, spans, Some((pos.end.line, pos.end.column)));
                }
                NodeValue::SoftBreak => {
                    self.restore_trailing_whitespace(node, &mut runs, marks);
                    runs.push(Run::Text { text: "\n".into(), marks: marks.to_vec(), verbatim: vec![(1, false)], end: None, separate: true });
                }
                NodeValue::LineBreak => {
                    self.restore_trailing_whitespace(node, &mut runs, marks);
                    runs.push(Run::Atom(json!({"type": "hard_break"})));
                }
                NodeValue::Code(code) => {
                    let literal = match self.raw_inline(node) {
                        Some(raw) => {
                            let ticks = raw.bytes().take_while(|b| *b == b'`').count();
                            let inner = raw.get(ticks..raw.len().saturating_sub(ticks)).unwrap_or("").replace('\n', " ");
                            match inner.strip_prefix(' ').and_then(|i| i.strip_suffix(' ')) {
                                Some(stripped) if !inner.bytes().all(|b| b == b' ') => stripped.to_owned(),
                                _ => inner,
                            }
                        }
                        None => code.literal.clone(),
                    };
                    runs.push(Run::Code(literal));
                }
                NodeValue::HtmlInline(html) => runs.push(Run::Html { text: self.raw_inline(node).unwrap_or(html), marks: marks.to_vec() }),
                NodeValue::Emph => runs.extend(self.runs(node, &with_mark(marks, json!({"type": "italic"})))?),
                NodeValue::Strong => runs.extend(self.runs(node, &with_mark(marks, json!({"type": "bold"})))?),
                // markdown-it strikes only `~~` pairs; a single-tilde pair stays literal.
                NodeValue::Strikethrough if self.single_tilde(node) => {
                    push_text(&mut runs, "~", marks, false, None);
                    runs.extend(self.runs(node, marks)?);
                    push_text(&mut runs, "~", marks, false, None);
                }
                NodeValue::Strikethrough => runs.extend(self.runs(node, &with_mark(marks, json!({"type": "strike"})))?),
                NodeValue::Link(link) => {
                    let href = mdurl::normalize_link(&link.url);
                    // An autolink's text is markdown-it's readable form of its raw destination.
                    let raw = self.lines.slice(node).unwrap_or_default();
                    let autolink = raw.strip_prefix('<').and_then(|r| r.strip_suffix('>')).map(mdurl::normalize_link_text);
                    let label = |marks: &[Value]| -> Result<Vec<Run>> {
                        match &autolink {
                            Some(text) => Ok(vec![Run::Text {
                                text: text.clone(),
                                marks: marks.to_vec(),
                                verbatim: vec![(text.len(), false)],
                                end: None,
                                separate: false,
                            }]),
                            None => self.runs(node, marks),
                        }
                    };
                    if safe_link_href(&href) {
                        let title = if link.title.is_empty() { Value::Null } else { Value::String(link.title.clone()) };
                        let attrs = link_attributes(&href, Some(&json!({"title": title})))?;
                        for run in label(&with_mark(marks, json!({"type": "link", "attrs": attrs})))? {
                            match run {
                                Run::Text { text, marks, verbatim, end, separate: false } if verbatim.len() == 1 => {
                                    push_text(&mut runs, &text, &marks, verbatim[0].1, end)
                                }
                                other => runs.push(other),
                            }
                        }
                    } else {
                        let label = inline_markdown(&inline(label(&[])?)?)?;
                        let pos = node.data.borrow().sourcepos;
                        push_text(&mut runs, &format!("[{label}]({href})"), marks, false, Some((pos.end.line, pos.end.column)));
                    }
                }
                NodeValue::Image(link) => {
                    let src = mdurl::normalize_link(&link.url);
                    let alt = self.image_label(node);
                    if safe_image_source(&src) {
                        let title = if link.title.is_empty() { Value::Null } else { Value::String(link.title.clone()) };
                        runs.push(Run::Image { src, alt, title, nested: !marks.is_empty() });
                    } else {
                        let title = if link.title.is_empty() { String::new() } else { format!(" {}", json::stringify(&json!(link.title))) };
                        let pos = node.data.borrow().sourcepos;
                        push_text(&mut runs, &format!("![{alt}]({src}{title})"), marks, false, Some((pos.end.line, pos.end.column)));
                    }
                }
                NodeValue::WikiLink(_) => {
                    let raw = self.raw_inline(node).unwrap_or_else(|| self.lines.slice(node).unwrap_or_default().to_owned());
                    match import_atom_source(&raw) {
                        Some(atom) => runs.push(Run::Atom(atom)),
                        None => push_text(&mut runs, &raw, marks, false, None),
                    }
                }
                other => bail!("Unsupported CommonMark inline {other:?}"),
            }
        }
        Ok(runs)
    }
}

impl Converter<'_> {
    /// The source of an inline that spans lines, as markdown-it reads it:
    /// container prefixes removed but any further indentation of the later
    /// lines kept (comrak drops that indentation).
    fn raw_inline<'a>(&self, node: &'a AstNode<'a>) -> Option<String> {
        let pos = node.data.borrow().sourcepos;
        if pos.start.line == pos.end.line {
            return None;
        }
        let column = self.container_column(node)?;
        let mut out = self.lines.line(pos.start.line).get(pos.start.column.checked_sub(1)?..)?.to_owned();
        for number in pos.start.line + 1..=pos.end.line {
            let line = self.lines.line(number);
            let strip = line.bytes().take(column).take_while(|b| matches!(b, b' ' | b'\t' | b'>')).count();
            let line = &line[strip..];
            out.push('\n');
            if number == pos.end.line {
                out.push_str(line.get(..pos.end.column.checked_sub(strip)?)?);
            } else {
                out.push_str(line);
            }
        }
        Some(out)
    }

    /// A text node as markdown-it reads it, with which of its bytes are literal
    /// source rather than the result of a backslash escape or a character
    /// reference (only a literal `[[` can open a reference atom, as only that
    /// reaches markdown-it's rule). Numeric references to code points
    /// markdown-it refuses (controls, surrogates, noncharacters) become
    /// U+FFFD there; comrak follows HTML and decodes some of them.
    fn read_text<'a>(&self, node: &'a AstNode<'a>, text: &str) -> (String, Vec<(usize, bool)>) {
        let pos = node.data.borrow().sourcepos;
        let unknown = || (text.to_owned(), vec![(text.len(), false)]);
        let (Some(start), Some(end)) = (self.lines.offset(pos.start.line, pos.start.column), self.lines.offset(pos.end.line, pos.end.column)) else {
            return unknown();
        };
        let source = self.lines.source.as_bytes();
        // comrak starts a text node that begins with an escaped character
        // after its backslash.
        let mut j = if start > 0 && source[start - 1] == b'\\' && text.as_bytes().first().is_some_and(u8::is_ascii_punctuation) { start - 1 } else { start };
        let end = (end + 1).min(source.len());
        let mut out = String::with_capacity(text.len());
        let mut spans: Vec<(usize, bool)> = Vec::new();
        let mut push = |out: &mut String, piece: &str, flag: bool| {
            out.push_str(piece);
            match spans.last_mut() {
                Some((last, last_flag)) if *last_flag == flag => *last += piece.len(),
                _ => spans.push((piece.len(), flag)),
            }
        };
        let mut buffer = [0; 4];
        for c in text.chars() {
            let length = c.len_utf8();
            let piece: &str = c.encode_utf8(&mut buffer);
            // A character reference: numeric ones decode as markdown-it does;
            // a named one is recognized by decoding to something other than
            // its own first byte (or by being `&amp;`).
            let reference = (source.get(j) == Some(&b'&'))
                .then(|| source[j..source.len().min(j + 40)].iter().position(|b| *b == b';'))
                .flatten()
                .map(|semi| &self.lines.source[j..j + semi + 1])
                .filter(|reference| numeric_reference(reference).is_some() || c != '&' || *reference == "&amp;");
            if let Some(reference) = reference {
                match numeric_reference(reference) {
                    Some(code) => {
                        let decoded = char::from_u32(code).filter(|_| valid_entity_code(code)).unwrap_or('\u{fffd}');
                        push(&mut out, decoded.encode_utf8(&mut [0; 4]), false);
                    }
                    None => push(&mut out, piece, false),
                }
                j += reference.len();
            } else if source.get(j..j + length) == Some(piece.as_bytes()) {
                push(&mut out, piece, true);
                j += length;
            } else if source.get(j) == Some(&b'\\') && source.get(j + 1) == piece.as_bytes().first() && c.is_ascii_punctuation() {
                push(&mut out, piece, false);
                j += 2;
            } else if j >= end || source.get(j) != Some(&b'&') {
                // A named reference that decodes to more than one character,
                // or text comrak synthesized: not literal.
                push(&mut out, piece, false);
            } else {
                return unknown();
            }
        }
        (out, spans)
    }

    /// The column where the content of the container holding this inline's
    /// block starts: markdown-it removes only that much indentation from a
    /// paragraph's later lines.
    fn container_column<'a>(&self, node: &'a AstNode<'a>) -> Option<usize> {
        let block = node.ancestors().find(|a| matches!(value_of(a), NodeValue::Paragraph | NodeValue::Heading(_) | NodeValue::TableCell))?;
        let container = block.parent()?;
        let column = match value_of(container) {
            NodeValue::Document => 0,
            NodeValue::Item(list) => container.data.borrow().sourcepos.start.column.saturating_sub(1) + list.padding,
            _ => block.data.borrow().sourcepos.start.column.saturating_sub(1),
        };
        Some(column)
    }

    /// markdown-it keeps a line's trailing whitespace before a soft break
    /// unless it ends in a space, of which it removes one; comrak removes all.
    fn restore_trailing_whitespace<'a>(&self, softbreak: &'a AstNode<'a>, runs: &mut Vec<Run>, marks: &[Value]) {
        let Some(previous) = softbreak.previous_sibling() else { return };
        let pos = previous.data.borrow().sourcepos;
        let Some(tail) = self.lines.line(pos.end.line).get(pos.end.column..) else { return };
        if tail.is_empty() || !tail.bytes().all(|b| b == b' ' || b == b'\t') {
            return;
        }
        // Before a hard break markdown-it removes every trailing space.
        let tail = if matches!(value_of(softbreak), NodeValue::LineBreak) { tail.trim_end_matches(' ') } else { tail.strip_suffix(' ').unwrap_or(tail) };
        if tail.is_empty() {
            return;
        }
        match runs.last_mut() {
            Some(Run::Text { text, verbatim, separate: false, .. }) if matches!(value_of(previous), NodeValue::Text(_)) => {
                text.push_str(tail);
                verbatim.push((tail.len(), false));
            }
            _ => push_text(runs, tail, marks, false, None),
        }
    }

    fn single_tilde<'a>(&self, node: &'a AstNode<'a>) -> bool {
        let pos = node.data.borrow().sourcepos;
        self.lines.offset(pos.start.line, pos.start.column).is_some_and(|at| self.lines.source.as_bytes().get(at + 1) != Some(&b'~'))
    }

    /// An image's raw label source, which markdown-it keeps as `alt`.
    fn image_label<'a>(&self, node: &'a AstNode<'a>) -> String {
        let (Some(first), Some(last)) = (node.first_child(), node.last_child()) else { return String::new() };
        let start = first.data.borrow().sourcepos.start;
        let end = last.data.borrow().sourcepos.end;
        match (self.lines.offset(start.line, start.column), self.lines.offset(end.line, end.column)) {
            (Some(from), Some(to)) if from <= to => self.lines.source.get(from..=to).map_or_else(|| alt_text(node), str::to_owned),
            _ => alt_text(node),
        }
    }
}

/// Trim JavaScript whitespace from both ends of a run sequence.
fn trim_runs(runs: &mut Vec<Run>) {
    if let Some(Run::Text { text, verbatim, .. }) = runs.first_mut() {
        let kept = text.trim_start_matches(json::is_js_space);
        let mut removed = text.len() - kept.len();
        *text = kept.to_owned();
        for span in verbatim.iter_mut() {
            let cut = removed.min(span.0);
            span.0 -= cut;
            removed -= cut;
        }
    }
    if let Some(Run::Text { text, verbatim, .. }) = runs.last_mut() {
        let kept = text.trim_end_matches(json::is_js_space);
        let mut removed = text.len() - kept.len();
        text.truncate(kept.len());
        for span in verbatim.iter_mut().rev() {
            let cut = removed.min(span.0);
            span.0 -= cut;
            removed -= cut;
        }
    }
    runs.retain(|run| !matches!(run, Run::Text { text, .. } if text.is_empty()));
}

/// The code point of a numeric character reference (`&#…;`, `&#x…;`).
fn numeric_reference(reference: &str) -> Option<u32> {
    let body = reference.strip_prefix("&#")?.strip_suffix(';')?;
    match body.strip_prefix(['x', 'X']) {
        Some(hex) if (1..=6).contains(&hex.len()) && hex.bytes().all(|b| b.is_ascii_hexdigit()) => u32::from_str_radix(hex, 16).ok(),
        None if (1..=7).contains(&body.len()) && body.bytes().all(|b| b.is_ascii_digit()) => body.parse().ok(),
        _ => None,
    }
}

/// markdown-it's `isValidEntityCode`.
fn valid_entity_code(code: u32) -> bool {
    !((0xD800..=0xDFFF).contains(&code)
        || (0xFDD0..=0xFDEF).contains(&code)
        || code & 0xFFFF >= 0xFFFE
        || code <= 0x08
        || code == 0x0B
        || (0x0E..=0x1F).contains(&code)
        || (0x7F..=0x9F).contains(&code)
        || code > 0x10_FFFF)
}

fn with_mark(marks: &[Value], mark: Value) -> Vec<Value> {
    let mut next = marks.to_vec();
    next.push(mark);
    next
}

/// Plain text of an image description, as markdown-it renders it.
fn alt_text<'a>(node: &'a AstNode<'a>) -> String {
    node.children()
        .map(|child| match value_of(child) {
            NodeValue::Text(text) => text.into_owned(),
            NodeValue::HtmlInline(html) => html,
            NodeValue::SoftBreak | NodeValue::LineBreak => "\n".into(),
            NodeValue::Code(_) => String::new(),
            _ => alt_text(child),
        })
        .collect()
}

/// An inline element after flattening marks.
enum Run {
    Text { text: String, marks: Vec<Value>, verbatim: Vec<(usize, bool)>, end: Option<(usize, usize)>, separate: bool },
    Html { text: String, marks: Vec<Value> },
    Code(String),
    Atom(Value),
    Image { src: String, alt: String, title: Value, nested: bool },
}

/// Join adjacent text with the same marks, as markdown-it joins text tokens.
/// `verbatim` records which byte spans came straight from source.
fn push_text(runs: &mut Vec<Run>, text: &str, marks: &[Value], verbatim: bool, end: Option<(usize, usize)>) {
    push_spans(runs, text, marks, vec![(text.len(), verbatim)], end);
}

fn push_spans(runs: &mut Vec<Run>, text: &str, marks: &[Value], verbatim: Vec<(usize, bool)>, end: Option<(usize, usize)>) {
    if let Some(Run::Text { text: last, marks: last_marks, verbatim: spans, end: last_end, separate: false }) = runs.last_mut()
        && last_marks.as_slice() == marks
    {
        last.push_str(text);
        spans.extend(verbatim);
        *last_end = end;
        return;
    }
    runs.push(Run::Text { text: text.to_owned(), marks: marks.to_vec(), verbatim, end, separate: false });
}

/// Historical wiki-style sources become canonical atoms; anything else stays text.
fn import_atom_source(raw: &str) -> Option<Value> {
    if let Some(atom) = parse_atom_source(raw) {
        return Some(atom);
    }
    let found = js_regex!(r"^\[\[([A-Z][A-Za-z0-9]*(?: [A-Z][A-Za-z0-9]*)*):\s*([^| ]+)\s*(?:\|([\s\S]*))?\]\]$").captures(raw)?;
    let kind = &found[1];
    let id = &found[2];
    let label = match found.get(3) {
        None => kind.to_owned(),
        Some(label) => label.as_str().strip_prefix(' ').unwrap_or(label.as_str()).to_owned(),
    };
    let normalized = if kind == "Tag" {
        format!("[[Tag: {id} | {label}]]")
    } else {
        build_entity_reference_source(Some(&json!(kind)), Some(&json!(id)), Some(&json!(label))).ok()?
    };
    parse_atom_source(&normalized)
}

enum Piece {
    Text(String),
    Atom(Value),
}

/// Split span lengths at a byte offset.
fn split_spans(spans: &[(usize, bool)], at: usize) -> (Vec<(usize, bool)>, Vec<(usize, bool)>) {
    let (mut left, mut right, mut seen) = (Vec::new(), Vec::new(), 0);
    for &(length, flag) in spans {
        if seen + length <= at {
            left.push((length, flag));
        } else if seen >= at {
            right.push((length, flag));
        } else {
            left.push((at - seen, flag));
            right.push((seen + length - at, flag));
        }
        seen += length;
    }
    (left, right)
}

/// markdown-it's reference rule reads from a literal `[[` to the first `]]`
/// even across line breaks. Ranges that span lines are resolved here: a
/// valid atom replaces them, anything else stays literal text that no later
/// `[[` inside it can reopen. Ranges within one text run are left to
/// [`split_text_atoms`].
fn cross_line_atoms(runs: Vec<Run>) -> Vec<Run> {
    let mut output: Vec<Run> = Vec::with_capacity(runs.len());
    let mut group: Vec<Run> = Vec::new();
    let flush = |group: &mut Vec<Run>, output: &mut Vec<Run>| {
        if group.len() >= 3 {
            output.extend(resolve_cross_line(std::mem::take(group)));
        } else {
            output.append(group);
        }
    };
    for run in runs {
        if matches!(run, Run::Text { .. }) {
            group.push(run);
        } else {
            flush(&mut group, &mut output);
            output.push(run);
        }
    }
    flush(&mut group, &mut output);
    output
}

fn resolve_cross_line(mut group: Vec<Run>) -> Vec<Run> {
    let mut combined = String::new();
    let mut owner: Vec<(usize, usize)> = Vec::new();
    let mut eligible: Vec<bool> = Vec::new();
    for (index, run) in group.iter().enumerate() {
        let Run::Text { text, verbatim, separate, .. } = run else { continue };
        combined.push_str(text);
        owner.extend((0..text.len()).map(|offset| (index, offset)));
        for &(length, flag) in verbatim {
            eligible.extend(std::iter::repeat_n(flag && !separate, length));
        }
        eligible.resize(combined.len(), false);
    }
    let marks_of = |run: &Run| match run {
        Run::Text { marks, .. } => marks.clone(),
        _ => Vec::new(),
    };
    let mut from = 0;
    while let Some(found) = combined[from..].find("[[") {
        let start = from + found;
        if !(eligible[start] && eligible[start + 1]) {
            from = start + 1;
            continue;
        }
        let Some(close) = combined[start + 2..].find("]]") else { break };
        let end = start + 2 + close + 2;
        from = end;
        let (first, first_offset) = owner[start];
        let (last, last_offset) = owner[end - 1];
        if first == last {
            continue;
        }
        let same_marks = (first..=last).all(|i| marks_of(&group[i]) == marks_of(&group[first]));
        match import_atom_source(&combined[start..end]).filter(|_| same_marks) {
            Some(atom) => {
                // Keep the first run's text before the atom and the last
                // run's text after it; the runs between are consumed.
                let (Run::Text { text: head, verbatim: head_spans, marks, .. }, Run::Text { text: tail, verbatim: tail_spans, end: tail_end, .. }) =
                    (&group[first], &group[last])
                else {
                    continue;
                };
                let before = Run::Text {
                    text: head[..first_offset].to_owned(),
                    marks: marks.clone(),
                    verbatim: split_spans(head_spans, first_offset).0,
                    end: None,
                    separate: false,
                };
                let after = Run::Text {
                    text: tail[last_offset + 1..].to_owned(),
                    marks: marks.clone(),
                    verbatim: split_spans(tail_spans, last_offset + 1).1,
                    end: *tail_end,
                    separate: false,
                };
                let mut rebuilt: Vec<Run> = group.drain(..first).collect();
                rebuilt.push(before);
                rebuilt.push(Run::Atom(atom));
                rebuilt.push(after);
                rebuilt.extend(group.drain(last + 1 - first..));
                rebuilt.retain(|run| !matches!(run, Run::Text { text, separate: false, .. } if text.is_empty()));
                // Positions changed; resolve the rest of the group again.
                let (done, rest): (Vec<Run>, Vec<Run>) = {
                    let split = rebuilt.iter().position(|run| matches!(run, Run::Atom(_))).map_or(rebuilt.len(), |i| i + 1);
                    let rest = rebuilt.split_off(split);
                    (rebuilt, rest)
                };
                let mut output = done;
                output.extend(if rest.len() >= 3 { resolve_cross_line(rest) } else { rest });
                return output;
            }
            None => {
                for (index, run) in group.iter_mut().enumerate().take(last + 1).skip(first) {
                    if let Run::Text { text, verbatim, .. } = run {
                        let low = if index == first { first_offset } else { 0 };
                        let high = if index == last { last_offset + 1 } else { text.len() };
                        let (left, right) = split_spans(verbatim, low);
                        let (_, rest) = split_spans(&right, high - low);
                        *verbatim = left.into_iter().chain([(high - low, false)]).chain(rest).collect();
                    }
                }
            }
        }
    }
    group
}

/// Find canonical `[[...]]` atoms inside verbatim source text that the parser
/// did not tokenize as a wiki link (for example labels containing `|`).
fn split_text_atoms(text: &str, verbatim: &[(usize, bool)]) -> Vec<Piece> {
    let mut eligible = Vec::with_capacity(text.len());
    for (length, flag) in verbatim {
        eligible.extend(std::iter::repeat_n(*flag, *length));
    }
    let mut parts = Vec::new();
    let (mut cursor, mut from) = (0, 0);
    while let Some(found) = text[from..].find("[[") {
        let start = from + found;
        let Some(close) = text[start + 2..].find("]]") else { break };
        let end = start + 2 + close + 2;
        from = end;
        if !eligible[start..end].iter().all(|flag| *flag) {
            continue;
        }
        if let Some(atom) = import_atom_source(&text[start..end]) {
            if start > cursor {
                parts.push(Piece::Text(text[cursor..start].to_owned()));
            }
            parts.push(Piece::Atom(atom));
            cursor = end;
        }
    }
    if cursor < text.len() {
        parts.push(Piece::Text(text[cursor..].to_owned()));
    }
    parts
}

fn recovery_marker(text: &str) -> bool {
    js_regex!(r"^<!--relay-task-draft:[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}-->$").is_match(text)
}

fn sorted_marks(marks: &[Value]) -> Vec<Value> {
    let mut sorted = marks.to_vec();
    sorted.sort_by_key(|mark| TEXT_MARKS.iter().position(|m| mark["type"] == *m));
    sorted
}

fn marked_text(text: &str, marks: &[Value]) -> Result<Value> {
    let mut node = Map::from_iter([("type".into(), json!("text")), ("text".into(), json!(text))]);
    if !marks.is_empty() {
        node.insert("marks".into(), Value::Array(sorted_marks(marks)));
    }
    map_inline(&Value::Object(node))
}

/// Runs to AST inline nodes (the reference runtime's `inline`).
fn inline(runs: Vec<Run>) -> Result<Vec<Value>> {
    let mut output: Vec<Value> = Vec::new();
    for run in cross_line_atoms(runs) {
        match run {
            Run::Text { text, marks, verbatim, .. } => {
                for part in split_text_atoms(&text, &verbatim) {
                    match part {
                        Piece::Atom(atom) => output.push(atom),
                        Piece::Text(text) => {
                            let text = js_regex!(r" ?<!--relay-task-draft:[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}-->")
                                .replace_all(&text, "");
                            if !text.is_empty() {
                                output.push(marked_text(&text, &marks)?);
                            }
                        }
                    }
                }
            }
            Run::Html { text, marks } => {
                if recovery_marker(&text) {
                    if let Some(previous) = output.last_mut().filter(|p| p["type"] == "text")
                        && let Some(kept) = previous["text"].as_str().and_then(|t| t.strip_suffix(' ')).map(str::to_owned)
                    {
                        if kept.is_empty() {
                            output.pop();
                        } else {
                            previous["text"] = Value::String(kept);
                        }
                    }
                    continue;
                }
                let text =
                    js_regex!(r" ?<!--relay-task-draft:[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}-->").replace_all(&text, "");
                if !text.is_empty() {
                    output.push(marked_text(&text, &marks)?);
                }
            }
            Run::Code(text) => output.push(map_inline(&json!({"type": "text", "text": text, "marks": [{"type": "code"}]}))?),
            Run::Atom(atom) => output.push(atom),
            Run::Image { .. } => bail!("Marked or linked inline image requires explicit authored media semantics"),
        }
    }
    Ok(output)
}

fn linked_task(item: &mut Value) {
    let Some(parts) = item["content"].get_mut(0).filter(|p| p["type"] == "paragraph").and_then(|p| p["content"].as_array_mut()) else {
        return;
    };
    let boundary = parts.iter().position(|n| n["type"] == "text" && n["text"].as_str().is_some_and(|t| t.contains('\n')));
    let Some(index) = boundary.unwrap_or(parts.len()).checked_sub(1) else { return };
    let last = &parts[index];
    if last["type"] != "relay.entity_ref" || last["props"]["entityType"] != "Task" {
        return;
    }
    let id = last["id"].clone();
    parts.remove(index);
    if let Some(previous) = index.checked_sub(1).and_then(|i| parts.get_mut(i))
        && previous["type"] == "text"
        && let Some(kept) = previous["text"].as_str().and_then(|t| t.strip_suffix(' ')).map(str::to_owned)
    {
        if kept.is_empty() {
            parts.remove(index - 1);
        } else {
            previous["text"] = Value::String(kept);
        }
    }
    item["props"]["entityId"] = id;
}

/// Standalone historical media lines: `::video[/v/<uuid>]` and bare `.gif` URLs.
fn historical_media(node: Value) -> Value {
    let content = node["content"].as_array().cloned().unwrap_or_default();
    if content.len() != 1 {
        return node;
    }
    let leaf = &content[0];
    if leaf["type"] == "text"
        && let Some(found) = js_regex!(r"^::video\[/v/([0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\]$")
            .captures(leaf["text"].as_str().unwrap_or_default())
    {
        return json!({"id": node["id"], "type": "relay.video_embed", "props": {"videoId": &found[1]}, "content": []});
    }
    let url = if leaf["type"] == "text" {
        leaf["text"].as_str()
    } else if leaf["type"] == "link" && leaf["content"].as_array().is_some_and(|c| c.len() == 1 && c[0]["type"] == "text" && c[0]["text"] == leaf["href"]) {
        leaf["href"].as_str()
    } else {
        None
    };
    match url {
        Some(url) if safe_image_source(url) && js_regex!(r"^(?i:https)://[^?#]+\.(?i:gif)(?:[?#]|$)").is_match(url) => {
            json!({"id": node["id"], "type": "image", "props": {"src": url, "alt": "", "title": null}, "content": []})
        }
        _ => node,
    }
}

/// Inline-only parse of a short authored string (callout titles, form
/// labels), as markdown-it's `parseInline`: no block structure, no reference
/// definitions, whitespace kept at both ends.
fn parse_inline(text: &str) -> Result<Vec<Value>> {
    // A no-break space before every line keeps block syntax (headings, lists,
    // HTML blocks, definitions) inert while still counting as whitespace for
    // emphasis flanking; one after the text keeps trailing spaces.
    let source = format!("\u{a0}{}\u{a0}", text.replace('\0', "\u{fffd}").replace('\n', "\n\u{a0}"));
    let arena = Arena::new();
    let root = comrak::parse_document(&arena, &source, &comrak_options());
    let lines = Lines::new(&source);
    fix_wikilink_positions(root, &lines);
    let converter = Converter { namespace: "", lines };
    let mut runs = Vec::new();
    for child in root.children() {
        if !matches!(value_of(child), NodeValue::Paragraph) {
            bail!("Directive inline content");
        }
        if !runs.is_empty() {
            runs.push(Run::Text { text: "\n".into(), marks: Vec::new(), verbatim: vec![(1, false)], end: None, separate: true });
        }
        runs.extend(converter.runs(child, &[])?);
    }
    // Remove the guards: the first line's, each later line's (with the
    // spaces markdown-it skips after a line break) and the trailing one.
    let (mut line_start, mut first_line) = (true, true);
    for run in &mut runs {
        match run {
            Run::Text { text, separate: true, .. } if text == "\n" => (line_start, first_line) = (true, false),
            Run::Atom(atom) if atom["type"] == "hard_break" => (line_start, first_line) = (true, false),
            Run::Text { text, verbatim, .. } if line_start => {
                line_start = false;
                if let Some(rest) = text.strip_prefix('\u{a0}') {
                    let kept = if first_line { rest } else { rest.trim_start_matches([' ', '\t']) };
                    let removed = text.len() - kept.len();
                    *text = kept.to_owned();
                    if let Some(span) = verbatim.first_mut() {
                        span.0 = span.0.saturating_sub(removed);
                    }
                }
            }
            _ => line_start = false,
        }
    }
    if let Some(Run::Text { text, verbatim, .. }) = runs.last_mut()
        && let Some(rest) = text.strip_suffix('\u{a0}')
    {
        *text = rest.to_owned();
        if let Some(span) = verbatim.last_mut() {
            span.0 = span.0.saturating_sub('\u{a0}'.len_utf8());
        }
    }
    runs.retain(|run| !matches!(run, Run::Text { text, .. } if text.is_empty()));
    inline(runs)
}

// ---- Historical question comments ----

fn decode_entities(text: &str) -> String {
    text.replace("&quot;", "\"").replace("&#39;", "'").replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
}

fn historical_question(header: &str, body: &str, namespace: &str, path: &[String]) -> Result<Value> {
    let raw = js_regex!(r"^<!--\s*relay:question\s+(.*?)\s*-->$").captures(header).map(|m| m[1].to_owned()).unwrap_or_default();
    let pattern = js_regex!(r#"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*("(?:\\.|[^"\\])*"|'[^']*')"#);
    if !json::js_trim(&pattern.replace_all(&raw, "")).is_empty() {
        bail!("Invalid historical question attributes");
    }
    let mut attributes: Vec<(String, String)> = Vec::new();
    for found in pattern.captures_iter(&raw) {
        let key = found[1].to_owned();
        if attributes.iter().any(|(k, _)| *k == key) {
            bail!("Duplicate historical question attribute");
        }
        let quoted = &found[2];
        attributes.push((key, decode_entities(&quoted[1..quoted.len() - 1])));
    }
    let get = |key: &str| attributes.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_str());
    let kind = get("type").unwrap_or("short_text").to_owned();
    let number = |key: &str| -> Result<Value> {
        match get(key) {
            None => Ok(Value::Null),
            Some(text) => match serde_json::from_str::<Value>(text) {
                Ok(value) if json::is_finite_number(&value) => Ok(value),
                _ => bail!("Invalid historical question number"),
            },
        }
    };
    let mut settings = match get("settings") {
        Some(text) => match serde_json::from_str::<Value>(text) {
            Ok(Value::Object(map)) => map,
            _ => bail!("Invalid historical question settings"),
        },
        None => Map::new(),
    };
    for (key, value) in &attributes {
        if ["id", "type", "required", "points", "min", "max", "settings", "label", "options"].contains(&key.as_str()) {
            continue;
        }
        if settings.contains_key(key) {
            bail!("Duplicate historical setting");
        }
        settings.insert(key.clone(), serde_json::from_str(value).unwrap_or_else(|_| Value::String(value.clone())));
    }
    let choice = ["multiple_choice", "dropdown", "checkboxes", "single_select", "multi_select"].contains(&kind.as_str());
    let option_pattern = if ["checkboxes", "multi_select"].contains(&kind.as_str()) {
        js_regex!(r"^\s*-?\s*\[([xX ])\]\s*(.*)$")
    } else {
        js_regex!(r"^\s*-?\s*\(([xX ])\)\s*(.*)$")
    };
    let mut labels = Vec::new();
    let mut options: Vec<Map> = Vec::new();
    for raw_line in body.split('\n') {
        let line = json::js_trim(raw_line);
        match option_pattern.captures(line).filter(|_| choice) {
            Some(found) => {
                options.push(Map::from_iter([("text".into(), json!(json::js_trim(&found[2]))), ("correct".into(), json!(found[1].to_lowercase() == "x"))]))
            }
            None if !line.is_empty() => labels.push(line.to_owned()),
            None => {}
        }
    }
    let mut choices = options.clone();
    if let Some(explicit) = get("options") {
        let explicit = match serde_json::from_str::<Value>(explicit) {
            Ok(Value::Array(items)) if options.is_empty() || options.len() == items.len() => items,
            _ => bail!("Invalid historical question options"),
        };
        choices = explicit
            .iter()
            .enumerate()
            .map(|(i, option)| {
                let mut merged = options.get(i).cloned().unwrap_or_default();
                for (key, value) in option.as_object().into_iter().flatten() {
                    merged.insert(key.clone(), value.clone());
                }
                merged
            })
            .collect();
    }
    let label = if labels.is_empty() { get("label").unwrap_or("").to_owned() } else { labels.join("\n") };
    let mut content = vec![block(namespace, &child_path(path, 0), "paragraph", parse_inline_or_empty(&label)?, None)];
    for (offset, option) in choices.iter().enumerate() {
        let index = offset + 1;
        let truthy_text = |key: &str| option.get(key).filter(|v| json::truthy(Some(v))).map(js_string);
        let text = truthy_text("label").or_else(|| truthy_text("text")).unwrap_or_default();
        let slug: String = js_regex!(r"^-+|-+$").replace_all(&js_regex!(r"[^a-z0-9]+").replace_all(&text.to_lowercase(), "-"), "").chars().take(80).collect();
        let extra: Map = option
            .iter()
            .filter(|(k, _)| !["id", "label", "text", "correct", "points", "settings"].contains(&k.as_str()))
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();
        let id = option
            .get("id")
            .filter(|v| json::truthy(Some(v)))
            .cloned()
            .unwrap_or_else(|| if slug.is_empty() { json!(format!("option-{index}")) } else { json!(slug) });
        let mut option_settings = option.get("settings").filter(|v| json::truthy(Some(v))).and_then(Value::as_object).cloned().unwrap_or_default();
        option_settings.extend(extra);
        let props = Map::from_iter([
            ("id".into(), id),
            ("correct".into(), option.get("correct").filter(|v| !v.is_null()).cloned().unwrap_or(json!(false))),
            ("points".into(), option.get("points").filter(|v| !v.is_null()).cloned().unwrap_or(Value::Null)),
            ("settings".into(), Value::Object(option_settings)),
        ]);
        content.push(block(namespace, &child_path(path, index), "relay.form_option", parse_inline_or_empty(&text)?, Some(props)));
    }
    let props = Map::from_iter([
        ("id".into(), get("id").map_or(Value::Null, |id| json!(id))),
        ("type".into(), json!(kind)),
        ("required".into(), json!(get("required") == Some("true"))),
        ("points".into(), number("points")?),
        ("min".into(), number("min")?),
        ("max".into(), number("max")?),
        ("settings".into(), Value::Object(settings)),
    ]);
    Ok(block(namespace, path, "relay.form_question", content, Some(props)))
}

fn parse_inline_or_empty(text: &str) -> Result<Vec<Value>> {
    if text.is_empty() { Ok(Vec::new()) } else { parse_inline(text) }
}

// ---- Readable Markdown projection ----

/// Readable Markdown for search, export and review. A derived projection,
/// never a second writable body.
pub fn project_markdown(document: &Value) -> Result<String> {
    normalize_document(document)?;
    let blocks = document["blocks"].as_array().map(Vec::as_slice).unwrap_or(&[]);
    let parts = blocks.iter().map(markdown).collect::<Result<Vec<_>>>()?;
    Ok(parts.join("\n\n") + "\n")
}

fn escape_markdown(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        if matches!(c, '\\' | '`' | '*' | '_' | '[' | ']' | '{' | '}') {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

pub fn inline_markdown(nodes: &[Value]) -> Result<String> {
    let mut out = String::new();
    for node in nodes {
        let kind = node["type"].as_str().unwrap_or_default();
        let children = || node["content"].as_array().map(Vec::as_slice).unwrap_or(&[]);
        match kind {
            "text" => out.push_str(&escape_markdown(node["text"].as_str().unwrap_or_default())),
            "hard_break" => out.push_str("  \n"),
            "relay.entity_ref" | "relay.tag_ref" => out.push_str(node["props"]["source"].as_str().unwrap_or("undefined")),
            "link" => {
                let title = node.get("props").and_then(|p| p.get("title")).filter(|t| !t.is_null());
                let title = title.map(|t| format!(" {}", json::stringify(t))).unwrap_or_default();
                out.push_str(&format!("[{}]({}{title})", inline_markdown(children())?, node["href"].as_str().unwrap_or_default()));
            }
            "code_span" => {
                let text = children().first().and_then(|c| c["text"].as_str()).unwrap_or_default();
                let fence = "`".repeat(longest_ticks(text) + 1);
                out.push_str(&format!("{fence}{text}{fence}"));
            }
            "ai_authored" => out.push_str(&inline_markdown(children())?),
            _ => {
                let delimiter = match kind {
                    "strong" => "**",
                    "emphasis" => "*",
                    "strikethrough" => "~~",
                    "underline" => "<u>",
                    "highlight" => "<mark>",
                    "superscript" => "<sup>",
                    "subscript" => "<sub>",
                    _ => bail!("Unsupported inline projection"),
                };
                let closing = if delimiter.starts_with('<') { delimiter.replacen('<', "</", 1) } else { delimiter.to_owned() };
                out.push_str(&format!("{delimiter}{}{closing}", inline_markdown(children())?));
            }
        }
    }
    Ok(out)
}

fn block_markdown_list(nodes: &[Value], separator: &str) -> Result<String> {
    Ok(nodes.iter().map(markdown).collect::<Result<Vec<_>>>()?.join(separator))
}

fn props_markdown(props: &Value) -> String {
    props
        .as_object()
        .map(|p| json::ordered_entries(p).into_iter().map(|(k, v)| format!("{k}: {}", json::stringify(v))).collect::<Vec<_>>().join(", "))
        .unwrap_or_default()
}

fn markdown(node: &Value) -> Result<String> {
    let props = node.get("props").unwrap_or(&Value::Null);
    let content = node["content"].as_array().map(Vec::as_slice).unwrap_or(&[]);
    let kind = node["type"].as_str().unwrap_or_default();
    Ok(match kind {
        "paragraph" | "relay.callout_title" => inline_markdown(content)?,
        "heading" => {
            let level = props["level"].as_u64().unwrap_or(1) as usize;
            let anchor = props["headingId"].as_str().filter(|id| !id.is_empty()).map(|id| format!(" {{#{id}}}")).unwrap_or_default();
            format!("{} {}{anchor}", "#".repeat(level), inline_markdown(content)?)
        }
        "quote" => block_markdown_list(content, "\n\n")?.split('\n').map(|line| format!("> {line}")).collect::<Vec<_>>().join("\n"),
        "horizontal_rule" => "---".into(),
        "code" => {
            let text: String = content.iter().map(|c| c["text"].as_str().unwrap_or_default()).collect();
            let fence = "`".repeat(3.max(longest_ticks(&text) + 1));
            let language = props["language"].as_str().unwrap_or_default();
            format!("{fence}{language}\n{text}{}{fence}", if text.ends_with('\n') { "" } else { "\n" })
        }
        "image" => format!("![{}]({})", props["alt"].as_str().unwrap_or_default(), js_string(&props["src"])),
        "list" | "task_list" => {
            let mut lines = Vec::new();
            for (index, item) in content.iter().enumerate() {
                let marker = if kind == "task_list" {
                    if item["props"]["checked"] == true { "- [x] ".to_owned() } else { "- [ ] ".to_owned() }
                } else if props["kind"] == "ordered" {
                    format!("{}. ", json::float_string(props["start"].as_f64().unwrap_or(1.0) + index as f64))
                } else {
                    "- ".to_owned()
                };
                let text = block_markdown_list(item["content"].as_array().map(Vec::as_slice).unwrap_or(&[]), "\n\n")?;
                let mut parts = text.split('\n');
                let first = parts.next().unwrap_or_default();
                let indent = " ".repeat(json::utf16_len(&marker));
                let rest: String = parts.map(|line| format!("\n{indent}{line}")).collect();
                lines.push(format!("{marker}{first}{rest}"));
            }
            lines.join("\n")
        }
        "table" => {
            let rows = content
                .iter()
                .map(|row| {
                    let cells = row["content"].as_array().map(Vec::as_slice).unwrap_or(&[]).iter().map(|cell| {
                        Ok(block_markdown_list(cell["content"].as_array().map(Vec::as_slice).unwrap_or(&[]), " ")?.replace('|', "\\|").replace('\n', "<br>"))
                    });
                    Ok(format!("| {} |", cells.collect::<Result<Vec<_>>>()?.join(" | ")))
                })
                .collect::<Result<Vec<_>>>()?;
            let header = content.first().and_then(|row| row["content"].as_array()).map(Vec::as_slice).unwrap_or(&[]);
            let separator = header
                .iter()
                .map(|cell| match cell["props"]["align"].as_str() {
                    Some("left") => ":---",
                    Some("center") => ":---:",
                    Some("right") => "---:",
                    _ => "---",
                })
                .collect::<Vec<_>>()
                .join(" | ");
            let mut out = vec![rows.first().cloned().unwrap_or_default(), format!("| {separator} |")];
            out.extend(rows.iter().skip(1).cloned());
            out.join("\n")
        }
        "relay.form_option" => format!("- {}", inline_markdown(content)?),
        "relay.paper_control" | "relay.entity_reference" => js_string(props.get("source").unwrap_or(&Value::Null)),
        _ => {
            if let Some(generic) = directive_node_for_type(kind) {
                let name = directive_for_type(generic.ast_type).map(|d| d.name.as_str()).unwrap_or_default();
                return Ok(format!("@{name}({}) {{\n{}\n}}", props_markdown(props), block_markdown_list(content, "\n\n")?));
            }
            let name = match kind {
                "relay.callout" => "Callout",
                "relay.form_question" => "Question",
                "relay.agent_suggestion" => "AgentSuggestion",
                "relay.data_view" => "DataView",
                "relay.video_embed" => "Video",
                _ => bail!("Unsupported block projection"),
            };
            let body = if kind == "relay.agent_suggestion" { inline_markdown(content)? } else { block_markdown_list(content, "\n\n")? };
            format!("@{name}({}) {{\n{body}\n}}", props_markdown(props))
        }
    })
}
