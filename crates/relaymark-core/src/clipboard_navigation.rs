//! Clipboard paste navigation plans (clipboard-navigation.js): anchor names
//! and heading and link repairs for pasted content, as maintained steps. They
//! grant no source, donor or edit authority; the host admits the paste.

use std::collections::{HashMap, HashSet};
use std::rc::Rc;

use regex::Regex;
use serde_json::{Value, json};

use crate::controls::paper_destinations;
use crate::error::{Result, bail};
use crate::json::{self, Map};
use crate::pm::model::{Fragment, Mark, Node, Slice};
use crate::pm::schema::schema;
use crate::pm::step::{Mappable, Step, StepMap, Transform};

fn same(a: &Value, b: &Value) -> bool {
    json::stable_stringify(a) == json::stable_stringify(b)
}

fn path_key(path: &[usize]) -> String {
    json::stable_stringify(&json!(path))
}

/// `keys(value, allowed, required)`.
fn keys(value: &Value, allowed: &[&str], required: &[&str]) -> Result<()> {
    match value.as_object() {
        Some(map) if map.keys().all(|k| allowed.contains(&k.as_str())) && required.iter().all(|k| map.contains_key(*k)) => Ok(()),
        _ => bail!("Invalid causal evidence fields"),
    }
}

fn identity_pattern() -> &'static Regex {
    static PATTERN: std::sync::OnceLock<Regex> = std::sync::OnceLock::new();
    PATTERN.get_or_init(|| Regex::new("^b[0-9a-f]{32}$").expect("regex"))
}

#[derive(Clone)]
struct Entry {
    node: Node,
    position: usize,
}

struct Entries {
    ids: HashMap<String, Entry>,
    paths: HashMap<String, Entry>,
}

fn entries(doc: &Node) -> Result<Entries> {
    fn visit(node: &Node, path: &mut Vec<usize>, position: usize, out: &mut Entries, budget: &mut isize) -> Result<()> {
        *budget -= 1;
        if *budget < 0 || path.len() > 128 {
            bail!("Clipboard navigation inventory limit");
        }
        out.paths.insert(path_key(path), Entry { node: node.clone(), position });
        if let Value::String(id) = node.attr("relaymarkId") {
            if !identity_pattern().is_match(id) || out.ids.contains_key(id) {
                bail!("Invalid clipboard structural identity");
            }
            out.ids.insert(id.clone(), Entry { node: node.clone(), position });
        }
        let mut offset = position + usize::from(!path.is_empty());
        for (i, child) in node.content().iter().enumerate() {
            path.push(i);
            visit(child, path, offset, out, budget)?;
            path.pop();
            offset += child.node_size();
        }
        Ok(())
    }
    let mut out = Entries { ids: HashMap::new(), paths: HashMap::new() };
    visit(doc, &mut Vec::new(), 0, &mut out, &mut 1_000_000)?;
    Ok(out)
}

/// `comparable(node)` of placement: node JSON without generated names.
fn comparable(node: &Node) -> Value {
    let mut json = node.to_json();
    if let Some(attrs) = json.get_mut("attrs").and_then(Value::as_object_mut) {
        match node.type_name() {
            "heading" => {
                attrs.shift_remove("headingId");
            }
            "relayAnchor" => {
                attrs.shift_remove("name");
            }
            _ => {}
        }
    }
    json
}

type Lookup = Rc<dyn Fn(&[usize]) -> Result<Found>>;
/// Which batch item a source path belongs to.
type Scope = Rc<dyn Fn(&[usize]) -> Result<usize>>;

#[derive(Clone)]
struct Found {
    node: Node,
    position: usize,
    ranges: Option<Vec<(usize, usize)>>,
}

struct Placement {
    source: Node,
    indices: Vec<usize>,
    steps: Vec<Value>,
    current: Node,
    lookup: Lookup,
    retained_names: Vec<Value>,
    source_destinations: Vec<Value>,
    source_scope: Option<Scope>,
}

fn slice_geometry(fragment: &Slice) -> Result<()> {
    let maximum = Slice::max_open(fragment.content.clone(), true);
    if fragment.open_start > maximum.open_start || fragment.open_end > maximum.open_end || fragment.size() <= 0 {
        bail!("Invalid clipboard fragment geometry");
    }
    Ok(())
}

fn doc_of(content: Fragment) -> Result<Node> {
    Node::create(schema().top, None, content, Vec::new())
}

fn clipboard_placement(input: &Value) -> Result<Placement> {
    if input.get("clipboard_items").is_some_and(|v| !v.is_null()) {
        return batch_placement(input);
    }
    keys(input, &["clipboard_slice", "before_document", "steps", "source_trace"], &["clipboard_slice", "before_document", "steps"])?;
    let fragment = Slice::from_json(input.get("clipboard_slice"))?;
    let source = doc_of(fragment.content.clone())?;
    let before = Node::from_json(&input["before_document"])?;
    before.check()?;
    slice_geometry(&fragment)?;
    let steps = input["steps"].as_array().cloned();
    let Some(steps) = steps.filter(|s| source.child_count() > 0 && source.child_count() <= 4096 && !s.is_empty() && s.len() <= 512) else {
        bail!("Invalid clipboard navigation input")
    };
    let copied = Rc::new(entries(&source)?);
    let original = entries(&before)?;
    if copied.ids.keys().any(|id| original.ids.contains_key(id)) {
        bail!("Clipboard identity was not freshly allocated");
    }
    // Exact identity-attribute steps may identify a newly split target
    // heading wrapper: placement classification only, no copied ancestry.
    let mut wrappers: HashMap<String, String> = HashMap::new();
    let mut placement = Transform::new(before.clone());
    let mut current = before.clone();
    for raw in &steps {
        let prior = (raw.get("stepType") == Some(&json!("attr")) && raw.get("attr") == Some(&json!("relaymarkId")))
            .then(|| raw.get("pos").and_then(Value::as_u64).and_then(|p| current.node_at(p as usize)))
            .flatten();
        let step = Step::from_json(raw)?;
        let applied = match step.apply(&current)? {
            Ok(doc) => doc,
            Err(_) => bail!("Refused clipboard navigation Step"),
        };
        if let Some(prior) = prior.filter(|p| p.type_name() == "heading") {
            let old_id = prior.attr("relaymarkId").as_str().unwrap_or_default().to_owned();
            let original_id = wrappers.get(&old_id).cloned().unwrap_or_else(|| old_id.clone());
            let value = raw.get("value").and_then(Value::as_str);
            if let Some(retained) = original.ids.get(&original_id)
                && retained.node.type_name() == "heading"
                && !copied.ids.contains_key(&old_id)
                && let Some(value) = value
                && !copied.ids.contains_key(value)
                && !original.ids.contains_key(value)
            {
                let mapped = placement.mapping.map(retained.position, 1);
                let original_node = current.node_at(mapped);
                let mut duplicates = 0;
                current.descendants(&mut |node, _, _, _| {
                    if node.type_name() == "heading" && node.attr("relaymarkId").as_str() == Some(old_id.as_str()) {
                        duplicates += 1;
                    }
                    true
                });
                let proved = wrappers.contains_key(&old_id);
                let distinct = proved || (duplicates > 1 && same(&Value::Object((**prior.attrs()).clone()), &Value::Object((**retained.node.attrs()).clone())));
                let pos = raw["pos"].as_u64().unwrap_or_default() as usize;
                let survives = original_node.as_ref().is_some_and(|n| {
                    n.ty() == retained.node.ty() && same(&Value::Object((**n.attrs()).clone()), &Value::Object((**retained.node.attrs()).clone()))
                }) && mapped != pos;
                let next = applied.node_at(pos);
                if distinct
                    && survives
                    && next.as_ref().is_some_and(|n| {
                        n.ty() == prior.ty() && n.attr("relaymarkId").as_str() == Some(value) && n.attr("headingId") == prior.attr("headingId")
                    })
                {
                    wrappers.insert(value.to_owned(), original_id.clone());
                }
            }
        }
        placement.step(step)?;
        current = placement.doc.clone();
    }
    let traced = match input.get("source_trace") {
        None | Some(Value::Null) => None,
        Some(trace) => Some(Rc::new(source_trace(trace, &fragment, &steps, &current, false)?)),
    };
    let placed = Rc::new(entries(&current)?);
    let before_pm = before.to_json();
    let mut original_names: HashMap<String, Value> = HashMap::new();
    for entry in paper_destinations(&before_pm) {
        let path: Vec<usize> = serde_json::from_value(entry["source_path"].clone()).unwrap_or_default();
        if let Some(found) = original.paths.get(&path_key(&path))
            && let Value::String(id) = found.node.attr("relaymarkId")
        {
            original_names.insert(id.clone(), entry["name"].clone());
        }
    }
    let mut retained_names = Vec::new();
    for entry in paper_destinations(&current.to_json()) {
        let path: Vec<usize> = serde_json::from_value(entry["source_path"].clone()).unwrap_or_default();
        let actual = placed.paths.get(&path_key(&path)).expect("placed destination");
        let id = actual.node.attr("relaymarkId").as_str().map(str::to_owned);
        if id.as_ref().is_some_and(|id| copied.ids.contains_key(id)) {
            continue;
        }
        let key = if entry["kind"] == "heading" { "headingId" } else { "name" };
        match id.as_ref().and_then(|id| original.ids.get(id)) {
            Some(retained) => {
                if retained.node.ty() != actual.node.ty() || retained.node.attr(key) != actual.node.attr(key) {
                    bail!("Clipboard navigation changed retained destination");
                }
                retained_names.push(original_names.get(id.as_deref().unwrap_or_default()).cloned().unwrap_or(Value::Null));
            }
            None if entry["kind"] == "heading" && id.as_ref().is_some_and(|id| wrappers.contains_key(id)) => {
                retained_names.push(actual.node.attr("headingId").clone());
            }
            None => bail!("Clipboard navigation changed retained destination"),
        }
    }
    let lookup: Lookup = {
        let copied = copied.clone();
        let placed = placed.clone();
        let traced = traced.clone();
        Rc::new(move |path: &[usize]| {
            let Some(expected) = copied.paths.get(&path_key(path)) else { bail!("Unavailable clipboard source path") };
            let mut prefix = path.len();
            let mut ancestor = None;
            while prefix > 0 {
                if let Some(item) = copied.paths.get(&path_key(&path[..prefix]))
                    && item.node.attr("relaymarkId").is_string()
                {
                    ancestor = Some(item.clone());
                    break;
                }
                prefix -= 1;
            }
            // Inline correspondence is positional even if fitting coalesced it.
            if expected.node.is_text()
                && let Some(traced) = &traced
            {
                return traced.lookup(path, &expected.node);
            }
            let Some(ancestor) = ancestor else { bail!("Clipboard source path has no structural owner") };
            let Some(retained) = placed.ids.get(ancestor.node.attr("relaymarkId").as_str().unwrap_or_default()) else {
                bail!("Clipboard fitting removed source destination")
            };
            let (mut node, mut position) = (retained.node.clone(), retained.position);
            for &child in &path[prefix..] {
                if child >= node.child_count() {
                    bail!("Clipboard fitting changed source path");
                }
                position += 1;
                for i in 0..child {
                    position += node.child(i).node_size();
                }
                node = node.child(child).clone();
            }
            if !same(&comparable(&node), &comparable(&expected.node)) {
                bail!("Clipboard fitting changed source node");
            }
            Ok(Found { node, position, ranges: None })
        })
    };
    let source_end = fragment.content.size as isize - fragment.open_end as isize;
    let source_destinations = paper_destinations(&source.to_json())
        .into_iter()
        .filter(|entry| {
            let path: Vec<usize> = serde_json::from_value(entry["source_path"].clone()).unwrap_or_default();
            copied.paths.get(&path_key(&path)).is_some_and(|v| v.position >= fragment.open_start && (v.position as isize) < source_end)
        })
        .collect();
    Ok(Placement { indices: (0..source.child_count()).collect(), source, steps, current, lookup, retained_names, source_destinations, source_scope: None })
}

fn batch_placement(input: &Value) -> Result<Placement> {
    keys(input, &["clipboard_items", "before_document", "steps"], &["clipboard_items", "before_document", "steps"])?;
    let items_json = input["clipboard_items"].as_array().cloned();
    let Some(items_json) = items_json.filter(|i| i.len() >= 2 && i.len() <= 4096) else { bail!("Invalid clipboard item roster") };
    let before = Node::from_json(&input["before_document"])?;
    let steps_json = input["steps"].as_array().cloned();
    before.check()?;
    let Some(steps) = steps_json.filter(|s| !s.is_empty() && s.len() <= 512) else { bail!("Clipboard Step budget") };
    let mut transform = Transform::new(before.clone());
    for raw in &steps {
        transform.step(Step::from_json(raw)?)?;
    }
    let current = transform.doc.clone();
    struct Item {
        fragment: Slice,
        trace: Trace,
        offset: usize,
    }
    let mut items: Vec<Item> = Vec::new();
    let mut children: Vec<Node> = Vec::new();
    let mut offset = 0;
    let mut prior: isize = -1;
    for item in &items_json {
        keys(item, &["clipboard_slice", "source_trace", "step_index"], &["clipboard_slice", "source_trace", "step_index"])?;
        let index = item["step_index"].as_u64().filter(|_| json::is_safe_integer(&item["step_index"])).map(|i| i as isize);
        let Some(index) = index.filter(|&i| i > prior && (i as usize) < steps.len()) else { bail!("Invalid clipboard item Step order") };
        prior = index;
        let fragment = Slice::from_json(item.get("clipboard_slice"))?;
        slice_geometry(&fragment)?;
        let trace = source_trace(&item["source_trace"], &fragment, &steps[index as usize..], &current, true)?;
        children.extend(fragment.content.iter().cloned());
        let count = fragment.content.child_count();
        items.push(Item { fragment, trace, offset });
        offset += count;
    }
    if offset > 4096 {
        bail!("Clipboard item node budget");
    }
    let combined = Slice::new(doc_of(Fragment::from_array(children))?.content().clone(), 0, 0);
    let base_input = json!({"clipboard_slice": combined.to_json(), "before_document": input["before_document"], "steps": steps});
    let base = clipboard_placement(&base_input)?;
    let items = Rc::new(items);
    let owner = {
        let items = items.clone();
        move |path: &[usize]| -> Result<(usize, Vec<usize>)> {
            let Some(at) = items.iter().position(|item| path[0] >= item.offset && path[0] < item.offset + item.fragment.content.child_count()) else {
                bail!("Invalid clipboard item path")
            };
            let mut inner = vec![path[0] - items[at].offset];
            inner.extend_from_slice(&path[1..]);
            Ok((at, inner))
        }
    };
    let owner = Rc::new(owner);
    let base_lookup = base.lookup.clone();
    let lookup: Lookup = {
        let items = items.clone();
        let owner = owner.clone();
        Rc::new(move |path: &[usize]| {
            let (at, inner) = owner(path)?;
            let mut node = doc_of(items[at].fragment.content.clone())?;
            for &i in &inner {
                if i >= node.child_count() {
                    bail!("Unavailable clipboard source path");
                }
                node = node.child(i).clone();
            }
            if node.is_text() { items[at].trace.lookup(&inner, &node) } else { base_lookup(path) }
        })
    };
    let mut source_destinations = Vec::new();
    for item in items.iter() {
        let doc = doc_of(item.fragment.content.clone())?;
        let mut positions: HashMap<String, usize> = HashMap::new();
        fn visit(node: &Node, path: &mut Vec<usize>, pos: usize, out: &mut HashMap<String, usize>) {
            out.insert(path_key(path), pos);
            let mut offset = pos + usize::from(!path.is_empty());
            for (index, child) in node.content().iter().enumerate() {
                path.push(index);
                visit(child, path, offset, out);
                path.pop();
                offset += child.node_size();
            }
        }
        visit(&doc, &mut Vec::new(), 0, &mut positions);
        let end = item.fragment.content.size as isize - item.fragment.open_end as isize;
        for destination in paper_destinations(&doc.to_json()) {
            let path: Vec<usize> = serde_json::from_value(destination["source_path"].clone()).unwrap_or_default();
            let pos = positions.get(&path_key(&path)).copied().unwrap_or_default();
            if pos >= item.fragment.open_start && (pos as isize) < end {
                let mut shifted = vec![path[0] + item.offset];
                shifted.extend_from_slice(&path[1..]);
                let mut entry = destination.as_object().cloned().unwrap_or_default();
                entry.insert("source_path".into(), json!(shifted));
                source_destinations.push(Value::Object(entry));
            }
        }
    }
    let scope_owner = owner.clone();
    Ok(Placement { lookup, source_destinations, source_scope: Some(Rc::new(move |path: &[usize]| scope_owner(path).map(|(at, _)| at))), ..base })
}

/// A source trace token.
enum Token {
    Text { unit: u16, marks: Vec<Mark> },
    Leaf(Node),
    Open(Node),
    Close(Node),
}

struct TraceNode {
    source_path: Vec<usize>,
    from: usize,
    to: usize,
    content_from: usize,
    content_to: usize,
    ty: &'static str,
}

impl TraceNode {
    fn to_json(&self) -> Value {
        json!({"source_path": self.source_path, "from": self.from, "to": self.to, "content_from": self.content_from, "content_to": self.content_to, "type": self.ty})
    }
}

fn tokens(content: &Fragment) -> (Vec<Token>, Vec<TraceNode>) {
    fn walk(fragment: &Fragment, path: &[usize], start: usize, out: &mut Vec<Token>, nodes: &mut Vec<TraceNode>) {
        let mut pos = start;
        for (i, node) in fragment.iter().enumerate() {
            let mut child = path.to_vec();
            child.push(i);
            let leaf = node.is_leaf();
            nodes.push(TraceNode {
                source_path: child.clone(),
                from: pos,
                to: pos + node.node_size(),
                content_from: if leaf { pos } else { pos + 1 },
                content_to: if leaf { pos + node.node_size() } else { pos + node.node_size() - 1 },
                ty: node.type_name(),
            });
            if let Some(units) = node.text_units() {
                for &unit in units {
                    out.push(Token::Text { unit, marks: node.marks().to_vec() });
                }
            } else if leaf {
                out.push(Token::Leaf(node.clone()));
            } else {
                out.push(Token::Open(node.clone()));
                walk(node.content(), &child, pos + 1, out, nodes);
                out.push(Token::Close(node.clone()));
            }
            pos += node.node_size();
        }
    }
    let (mut out, mut nodes) = (Vec::new(), Vec::new());
    walk(content, &[], 0, &mut out, &mut nodes);
    (out, nodes)
}

struct Trace {
    nodes_by_path: HashMap<String, (usize, usize)>,
    placements: Vec<(usize, usize, usize, usize)>,
    suffix: Vec<StepMap>,
}

impl Trace {
    fn mapped_token(&self, position: usize) -> Option<usize> {
        let (mut from, mut to) = (position, position + 1);
        for map in &self.suffix {
            from = map.map_pos(from, 1);
            to = map.map_pos(to, -1);
        }
        (to == from + 1).then_some(from)
    }

    fn lookup(&self, path: &[usize], node: &Node) -> Result<Found> {
        let Some(&(source_from, source_to)) = self.nodes_by_path.get(&path_key(path)).filter(|_| node.is_text()) else {
            bail!("Unavailable clipboard traced text path")
        };
        let mut ranges: Vec<(usize, usize)> = Vec::new();
        let mut count = 0;
        for &(item_from, item_to, target_from, _) in &self.placements {
            let from = source_from.max(item_from);
            let to = source_to.min(item_to);
            if to <= from {
                continue;
            }
            for token in from..to {
                let Some(start) = self.mapped_token(target_from + token - item_from) else { bail!("Later clipboard item discarded original referenced text") };
                count += 1;
                match ranges.last_mut() {
                    Some(previous) if previous.1 == start => previous.1 = start + 1,
                    _ => ranges.push((start, start + 1)),
                }
            }
        }
        if count != node.node_size() || ranges.is_empty() {
            bail!("Clipboard fitting discarded original referenced text");
        }
        Ok(Found { node: node.clone(), position: ranges[0].0, ranges: Some(ranges) })
    }
}

/// `clipboardSourceTrace`: bind the fitter's trace to the actual original
/// fragment and steps, comparing text only at the claimed positions.
fn source_trace(trace: &Value, fragment: &Slice, steps: &[Value], current: &Node, allow_structural_suffix: bool) -> Result<Trace> {
    let s = schema();
    keys(
        trace,
        &["source_nodes", "placements", "omitted_source_tokens", "events", "step"],
        &["source_nodes", "placements", "omitted_source_tokens", "events", "step"],
    )?;
    let integer = |v: &Value| json::is_safe_integer(v) && v.as_f64().is_some_and(|n| (0.0..=1_000_000.0).contains(&n));
    let as_int = |v: &Value| v.as_f64().unwrap_or_default() as usize;
    let suffix_ok =
        steps[1..].iter().all(|raw| raw.get("stepType").and_then(Value::as_str).is_some_and(|t| ["attr", "docAttr", "addMark", "removeMark"].contains(&t)));
    if !same(&trace["step"], &steps[0]) || (!allow_structural_suffix && !suffix_ok) {
        bail!("Clipboard trace Step disagrees with placement");
    }
    let suffix = steps[1..].iter().map(|raw| Step::from_json(raw).map(|s| s.get_map())).collect::<Result<Vec<_>>>()?;
    let arr = |key: &str| trace.get(key).and_then(Value::as_array);
    let (Some(source_nodes), Some(placements_json), Some(events), Some(omitted_json)) =
        (arr("source_nodes"), arr("placements"), arr("events"), arr("omitted_source_tokens"))
    else {
        bail!("Clipboard trace resource bound")
    };
    if source_nodes.len() > 65536 || placements_json.len() > 1_000_000 || events.len() > 65536 {
        bail!("Clipboard trace resource bound");
    }
    let (original, original_nodes) = tokens(&fragment.content);
    let (target, _) = tokens(current.content());
    if original.len() > 1_000_000 || !same(&Value::Array(original_nodes.iter().map(TraceNode::to_json).collect()), &Value::Array(source_nodes.clone())) {
        bail!("Clipboard trace original path inventory changed");
    }
    let nodes_by_path: HashMap<String, &TraceNode> = original_nodes.iter().map(|n| (path_key(&n.source_path), n)).collect();
    let opening: HashMap<usize, &TraceNode> = original_nodes.iter().map(|n| (n.from, n)).collect();
    let closing: HashMap<usize, &TraceNode> = original_nodes.iter().map(|n| (n.to - 1, n)).collect();
    let mut filtered: HashMap<usize, Vec<Value>> = HashMap::new();
    let mut budget: isize = 1_000_000;
    for event in events {
        if event.get("kind") == Some(&json!("open_wrapper")) {
            keys(event, &["kind", "source_path"], &["kind", "source_path"])?;
            let path: Option<Vec<usize>> = serde_json::from_value(event["source_path"].clone()).ok();
            let node = path.and_then(|p| nodes_by_path.get(&path_key(&p)).copied());
            if node.is_none_or(|n| n.content_from == n.from) {
                bail!("Invalid clipboard opened wrapper");
            }
            continue;
        }
        let kind = event.get("kind").and_then(Value::as_str).unwrap_or_default();
        if kind == "filtered_marks" {
            keys(event, &["kind", "source_tokens", "marks"], &["kind", "source_tokens", "marks"])?;
        } else {
            keys(event, &["kind", "source_tokens"], &["kind", "source_tokens"])?;
        }
        let tokens_json = event.get("source_tokens").and_then(Value::as_array);
        let valid = ["drop_node", "empty_open_node", "filtered_marks"].contains(&kind)
            && tokens_json.is_some_and(|t| t.iter().all(|n| integer(n) && as_int(n) < original.len()));
        budget -= tokens_json.map_or(0, Vec::len) as isize;
        if !valid || budget < 0 {
            bail!("Invalid clipboard source event");
        }
        if kind == "filtered_marks" {
            let Some(marks) = event["marks"].as_array().filter(|m| m.len() <= 64) else { bail!("Invalid clipboard filtered marks") };
            for raw in marks {
                if Mark::from_json(raw)?.ty == s.mark_type("link").expect("link") {
                    bail!("Clipboard fitting discarded original link");
                }
            }
            for n in tokens_json.expect("tokens") {
                filtered.insert(as_int(n), marks.clone());
            }
        }
    }
    let partial = Trace { nodes_by_path: HashMap::new(), placements: Vec::new(), suffix: suffix.clone() };
    let mut seen = HashSet::new();
    let mut targets = HashSet::new();
    let mut prior = 0usize;
    let mut placements = Vec::new();
    let mark_json = |marks: &[Mark]| Value::Array(marks.iter().map(Mark::to_json).collect());
    let node_comparable = |node: &Node| {
        let mut attrs = (**node.attrs()).clone();
        match node.type_name() {
            "heading" => {
                attrs.shift_remove("headingId");
            }
            "relayAnchor" => {
                attrs.shift_remove("name");
            }
            _ => {}
        }
        json!({"type": node.type_name(), "attrs": attrs, "marks": mark_json(node.marks())})
    };
    let source_end = fragment.content.size as isize - fragment.open_end as isize;
    for range in placements_json {
        keys(range, &["source_from", "source_to", "target_from", "target_to"], &["source_from", "source_to", "target_from", "target_to"])?;
        let values: Vec<&Value> = range.as_object().expect("object").values().collect();
        if values.iter().any(|v| !integer(v)) {
            bail!("Invalid clipboard trace placement range");
        }
        let (sf, st, tf, tt) = (as_int(&range["source_from"]), as_int(&range["source_to"]), as_int(&range["target_from"]), as_int(&range["target_to"]));
        if st <= sf || st > original.len() || tt as isize - tf as isize != st as isize - sf as isize || tt > 1_000_000 || tf < prior {
            bail!("Invalid clipboard trace placement range");
        }
        prior = tt;
        for n in 0..st - sf {
            let s_index = sf + n;
            let t = partial.mapped_token(tf + n);
            if !seen.insert(s_index) {
                bail!("Clipboard trace duplicated source token");
            }
            let a = &original[s_index];
            let Some(t) = t else {
                if matches!(a, Token::Text { .. } | Token::Leaf(_)) {
                    bail!("Later clipboard item discarded original semantic content");
                }
                continue;
            };
            if !targets.insert(t) {
                bail!("Clipboard trace duplicated target token");
            }
            let b = target.get(t);
            match (a, b) {
                (Token::Text { unit, marks }, Some(Token::Text { unit: bu, marks: bm })) => {
                    let removed = filtered.get(&s_index).cloned().unwrap_or_default();
                    let kept: Vec<Mark> = marks.iter().filter(|m| !removed.iter().any(|raw| same(&m.to_json(), raw))).cloned().collect();
                    if unit != bu || !same(&mark_json(&kept), &mark_json(bm)) {
                        bail!("Clipboard trace text/marks changed at issued position");
                    }
                }
                (Token::Leaf(an), Some(Token::Leaf(bn))) => {
                    if !same(&node_comparable(an), &node_comparable(bn)) {
                        bail!("Clipboard trace node changed at issued position");
                    }
                }
                (Token::Open(an), Some(Token::Open(bn))) | (Token::Close(an), Some(Token::Close(bn))) => {
                    let bounds = if matches!(a, Token::Open(_)) { opening.get(&s_index) } else { closing.get(&s_index) };
                    let context = bounds.is_some_and(|b| b.from < fragment.open_start || b.to as isize > source_end);
                    if !context && !same(&node_comparable(an), &node_comparable(bn)) {
                        bail!("Clipboard trace node changed at issued position");
                    }
                }
                _ => bail!("Clipboard trace token kind changed"),
            }
        }
        placements.push((sf, st, tf, tt));
    }
    let omitted: Vec<Value> = (0..original.len()).filter(|n| !seen.contains(n)).map(|n| json!(n)).collect();
    if !same(&Value::Array(omitted.clone()), &Value::Array(omitted_json.clone())) {
        bail!("Clipboard trace incomplete omission roster");
    }
    for token in omitted.iter().map(as_int) {
        if token >= fragment.open_start && (token as isize) < source_end && matches!(original[token], Token::Text { .. } | Token::Leaf(_)) {
            bail!("Clipboard fitting discarded original semantic content");
        }
    }
    Ok(Trace { nodes_by_path: nodes_by_path.into_iter().map(|(k, n)| (k, (n.from, n.to))).collect(), placements, suffix })
}

fn destination_names(doc: &Node, out: &mut HashSet<String>) {
    doc.descendants(&mut |node, _, _, _| {
        let name = match node.type_name() {
            "relayAnchor" => node.attr("name"),
            "heading" => node.attr("headingId"),
            _ => &Value::Null,
        };
        if let Value::String(name) = name {
            out.insert(name.clone());
        }
        true
    });
}

fn path_of(entry: &Value) -> Vec<usize> {
    serde_json::from_value(entry["source_path"].clone()).unwrap_or_default()
}

/// `planClipboardAnchorAllocation`.
pub fn plan_anchor_allocation(input: &Value) -> Result<Value> {
    let placement = clipboard_placement(input)?;
    anchor_allocation(&placement)
}

fn anchor_allocation(placement: &Placement) -> Result<Value> {
    let inventory: Vec<&Value> = placement.source_destinations.iter().filter(|e| e["kind"] == "anchor").collect();
    let selected: HashSet<usize> = placement.indices.iter().copied().collect();
    let key = |entry: &Value| -> Result<String> {
        let name = json::stringify(&entry["name"]);
        Ok(match &placement.source_scope {
            Some(scope) => format!("{}:{name}", scope(&path_of(entry))?),
            None => name,
        })
    };
    let mut counts: HashMap<String, usize> = HashMap::new();
    for entry in &inventory {
        *counts.entry(key(entry)?).or_default() += 1;
    }
    let mut used: HashSet<String> = HashSet::new();
    let mut used_undefined = false;
    for name in &placement.retained_names {
        match name.as_str() {
            Some(name) => {
                used.insert(name.to_owned());
            }
            None => used_undefined = true,
        }
    }
    let _ = used_undefined;
    let mut reserved = HashSet::new();
    destination_names(&placement.current, &mut reserved);
    for entry in paper_destinations(&placement.current.to_json()) {
        if let Some(name) = entry["name"].as_str() {
            reserved.insert(name.to_owned());
        }
    }
    let mut repair = Transform::new(placement.current.clone());
    for entry in inventory {
        let path = path_of(entry);
        if !selected.contains(&path[0]) {
            continue;
        }
        if counts.get(&key(entry)?) != Some(&1) {
            bail!("Ambiguous original explicit Anchor");
        }
        let found = (placement.lookup)(&path)?;
        if found.node.type_name() != "relayAnchor" || *found.node.attr("name") != entry["name"] {
            bail!("Reviewed Anchor changed original source name");
        }
        let mut name = entry["name"].as_str().unwrap_or_default().to_owned();
        if used.contains(&name) {
            let id = found.node.attr("relaymarkId").as_str().filter(|id| identity_pattern().is_match(id));
            let Some(id) = id else { bail!("Reviewed Anchor requires allocated canonical identity") };
            let base = format!("a-{id}");
            name = base.clone();
            let mut suffix = 2;
            while reserved.contains(&name) {
                name = format!("{base}-{suffix}");
                suffix += 1;
            }
            if name.chars().map(char::len_utf16).sum::<usize>() > 128 {
                bail!("Reviewed Anchor name limit");
            }
            repair.set_node_attribute(found.position, "name", json!(name))?;
            reserved.insert(name.clone());
        }
        used.insert(name);
    }
    if placement.steps.len() + repair.steps.len() > 512 {
        bail!("Reviewed navigation Step limit");
    }
    Ok(json!({
        "steps": repair.steps.iter().map(Step::to_json).collect::<Vec<_>>(),
        "document": repair.doc.to_json(),
        "retained_destination_names": placement.retained_names,
    }))
}

/// `planClipboardHeadingNavigation`.
pub fn plan_heading_navigation(input: &Value) -> Result<Value> {
    let placement = clipboard_placement(input)?;
    let is_anchor_step = |step: &Value| step.get("stepType") == Some(&json!("attr")) && step.get("attr") == Some(&json!("name"));
    let anchor_steps: Vec<Value> = placement.steps.iter().filter(|s| is_anchor_step(s)).cloned().collect();
    let mut without = input.as_object().cloned().unwrap_or_default();
    without.insert("steps".into(), Value::Array(placement.steps.iter().filter(|s| !is_anchor_step(s)).cloned().collect()));
    let allocation = anchor_allocation(&clipboard_placement(&Value::Object(without))?)?;
    if !same(&allocation["steps"], &Value::Array(anchor_steps)) {
        bail!("Reviewed Anchor name Steps disagree with original collision");
    }
    let selected: HashSet<usize> = placement.indices.iter().copied().collect();
    let inventory = &placement.source_destinations;
    let mut final_names = HashSet::new();
    let mut ambiguous = false;
    placement.current.descendants(&mut |node, _, _, _| {
        let name = match node.type_name() {
            "heading" => node.attr("headingId"),
            "relayAnchor" => node.attr("name"),
            _ => &Value::Null,
        };
        if let Value::String(name) = name
            && !final_names.insert(name.clone())
        {
            ambiguous = true;
        }
        true
    });
    if ambiguous {
        bail!("Ambiguous reviewed destination");
    }
    static NAME: std::sync::OnceLock<Regex> = std::sync::OnceLock::new();
    let name_pattern = NAME.get_or_init(|| Regex::new("^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$").expect("regex"));
    let mut destinations: Vec<Value> = Vec::new();
    for entry in inventory {
        let path = path_of(entry);
        if !selected.contains(&path[0]) {
            continue;
        }
        let found = (placement.lookup)(&path)?;
        let name = if entry["kind"] == "heading" { found.node.attr("headingId") } else { found.node.attr("name") };
        let Some(name) = name.as_str().filter(|n| name_pattern.is_match(n)) else { bail!("Unavailable reviewed destination") };
        destinations.push(json!({"source_path": path, "kind": entry["kind"], "source_name": entry["name"], "destination_name": name}));
    }
    let mut all_references: Vec<Value> = Vec::new();
    fn walk(node: &Node, path: &mut Vec<usize>, out: &mut Vec<Value>) {
        if let Some(Value::String(href)) =
            node.marks().iter().find(|m| schema().marks[m.ty].name == "link").map(|m| m.attrs.get("href").cloned().unwrap_or(Value::Null))
            && href.starts_with('#')
        {
            out.push(json!({"source_path": path, "kind": "link", "source_target": href}));
        }
        if node.type_name() == "relayButton" && node.attr("kind") == "anchor" {
            out.push(json!({"source_path": path, "kind": "button", "source_target": node.attr("target")}));
        }
        for (i, child) in node.content().iter().enumerate() {
            path.push(i);
            walk(child, path, out);
            path.pop();
        }
    }
    walk(&placement.source, &mut Vec::new(), &mut all_references);
    let mut repair = Transform::new(placement.current.clone());
    let mut references: Vec<Value> = Vec::new();
    for reference in &all_references {
        let path = path_of(reference);
        if !selected.contains(&path[0]) {
            continue;
        }
        let source_target = reference["source_target"].clone();
        let mut name = source_target.clone();
        if reference["kind"] == "link" {
            let text = source_target.as_str().unwrap_or_default();
            match crate::links::decode_uri_component(&text[1..]) {
                Some(decoded) => name = json!(decoded),
                None => bail!("Malformed original navigation fragment"),
            }
        }
        let mut original = Vec::new();
        for entry in inventory.iter() {
            if entry["name"] != name {
                continue;
            }
            if let Some(scope) = &placement.source_scope
                && scope(&path_of(entry))? != scope(&path)?
            {
                continue;
            }
            original.push(entry);
        }
        if original.len() != 1 {
            bail!("Unresolved or ambiguous original navigation destination");
        }
        let Some(destination) = destinations.iter().find(|d| same(&d["source_path"], &original[0]["source_path"]) && d["kind"] == original[0]["kind"]) else {
            bail!("Original navigation destination was not selected")
        };
        let target = if destination["destination_name"] == destination["source_name"] {
            source_target.clone()
        } else {
            json!(format!("{}{}", if reference["kind"] == "link" { "#" } else { "" }, destination["destination_name"].as_str().unwrap_or_default()))
        };
        let mut with_target = reference.as_object().cloned().unwrap_or_default();
        with_target.insert("destination_target".into(), target.clone());
        references.push(Value::Object(with_target));
        let found = (placement.lookup)(&path)?;
        if reference["kind"] == "link" {
            let mark = found.node.marks().iter().find(|m| schema().marks[m.ty].name == "link").cloned();
            if !found.node.is_inline() || mark.as_ref().map(|m| m.attrs.get("href").cloned().unwrap_or(Value::Null)) != Some(source_target.clone()) {
                bail!("Reviewed navigation changed original link");
            }
            let mark = mark.expect("link mark");
            if target != source_target {
                let ranges = found.ranges.clone().unwrap_or_else(|| vec![(found.position, found.position + found.node.node_size())]);
                for (from, to) in ranges {
                    repair.remove_mark(from, to, Some(&mark), None)?;
                    let mut attrs: Map = (*mark.attrs).clone();
                    attrs.insert("href".into(), target.clone());
                    repair.add_mark(from, to, &Mark::new(mark.ty, Some(&attrs))?)?;
                }
            }
        } else {
            if found.node.type_name() != "relayButton" || found.node.attr("kind") != "anchor" || *found.node.attr("target") != source_target {
                bail!("Reviewed navigation changed original button");
            }
            if target != source_target {
                repair.set_node_attribute(found.position, "target", target)?;
            }
        }
    }
    if placement.steps.len() + repair.steps.len() > 512 {
        bail!("Reviewed navigation Step limit");
    }
    if destinations.len() > 4096 || references.len() > 4096 {
        bail!("Reviewed navigation correspondence limit");
    }
    let inventory_hash = json::canonical_sha256(&json!({"destinations": inventory, "references": all_references}));
    Ok(json!({
        "steps": repair.steps.iter().map(Step::to_json).collect::<Vec<_>>(),
        "document": repair.doc.to_json(),
        "navigation_correspondence": {"source_inventory_sha256": inventory_hash, "destinations": destinations, "references": references},
    }))
}
