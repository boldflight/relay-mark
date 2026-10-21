//! The native editing runtime (content-edit.js and content-edit-write.js):
//! canonical step application with its causal identity ranges, the
//! ProseMirror-to-Yjs text write plan, and editor commands. The host supplies
//! its admitted document; no persistence, transport or authority lives here.

use std::collections::HashMap;

use serde_json::{Value, json};

use crate::adapter::{assert_authored_metadata, to_relaymark};
use crate::error::{Result, bail};
use crate::json::{self, Map};
use crate::pm::model::Node;
use crate::pm::step::{Step, StepMap};

/// A source range retained at a destination.
#[derive(Clone, Copy, Debug)]
pub struct Range {
    pub source_from: usize,
    pub destination_from: usize,
    pub length: usize,
}

impl Range {
    fn to_json(self) -> Value {
        json!({"source_from": self.source_from, "destination_from": self.destination_from, "length": self.length})
    }
}

pub struct Applied {
    pub json: Value,
    pub authored: Value,
    pub step_maps: Vec<StepMap>,
    pub retained: Vec<Range>,
    pub inserted: Vec<(usize, usize)>,
    pub copied: Vec<Range>,
}

impl Applied {
    pub fn to_json(&self) -> Value {
        json!({
            "document": self.json,
            "authored_document": self.authored,
            "step_maps": self.step_maps.iter().map(|m| json!({"ranges": m.ranges, "inverted": m.inverted})).collect::<Vec<_>>(),
            "retained_ranges": self.retained.iter().map(|r| r.to_json()).collect::<Vec<_>>(),
            "inserted_ranges": self.inserted.iter().map(|(d, l)| json!({"destination_from": d, "length": l})).collect::<Vec<_>>(),
            "copied_subtree_ranges": self.copied.iter().map(|r| r.to_json()).collect::<Vec<_>>(),
        })
    }
}

/// An admitted editor document: its authored grammar and ProseMirror checks.
pub fn admitted(document: &Value) -> Result<Node> {
    // Validate original attributes before Node.fromJSON can fill defaults.
    to_relaymark(document)?;
    let node = Node::from_json(document)?;
    node.check()?;
    Ok(node)
}

/// `applyContentEdit`.
pub fn apply_content_edit(document: &Value, operation: &Value, maximum_steps: usize) -> Result<Applied> {
    let steps = operation.get("steps").and_then(Value::as_array);
    let Some(steps) = steps.filter(|steps| operation.get("kind") == Some(&json!("content_edit")) && !steps.is_empty() && steps.len() <= maximum_steps) else {
        bail!("Invalid or oversized canonical content edit");
    };
    if operation.get("group").is_some() || operation.get("history").is_some() {
        bail!("Unsupported content edit envelope");
    }
    let mut doc = admitted(document)?;
    let mut step_maps = Vec::new();
    let mut originals: HashMap<String, (Node, usize)> = HashMap::new();
    let mut duplicate = false;
    doc.descendants(&mut |node, position, _, _| {
        if let Some(id) = node.attr("relaymarkId").as_str().filter(|id| !id.is_empty()) {
            if originals.contains_key(id) {
                duplicate = true;
            }
            originals.insert(id.to_owned(), (node.clone(), position));
        }
        true
    });
    if duplicate {
        bail!("Ambiguous retained subtree identity");
    }
    let mut copied: Vec<Range> = Vec::new();
    let size = doc.content().size;
    let mut retained: Vec<Range> = if size > 0 { vec![Range { source_from: 0, destination_from: 0, length: size }] } else { Vec::new() };
    for raw in steps {
        if raw.get("stepType") == Some(&json!("docAttr")) {
            if raw.get("attr") != Some(&json!("relaymark")) {
                bail!("Unknown canonical document attribute");
            }
            assert_authored_metadata(raw.get("value").unwrap_or(&Value::Null))?;
        }
        let step = Step::from_json(raw)?;
        // Never quietly drop unknown slice, mark, node or step attributes.
        if json::stable_stringify(&step.to_json()) != json::stable_stringify(raw) {
            bail!("Noncanonical content edit step");
        }
        doc = match step.apply(&doc)? {
            Ok(next) => next,
            Err(failed) => bail!("Canonical content edit refused: {failed}"),
        };
        let map = step.get_map();
        let mut changed: Vec<(usize, usize)> = Vec::new();
        map.for_each(&mut |from, to, _, _| changed.push((from, to)));
        copied = map_ranges(&copied, &map, &changed)?;
        // A preserved identity is a source pointer only for its complete exact
        // original subtree, at a destination that holds that subtree.
        let mut candidates: Vec<Range> = Vec::new();
        if let Step::Replace { from, slice, .. } = &step
            && slice.content.size > 0
        {
            slice.content.descendants(&mut |node, pos, _, _| {
                let id = node.attr("relaymarkId").as_str().filter(|id| !id.is_empty());
                let Some((original, position)) = id.and_then(|id| originals.get(id)) else { return true };
                if !node.eq(original) {
                    return true;
                }
                let destination = (*from + pos) as isize - slice.open_start as isize;
                if destination < 0 || !doc.node_at(destination as usize).is_some_and(|at| at.eq(node)) {
                    return true;
                }
                let destination = destination as usize;
                if candidates.iter().any(|r| destination >= r.destination_from && destination + node.node_size() <= r.destination_from + r.length) {
                    return false;
                }
                candidates.push(Range { source_from: *position, destination_from: destination, length: node.node_size() });
                false
            });
        }
        copied.extend(candidates);
        if copied.len() > 65536 {
            bail!("Copied subtree mapping budget exceeded");
        }
        retained = map_ranges(&retained, &map, &changed)?;
        step_maps.push(map);
    }
    doc.check()?;
    let document_json = doc.to_json();
    let authored = to_relaymark(&document_json)?;
    let mut sorted = retained.clone();
    sorted.sort_by_key(|r| r.destination_from);
    let mut inserted = Vec::new();
    let mut cursor = 0;
    for range in sorted {
        if range.destination_from > cursor {
            inserted.push((cursor, range.destination_from - cursor));
        }
        cursor = cursor.max(range.destination_from + range.length);
    }
    if cursor < doc.content().size {
        inserted.push((cursor, doc.content().size - cursor));
    }
    Ok(Applied { json: document_json, authored, step_maps, retained, inserted, copied })
}

/// Maps retained ranges through one step map, splitting them at every
/// changed boundary and dropping what the step replaced.
fn map_ranges(ranges: &[Range], map: &StepMap, changed: &[(usize, usize)]) -> Result<Vec<Range>> {
    let mut next: Vec<Range> = Vec::new();
    for range in ranges {
        let start = range.destination_from;
        let end = start + range.length;
        let mut boundaries = vec![start, end];
        for &(from, to) in changed {
            for p in [from, to] {
                if p > start && p < end {
                    boundaries.push(p);
                }
            }
        }
        boundaries.sort_unstable();
        for pair in boundaries.windows(2) {
            let (from, to) = (pair[0], pair[1]);
            if from == to || changed.iter().any(|&(a, b)| a < b && from >= a && to <= b) {
                continue;
            }
            let destination = map.map(from, 1);
            let upper = map.map(to, -1);
            if upper as isize - destination as isize != (to - from) as isize {
                bail!("Unprovable maintained map interval");
            }
            let source = range.source_from + from - start;
            match next.last_mut() {
                Some(last) if last.source_from + last.length == source && last.destination_from + last.length == destination => last.length += to - from,
                _ => next.push(Range { source_from: source, destination_from: destination, length: to - from }),
            }
            if next.len() > 65536 {
                bail!("Content edit causal mapping budget exceeded");
            }
        }
    }
    Ok(next)
}

/// `contentEditTextGroups`: each parent's runs of text, by identity.
struct TextGroup {
    parent: Value,
    index: usize,
    position: usize,
    text: Vec<u16>,
}

fn text_groups(document: &Node) -> Vec<TextGroup> {
    fn visit(node: &Node, position: isize, groups: &mut Vec<TextGroup>) {
        let mut group_index = 0;
        let mut open: Option<usize> = None;
        let mut offset = 0;
        for child in node.content().iter() {
            let start = (if node.type_name() == "doc" { 0 } else { position + 1 }) as usize + offset;
            if let Some(text) = child.text_units() {
                let index = *open.get_or_insert_with(|| {
                    groups.push(TextGroup { parent: node.attr("relaymarkId").clone(), index: group_index, position: start, text: Vec::new() });
                    group_index += 1;
                    groups.len() - 1
                });
                groups[index].text.extend_from_slice(text);
            } else {
                open = None;
                visit(child, start as isize, groups);
                group_index += 1;
            }
            offset += child.node_size();
        }
        if node.inline_content() && node.content().size == 0 {
            groups.push(TextGroup { parent: node.attr("relaymarkId").clone(), index: 0, position: (position + 1) as usize, text: Vec::new() });
        }
    }
    let mut groups = Vec::new();
    visit(document, -1, &mut groups);
    groups
}

/// `group.parent + ':' + group.index` as JavaScript concatenates it.
fn group_key(parent: &Value, index: usize) -> String {
    let parent = match parent {
        Value::String(s) => s.clone(),
        Value::Null => "null".to_owned(),
        other => json::stringify(other),
    };
    format!("{parent}:{index}")
}

fn groups_json(document: &Node) -> Map {
    let mut out = Map::new();
    for group in text_groups(document) {
        out.insert(
            group_key(&group.parent, group.index),
            json!({"parent": group.parent, "index": group.index, "position": group.position, "text": String::from_utf16_lossy(&group.text)}),
        );
    }
    out
}

/// `prepareContentEditWrite`: the causal writer's plan, after checking that
/// the steps' actual result is `after`.
pub fn prepare_content_edit_write(before: &Value, steps: &Value, after: &Value) -> Result<Value> {
    let operation = json!({"kind": "content_edit", "steps": steps});
    let expected = apply_content_edit(before, &operation, 512)?;
    if json::stable_stringify(&expected.json) != json::stable_stringify(after) {
        bail!("Causal writer result disagrees with actual steps");
    }
    let before_node = Node::from_json(before)?;
    let after_node = Node::from_json(after)?;
    let before_groups = groups_json(&before_node);
    let after_groups = groups_json(&after_node);
    let retained = &expected.retained;
    let mut causal: Vec<Value> = Vec::new();
    for target in after_groups.values() {
        let key = group_key(&target["parent"], target["index"].as_u64().unwrap_or_default() as usize);
        let source = before_groups.get(&key);
        let text_len = |g: &Value| crate::pm::model::utf16_len(g["text"].as_str().unwrap_or_default());
        let position = |g: &Value| g["position"].as_u64().unwrap_or_default() as usize;
        let mut kept = false;
        if let Some(source) = source
            && text_len(source) == text_len(target)
        {
            if text_len(source) == 0 {
                kept = true;
            } else {
                let lower = retained.partition_point(|r| r.source_from + r.length <= position(source));
                kept = retained.get(lower).is_some_and(|r| {
                    r.source_from <= position(source)
                        && r.source_from + r.length >= position(source) + text_len(source)
                        && r.destination_from + position(source) - r.source_from == position(target)
                });
            }
        }
        if !kept && !causal.contains(&target["parent"]) {
            causal.push(target["parent"].clone());
        }
    }
    Ok(json!({
        "retained_ranges": retained.iter().map(|r| r.to_json()).collect::<Vec<_>>(),
        "before_groups": before_groups,
        "after_groups": after_groups,
        "causal_targets": causal,
    }))
}

/// JavaScript `String(value)` for a key part.
fn key_part(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Number(n) => json::number_string(n),
        Value::Null => "null".into(),
        Value::Bool(b) => b.to_string(),
        Value::Array(items) => items.iter().map(|v| if v.is_null() { String::new() } else { key_part(v) }).collect::<Vec<_>>().join(","),
        Value::Object(_) => "[object Object]".into(),
    }
}

fn surrogate_boundary(text: &[u16], offset: usize) -> Result<()> {
    if offset > 0 && offset < text.len() && (0xd800..=0xdbff).contains(&text[offset - 1]) && (0xdc00..=0xdfff).contains(&text[offset]) {
        bail!("Causal writer boundary splits Unicode");
    }
    Ok(())
}

fn safe_integer(value: &Value) -> Option<i64> {
    json::is_safe_integer(value).then(|| value.as_f64().unwrap_or_default() as i64)
}

/// `planContentEditTextWrite`: the Yjs delta that turns a source text group
/// into a target one, retaining exactly what the steps retained.
pub fn plan_text_write(
    prepared: &Value,
    source_parent: &Value,
    source_group: &Value,
    target_parent: &Value,
    target_group: &Value,
    span: Option<&Value>,
) -> Result<Value> {
    let group = |groups: &str, parent: &Value, index: &Value| -> Option<(usize, Vec<u16>)> {
        let found = prepared.get(groups)?.get(format!("{}:{}", key_part(parent), key_part(index)))?;
        if !json::truthy(Some(found)) {
            return None;
        }
        let position = found.get("position")?.as_f64()? as usize;
        let text = found.get("text").and_then(Value::as_str).unwrap_or_default().encode_utf16().collect();
        Some((position, text))
    };
    let (Some(mut source), Some(target)) = (group("before_groups", source_parent, source_group), group("after_groups", target_parent, target_group)) else {
        bail!("Causal writer text group unavailable");
    };
    if let Some(span) = span {
        let fields = span.as_object().map(|m| {
            let mut keys: Vec<&String> = m.keys().collect();
            keys.sort();
            keys.iter().map(|k| k.as_str()).collect::<Vec<_>>().join(",")
        });
        let offset = span.get("offset").and_then(safe_integer);
        let length = span.get("length").and_then(safe_integer);
        let (Some(offset), Some(length)) = (offset, length) else { bail!("Invalid causal source branch span") };
        if fields.as_deref() != Some("length,offset") || offset < 0 || length < 0 || (offset + length) as usize > source.1.len() {
            bail!("Invalid causal source branch span");
        }
        let (offset, length) = (offset as usize, length as usize);
        surrogate_boundary(&source.1, offset)?;
        surrogate_boundary(&source.1, offset + length)?;
        source = (source.0 + offset, source.1[offset..offset + length].to_vec());
    }
    let ranges: Vec<Range> = prepared
        .get("retained_ranges")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .map(|r| Range {
                    source_from: r["source_from"].as_u64().unwrap_or_default() as usize,
                    destination_from: r["destination_from"].as_u64().unwrap_or_default() as usize,
                    length: r["length"].as_u64().unwrap_or_default() as usize,
                })
                .collect()
        })
        .unwrap_or_default();
    let (source_pos, source_text) = (source.0 as isize, &source.1);
    let (target_pos, target_text) = (target.0 as isize, &target.1);
    let lower = ranges.partition_point(|r| ((r.source_from + r.length) as isize) <= source_pos);
    // (source offset, target offset, count)
    let mut kept: Vec<(isize, isize, isize)> = Vec::new();
    for range in &ranges[lower..] {
        let (sf, df, len) = (range.source_from as isize, range.destination_from as isize, range.length as isize);
        if sf >= source_pos + source_text.len() as isize {
            break;
        }
        let from = sf.max(source_pos).max(sf + target_pos - df);
        let to = (sf + len).min(source_pos + source_text.len() as isize).min(sf + target_pos + target_text.len() as isize - df);
        if from < to {
            kept.push((from - source_pos, df + from - sf - target_pos, to - from));
        }
    }
    kept.sort_by_key(|k| k.1);
    let mut delta: Vec<Value> = Vec::new();
    let (mut from, mut to) = (0isize, 0isize);
    let gaps = |delta: &mut Vec<Value>, from: isize, to: isize, next_source: isize, next_target: isize| -> Result<()> {
        surrogate_boundary(source_text, from as usize)?;
        surrogate_boundary(source_text, next_source as usize)?;
        surrogate_boundary(target_text, to as usize)?;
        surrogate_boundary(target_text, next_target as usize)?;
        if next_source < from || next_target < to {
            bail!("Causal writer retention order disagrees");
        }
        if next_source > from {
            delta.push(json!({"delete": next_source - from}));
        }
        if next_target > to {
            delta.push(json!({"insert": String::from_utf16_lossy(&target_text[to as usize..next_target as usize])}));
        }
        Ok(())
    };
    for (source_offset, target_offset, count) in kept {
        gaps(&mut delta, from, to, source_offset, target_offset)?;
        surrogate_boundary(source_text, (source_offset + count) as usize)?;
        surrogate_boundary(target_text, (target_offset + count) as usize)?;
        let (s, t, c) = (source_offset as usize, target_offset as usize, count as usize);
        if source_text[s..s + c] != target_text[t..t + c] {
            bail!("Causal writer retained contents disagree");
        }
        delta.push(json!({"retain": count}));
        from = source_offset + count;
        to = target_offset + count;
    }
    gaps(&mut delta, from, to, source_text.len() as isize, target_text.len() as isize)?;
    Ok(Value::Array(delta))
}
