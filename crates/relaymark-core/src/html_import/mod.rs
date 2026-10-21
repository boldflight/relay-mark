//! HTML import (document-html.js): retained rendered HTML to a canonical
//! document, and clipboard HTML to an editor slice. Relay's own HTML is read
//! strictly through the canonical rules and must account for every source
//! node, attribute, mark and character; HTML other applications put on the
//! clipboard is read with the web editor's paste rules.

mod dom;
mod model;
mod parser;
mod rules;

use std::collections::{BTreeMap, HashMap};

use serde_json::Value;

use crate::error::{Result, bail};
use crate::json::{self, Map};

use dom::{Dom, Id};
use model::{Node, Schema, TypeId, append, fragment, max_open, schema};
use parser::Whitespace;
use rules::{Inventory, canonical_parser, foreign_parser, inspect};

const MAX_HTML: usize = 4_194_304;

fn normalization(entries: Vec<(&str, Value)>) -> Value {
    Value::Object(entries.into_iter().map(|(key, value)| (key.to_owned(), value)).collect())
}

fn check_input(html: &str, namespace: &str) -> Result<()> {
    if json::utf16_len(html) > MAX_HTML || html.len() > MAX_HTML || namespace.is_empty() {
        bail!("Invalid retained HTML input");
    }
    Ok(())
}

/// `readHTML`: the HTML as the body of an otherwise empty document.
fn read_html(html: &str, namespace: &str) -> Result<(Dom, Id)> {
    check_input(html, namespace)?;
    let dom = Dom::parse(&format!("<html><head></head><body>{html}</body></html>"));
    let Some(root) = dom.element_children(dom.document()).into_iter().find(|&e| dom.name(e) == "html") else { bail!("Invalid retained HTML envelope") };
    let children = dom.element_children(root);
    let head = children.iter().copied().find(|&e| dom.name(e) == "head");
    let body = children.iter().copied().find(|&e| dom.name(e) == "body");
    match (head, body) {
        (Some(head), Some(body)) if children.len() == 2 && dom.children(head).is_empty() => Ok((dom, body)),
        _ => bail!("Invalid retained HTML envelope"),
    }
}

/// Retained rendered HTML (for example a frozen `description_html`) to a
/// canonical document, as `importDocumentSnapshot` returns it, with the
/// normalizations the import made. `None` is an explicit empty retention.
pub fn import_document(html: Option<&str>, namespace: &str) -> Result<Value> {
    let source = html.unwrap_or("");
    let (mut dom, body) = read_html(source, namespace)?;
    let mut inventory = inspect(&dom, body)?;
    let schema = schema();
    let document = canonical_parser().parse(&mut dom, body, Some(Whitespace::Full))?;
    schema.check(&document)?;
    validate_projection(schema, &document, &mut inventory)?;
    let prosemirror = schema.to_json(&document);
    let snapshot = crate::snapshot::prosemirror_to_snapshot(&prosemirror, &Value::Object(Map::new()))?;
    let mut imported = crate::migrate::import_document_snapshot(&snapshot, namespace)?;
    let mut normalizations = Vec::new();
    if source.is_empty() {
        normalizations.push(normalization(vec![("operation", "empty_retained_html".into()), ("source_value", html.map_or(Value::Null, Value::from))]));
    }
    normalizations.append(&mut inventory.normalizations);
    if let Some(Value::Array(existing)) = imported.get_mut("normalizations") {
        normalizations.append(existing);
    }
    normalizations.push(normalization(vec![("operation", "import_retained_html".into()), ("source", "description_html".into())]));
    imported.as_object_mut().expect("imported document").insert("normalizations".into(), Value::Array(normalizations));
    Ok(imported)
}

/// `validateProjection`: the parse kept every source character, node (save
/// paragraphs PM wraps around loose inline content), attribute and mark.
fn validate_projection(schema: &Schema, document: &Node, inventory: &mut Inventory) -> Result<()> {
    struct Parsed<'a> {
        node: &'a Node,
        /// Index of the parent in the parsed list; `None` for the root.
        parent: Option<usize>,
        parent_type: TypeId,
    }
    fn walk<'a>(schema: &Schema, node: &'a Node, parent: Option<usize>, nodes: &mut Vec<Parsed<'a>>, text: &mut String, marks: &mut BTreeMap<String, String>) {
        for child in &node.content {
            if let Some(value) = &child.text {
                text.push_str(value);
                for mark in &child.marks {
                    let key = json::stable_stringify(&Value::Array(vec![schema.marks[mark.ty].name.clone().into(), Value::Object(mark.attrs.clone())]));
                    marks.entry(key).or_default().push_str(value);
                }
                continue;
            }
            nodes.push(Parsed { node: child, parent, parent_type: node.ty });
            let index = nodes.len() - 1;
            walk(schema, child, Some(index), nodes, text, marks);
        }
    }
    let mut parsed = Vec::new();
    let mut parsed_text = String::new();
    let mut parsed_marks = BTreeMap::new();
    walk(schema, document, None, &mut parsed, &mut parsed_text, &mut parsed_marks);
    if parsed_text != inventory.text {
        bail!("Retained HTML text was not preserved");
    }
    let paragraph = schema.node_type("paragraph").expect("paragraph");
    let mut matched: HashMap<usize, (bool, usize)> = HashMap::new();
    let mut source_index = 0;
    for (index, entry) in parsed.iter().enumerate() {
        let original = inventory.nodes.get(source_index);
        if entry.node.ty == paragraph && original.is_none_or(|o| o.name != "paragraph") {
            let parent = entry.parent.and_then(|p| matched.get(&p));
            let implicit = parent.is_some_and(|(allows, _)| *allows) && schema.match_type(schema.nodes[entry.parent_type].content, paragraph).is_some();
            if implicit || (inventory.nodes.is_empty() && json::js_trim(&inventory.text).is_empty()) {
                let parent_index = parent.map_or(Value::Null, |(_, at)| Value::from(*at));
                inventory.normalizations.push(normalization(vec![
                    ("operation", "wrap_retained_inline".into()),
                    ("node", "paragraph".into()),
                    ("source_parent_index", parent_index),
                ]));
                continue;
            }
        }
        let Some(original) = original else { bail!("Retained HTML structure or attributes were not preserved") };
        let same = schema.nodes[entry.node.ty].name == original.name
            && original.attributes.iter().all(|(key, value)| {
                json::stable_stringify(entry.node.attrs.get(key).unwrap_or(&Value::Null)) == json::stable_stringify(value) && entry.node.attrs.contains_key(key)
            });
        if !same {
            bail!("Retained HTML structure or attributes were not preserved");
        }
        matched.insert(index, (original.allows_implicit_paragraph, source_index));
        source_index += 1;
    }
    if source_index != inventory.nodes.len() {
        bail!("Retained HTML structure was not preserved");
    }
    let mut expected: BTreeMap<String, String> = BTreeMap::new();
    for mark in &inventory.marks {
        let key = json::stable_stringify(&Value::Array(vec![mark.name.into(), Value::Object(mark.attributes.clone())]));
        expected.entry(key).or_default().push_str(&mark.text);
    }
    if expected != parsed_marks {
        bail!("Retained HTML marks were not preserved");
    }
    Ok(())
}

/// An editor slice: content with open depths on each side.
struct Slice {
    content: Vec<Node>,
    open_start: usize,
    open_end: usize,
}

impl Slice {
    fn to_json(&self, schema: &Schema) -> Value {
        normalization(vec![("content", schema.fragment_json(&self.content)), ("openStart", self.open_start.into()), ("openEnd", self.open_end.into())])
    }
}

fn node_size(schema: &Schema, node: &Node) -> usize {
    match &node.text {
        Some(text) => json::utf16_len(text),
        None if schema.is_leaf(node.ty) => 1,
        None => fragment_size(schema, &node.content) + 2,
    }
}

fn fragment_size(schema: &Schema, nodes: &[Node]) -> usize {
    nodes.iter().map(|node| node_size(schema, node)).sum()
}

/// Clipboard HTML to an editor slice `{slice: {content, openStart, openEnd},
/// normalizations}`. Relay's own clipboard HTML (and any ProseMirror slice) is
/// read exactly; HTML another application wrote is read as a web paste.
pub fn import_clipboard(html: &str, namespace: &str) -> Result<Value> {
    let canonical = import_canonical_clipboard(html, namespace);
    let Err(error) = canonical else { return canonical };
    if check_input(html, namespace).is_err() {
        return Err(error);
    }
    // Other applications write whole documents, with head, styles and metadata.
    let lower = html.to_ascii_lowercase();
    let whole = lower.match_indices("<html").any(|(at, _)| lower[at + 5..].starts_with(|c: char| c == '>' || is_regex_space(c)));
    let dom = Dom::parse(&if whole { html.to_owned() } else { format!("<html><head></head><body>{html}</body></html>") });
    let body = dom.find_descendant(dom.document(), "body");
    // Editor-written HTML (a ProseMirror slice, Relay identities or authored
    // attributes) keeps its exact import and its refusals.
    let Some(body) = body else { return Err(error) };
    let editor_written = dom.descendants(body).into_iter().any(|element| {
        dom.attrs(element)
            .iter()
            .any(|(name, _)| ["data-pm-slice", "data-relaymark", "data-authored", "data-relay-"].iter().any(|prefix| name.starts_with(prefix)))
    });
    if editor_written {
        return Err(error);
    }
    import_foreign_clipboard(dom, body)
}

/// JavaScript `\s`.
fn is_regex_space(character: char) -> bool {
    json::is_js_space(character)
}

fn import_foreign_clipboard(mut dom: Dom, body: Id) -> Result<Value> {
    let schema = schema();
    let content = foreign_parser().parse_slice(&mut dom, body, None)?;
    // `Slice.fromJSON` into the canonical schema rebuilds the same nodes.
    let (open_start, open_end) = max_open(schema, &content, true);
    let slice = Slice { content, open_start, open_end };
    if slice.content.is_empty() {
        bail!("Empty clipboard Slice");
    }
    schema.check(&schema.create(schema.top, None, slice.content.clone(), Vec::new())?)?;
    let (start, end) = max_open(schema, &slice.content, false);
    let slice = close_slice(schema, slice, start, end)?;
    Ok(normalization(vec![
        ("slice", slice.to_json(schema)),
        ("normalizations", Value::Array(vec![normalization(vec![("operation", "import_foreign_clipboard_html".into()), ("source", "clipboard_html".into())])])),
    ]))
}

fn import_canonical_clipboard(html: &str, namespace: &str) -> Result<Value> {
    let schema = schema();
    let (mut dom, body) = read_html(html, namespace)?;
    let mut normalizations = normalize_identities(&mut dom, body)?;
    let markers: Vec<Id> = dom.descendants(body).into_iter().filter(|&e| dom.has_attr(e, "data-pm-slice")).collect();
    if markers.len() > 1 {
        bail!("Duplicate clipboard Slice metadata");
    }
    let mut root = body;
    let mut declared: Option<(usize, usize)> = None;
    let mut context: Vec<Value> = Vec::new();
    if let Some(&marker) = markers.first() {
        let metadata = dom.attr(marker, "data-pm-slice").unwrap_or_default().to_owned();
        let Some(metadata) = parse_slice_metadata(&metadata) else { bail!("Invalid clipboard Slice metadata") };
        let within = |depth: Option<usize>| depth.filter(|&n| n <= 128);
        let (Some(start), Some(end), Some(wrappers)) = (within(metadata.open_start), within(metadata.open_end), within(metadata.wrappers)) else {
            bail!("Clipboard Slice depth limit")
        };
        declared = Some((start, end));
        let parsed = json::parse(&metadata.context)?;
        match parsed {
            Value::Array(items) if items.len() % 2 == 0 && items.len() <= 256 => context = items,
            _ => bail!("Invalid clipboard context"),
        }
        dom.remove_attr(marker, "data-pm-slice");
        for _ in 0..wrappers {
            let children = dom.children(root);
            let wrapper =
                children.first().copied().filter(|&child| children.len() == 1 && dom.is_element(child) && matches!(dom.name(child), "table" | "tbody" | "tr"));
            let Some(wrapper) = wrapper else { bail!("Invalid clipboard table wrapper") };
            if !dom.attrs(wrapper).is_empty() {
                bail!("Unexpected clipboard wrapper attributes");
            }
            root = wrapper;
        }
    }
    let mut inventory = inspect(&dom, root)?;
    let content = canonical_parser().parse_slice(&mut dom, root, Some(Whitespace::Full))?;
    let (open_start, open_end) = max_open(schema, &content, true);
    let mut slice = Slice { content, open_start, open_end };
    if slice.content.is_empty() {
        bail!("Empty clipboard Slice");
    }
    // Validate exact original semantic nodes and marks before adding exported context.
    let top = schema.create(schema.top, None, slice.content.clone(), Vec::new())?;
    validate_projection(schema, &top, &mut inventory)?;
    slice = match declared {
        Some((start, end)) => {
            if start > slice.open_start || end > slice.open_end {
                bail!("Clipboard Slice depths exceed parsed content");
            }
            close_slice(schema, slice, start, end)?
        }
        None => {
            let (start, end) = max_open(schema, &slice.content, false);
            close_slice(schema, slice, start, end)?
        }
    };
    for pair in context.chunks(2).rev() {
        let (name, attrs) = (&pair[0], &pair[1]);
        let ty = name.as_str().and_then(|name| schema.node_type(name));
        let Some(ty) = ty.filter(|&ty| ty != schema.top && !schema.is_leaf(ty) && !schema.has_required_attrs(ty)) else {
            bail!("Unsupported clipboard context")
        };
        let attrs = match attrs {
            Value::Null => None,
            Value::Object(map) if map.keys().all(|key| schema.node_attrs(ty, None).is_ok_and(|declared| declared.contains_key(key))) => Some(map),
            _ => bail!("Unsupported clipboard context"),
        };
        let wrapped = schema.create(ty, attrs, slice.content, Vec::new())?;
        slice = Slice { content: vec![wrapped], open_start: slice.open_start + 1, open_end: slice.open_end + 1 };
    }
    let (maximum_start, maximum_end) = max_open(schema, &slice.content, true);
    let size = fragment_size(schema, &slice.content) as isize - slice.open_start as isize - slice.open_end as isize;
    if slice.open_start > maximum_start || slice.open_end > maximum_end || size <= 0 {
        bail!("Invalid restored clipboard Slice geometry");
    }
    // No closed document conversion here: open list and table fragments are
    // legitimate; the host's preflight reads the exact fragment.
    normalizations.append(&mut inventory.normalizations);
    normalizations.push(normalization(vec![("operation", "import_clipboard_html".into()), ("source", "clipboard_html".into())]));
    Ok(normalization(vec![("slice", slice.to_json(schema)), ("normalizations", Value::Array(normalizations))]))
}

/// `data-pm-slice`: open depths, table wrapper count and context. A depth
/// beyond JavaScript's safe integers is `None`.
struct SliceMetadata {
    open_start: Option<usize>,
    open_end: Option<usize>,
    wrappers: Option<usize>,
    context: String,
}

/// `/^(\d+) (\d+)(?: -(\d+))? (.*)$/` with JavaScript `Number`s.
fn parse_slice_metadata(text: &str) -> Option<SliceMetadata> {
    let number = |digits: &str| -> Option<Option<usize>> {
        (!digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit()))
            .then(|| digits.parse::<f64>().ok().filter(|n| *n <= 9_007_199_254_740_991.0).map(|n| n as usize))
    };
    let (start, rest) = text.split_once(' ')?;
    let open_start = number(start)?;
    let (end, mut rest) = rest.split_once(' ')?;
    let open_end = number(end)?;
    let mut wrappers = Some(0);
    // `(?: -(\d+))?` is tried first; on failure the whole rest is the context.
    if let Some(after) = rest.strip_prefix('-')
        && let Some((digits, tail)) = after.split_once(' ')
        && let Some(count) = number(digits)
    {
        wrappers = count;
        rest = tail;
    }
    if rest.contains(['\n', '\r', '\u{2028}', '\u{2029}']) {
        return None;
    }
    Some(SliceMetadata { open_start, open_end, wrappers, context: rest.to_owned() })
}

/// Explicit recovery of the former web clipboard identity spelling.
fn normalize_identities(dom: &mut Dom, root: Id) -> Result<Vec<Value>> {
    let mut count = 0;
    for element in dom.descendants(root) {
        let Some(original) = dom.attr(element, "data-relaymarkid").map(str::to_owned) else { continue };
        if dom.attr(element, "data-relaymark-id").is_some_and(|canonical| canonical != original) {
            bail!("Conflicting clipboard structural identity");
        }
        dom.set_attr(element, "data-relaymark-id", &original);
        dom.remove_attr(element, "data-relaymarkid");
        count += 1;
    }
    Ok(if count > 0 {
        vec![normalization(vec![
            ("operation", "normalize_clipboard_structural_identity".into()),
            ("source", "data-relaymarkid".into()),
            ("target", "data-relaymark-id".into()),
            ("count", count.into()),
        ])]
    } else {
        Vec::new()
    })
}

/// `closeClipboardSlice`: prosemirror-view's closeSlice geometry.
fn close_slice(schema: &Schema, slice: Slice, open_start: usize, open_end: usize) -> Result<Slice> {
    let mut slice = slice;
    if open_start < slice.open_start {
        let content = close_range(schema, slice.content, true, open_start, slice.open_start, 0, slice.open_end)?;
        slice = Slice { content, open_start, open_end: slice.open_end };
    }
    if open_end < slice.open_end {
        let content = close_range(schema, slice.content, false, open_end, slice.open_end, 0, 0)?;
        slice = Slice { content, open_start: slice.open_start, open_end };
    }
    Ok(slice)
}

fn close_range(schema: &Schema, mut nodes: Vec<Node>, start_side: bool, from: usize, to: usize, depth: usize, open_end: usize) -> Result<Vec<Node>> {
    let open_end = if nodes.len() > 1 { 0 } else { open_end };
    let index = if start_side { 0 } else { nodes.len() - 1 };
    let node = &nodes[index];
    let mut inner = node.content.clone();
    if depth + 1 < to {
        inner = close_range(schema, inner, start_side, from, to, depth + 1, open_end)?;
    }
    if depth >= from {
        let start = schema.nodes[node.ty].content;
        let fill = if start_side {
            schema.fill_before(start, &inner, open_end <= depth, 0)
        } else {
            schema.match_fragment(start, &node.content).and_then(|matched| schema.fill_before(matched, &[], true, 0))
        };
        let Some(fill) = fill else { bail!("Unclosable clipboard Slice") };
        inner = if start_side { append(fill, inner) } else { append(inner, fill) };
    }
    let mut copy = nodes[index].clone();
    copy.content = fragment(inner);
    nodes[index] = copy;
    Ok(nodes)
}

/// Corpus curation for `tools/html-dom.mjs`: the reference runtime parses
/// HTML with linkedom, this engine as the HTML standard (and browsers) do.
/// Tag soup they build different trees for is left out of the HTML oracle.
///
///     RELAYMARK_DOM_CALLS=calls.jsonl RELAYMARK_DOM_OUTPUT=doms.jsonl \
///       cargo test --release --lib dump_doms -- --ignored
#[cfg(test)]
mod dom_dump {
    use super::*;

    fn dump(dom: &Dom, id: Id) -> Value {
        let mut children: Vec<Value> = Vec::new();
        for &child in dom.children(id) {
            if let Some(text) = dom.text(child) {
                if let Some(Value::String(last)) = children.last_mut() {
                    last.push_str(text);
                } else {
                    children.push(Value::String(text.to_owned()));
                }
            } else if dom.is_element(child) {
                children.push(dump(dom, child));
            } else {
                children.push(serde_json::json!(["#comment"]));
            }
        }
        let mut attrs: Vec<(String, String)> = dom.attrs(id).to_vec();
        attrs.sort();
        serde_json::json!([dom.name(id), attrs, children])
    }

    /// The body of the document each HTML import call reads.
    #[test]
    #[ignore]
    fn dump_doms() {
        let calls = std::env::var("RELAYMARK_DOM_CALLS").unwrap();
        let mut out = String::new();
        for line in std::fs::read_to_string(calls).unwrap().lines() {
            // A lone surrogate has no Rust string; such an HTML call is left out.
            let Ok(call) = serde_json::from_str::<Value>(line) else {
                if line.contains(r#""fn":"document-html."#) {
                    out.push_str("null\n");
                }
                continue;
            };
            let name = call["fn"].as_str().unwrap_or_default();
            if !name.starts_with("document-html.") {
                continue;
            }
            let html = call["args"][0]["html"].as_str().unwrap_or_default();
            let wrapped = format!("<html><head></head><body>{html}</body></html>");
            let lower = html.to_ascii_lowercase();
            let whole = lower.match_indices("<html").any(|(at, _)| lower[at + 5..].starts_with(|c: char| c == '>' || is_regex_space(c)));
            let body = |text: &str| {
                let dom = Dom::parse(text);
                dom.find_descendant(dom.document(), "body").map_or(Value::Null, |b| dump(&dom, b))
            };
            let raw = if name.ends_with("importClipboardHTML") && whole { body(html) } else { body(&wrapped) };
            out.push_str(&serde_json::json!([body(&wrapped), raw]).to_string());
            out.push('\n');
        }
        std::fs::write(std::env::var("RELAYMARK_DOM_OUTPUT").unwrap(), out).unwrap();
    }
}
