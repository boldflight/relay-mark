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

const TABLE_COMMANDS: [&str; 12] = [
    "addRowBefore",
    "addRowAfter",
    "deleteRow",
    "addColumnBefore",
    "addColumnAfter",
    "deleteColumn",
    "mergeCells",
    "splitCell",
    "toggleHeaderRow",
    "toggleHeaderColumn",
    "toggleHeaderCell",
    "deleteTable",
];

/// `createContentEditCommand`: a maintained editor command over the admitted
/// document, as its steps and resulting document, selection and marks.
pub fn create_content_edit_command(document: &Value, request: &Value) -> Result<Value> {
    use crate::pm::commands::{self, State};
    use crate::pm::schema::schema;
    use crate::pm::state::Selection;
    use crate::pm::tables;

    let s = schema();
    let command = request.get("command").and_then(Value::as_str);
    let selection_json = request.get("selection").filter(|v| json::truthy(Some(v)));
    let valid_keys = request.as_object().is_some_and(|m| m.keys().all(|k| k == "command" || k == "selection"));
    let (Some(command), Some(selection_json)) = (command, selection_json) else { bail!("Invalid canonical editor command") };
    if !valid_keys || json::utf16_len(&json::stringify(request)) > 524_288 {
        bail!("Invalid canonical editor command");
    }
    let doc = admitted(document)?;
    let selection = Selection::from_json(&doc, selection_json)?;
    if json::stable_stringify(&selection.to_json()) != json::stable_stringify(selection_json) {
        bail!("Noncanonical editor selection");
    }
    let state = State { doc: doc.clone(), selection: selection.clone() };
    let cursor = selection.sel_from();
    let item = if cursor.depth >= 2 { Some(cursor.node(cursor.depth - 1).clone()) } else { None };
    let list_item = item.as_ref().filter(|i| matches!(i.type_name(), "listItem" | "taskItem")).map(Node::ty);
    let linked = |item: &Node| json::truthy(Some(item.attr("entityId")));
    let mut kind = "edit";
    let mut transaction = None;
    match command {
        "return" => {
            if let (Some(list_item), Some(item)) = (list_item, &item) {
                if cursor.parent().content().size == 0
                    && item.child_count() == 1
                    && linked(item)
                    && (cursor.depth < 4 || cursor.node(cursor.depth - 3).ty() != list_item)
                {
                    bail!("Canonical editor command refused: linked task lift");
                }
                let attrs = (s.nodes[list_item].name == "taskItem").then(|| {
                    let mut attrs = Map::new();
                    attrs.insert("checked".into(), Value::Bool(false));
                    attrs.insert("entityId".into(), Value::Null);
                    attrs
                });
                transaction = commands::split_list_item_keep_marks(&state, list_item, attrs)?;
                if transaction.is_some() {
                    kind = if cursor.parent().content().size == 0 { "exit" } else { "split" };
                }
            }
            if transaction.is_none() {
                type Command = fn(&State) -> Result<Option<crate::pm::state::Transaction>>;
                let chain: [(Command, &str); 4] = [
                    (commands::newline_in_code, "split"),
                    (commands::create_paragraph_near, "split"),
                    (commands::lift_empty_block, "exit"),
                    (commands::split_block_keep_marks, "split"),
                ];
                for (run, result_kind) in chain {
                    if let Some(tr) = run(&state)? {
                        transaction = Some(tr);
                        kind = result_kind;
                        break;
                    }
                }
            }
        }
        "sink_list_item" | "lift_list_item" => {
            if let (Some(list_item), Some(item)) = (list_item, &item) {
                if command == "lift_list_item" && linked(item) && (cursor.depth < 4 || cursor.node(cursor.depth - 3).ty() != list_item) {
                    bail!("Canonical editor command refused: linked task lift");
                }
                transaction =
                    if command == "sink_list_item" { commands::sink_list_item(&state, list_item)? } else { commands::lift_list_item(&state, list_item)? };
            }
        }
        _ => {
            if !TABLE_COMMANDS.contains(&command) {
                bail!("Unknown canonical editor command");
            }
            let mut tr = state.tr();
            if tables::table_command(command, &mut tr, &selection)? {
                transaction = Some(tr);
            }
        }
    }
    let Some(mut tr) = transaction.filter(|tr| tr.doc_changed() && tr.steps.len() <= 512) else { bail!("Canonical editor command refused") };
    if command == "return" && list_item.is_some_and(|t| s.nodes[t].name == "taskItem") && kind == "split" {
        let list_item = list_item.expect("task item");
        let selected = tr.selection()?.sel_from();
        if selected.depth >= 2 && selected.node(selected.depth - 1).ty() == list_item {
            let pos = selected.before(selected.depth - 1)?;
            let original = cursor.before(cursor.depth - 1)?;
            if pos != tr.mapping.map(original, -1) {
                let defaults = s.default_attrs(list_item).cloned().unwrap_or_default();
                for key in ["checked", "entityId"] {
                    let current = selected.node(selected.depth - 1).attr(key).clone();
                    let default = defaults.get(key).cloned().unwrap_or(Value::Null);
                    if current != default {
                        tr.set_node_attribute(pos, key, default)?;
                    }
                }
            }
        }
    }
    if kind == "edit" && command != "sink_list_item" && command != "lift_list_item" {
        if let Some(steps) = tables::fix_tables(&tr.doc.clone(), &doc)? {
            for step in steps {
                tr.step(step)?;
            }
        }
        let mut pass = 0;
        while pass < 256 && tables::remove_covered_row(&mut tr)? {
            if pass == 255 {
                bail!("Oversized covered-row normalization");
            }
            pass += 1;
        }
        if let Some(steps) = tables::fix_tables(&tr.doc.clone(), &doc)? {
            for step in steps {
                tr.step(step)?;
            }
        }
    }
    tr.doc.check()?;
    let mut retained = Map::new();
    let final_doc = tr.doc.clone();
    doc.descendants(&mut |node, pos, _, _| {
        let id = node.attr("relaymarkId");
        if !json::truthy(Some(id)) {
            return true;
        }
        let mapped = tr.mapping.map_result(pos, 1);
        if !mapped.deleted() && final_doc.node_at(mapped.pos).is_some_and(|n| n.attr("relaymarkId") == id) {
            retained.insert(json::stringify(id).trim_matches('"').to_owned(), json!(mapped.pos));
        }
        true
    });
    let stored = tr.stored_marks().cloned();
    let selection = tr.selection()?.to_json();
    Ok(json!({
        "kind": kind,
        "retained_ids": retained,
        "steps": tr.steps.iter().map(|step| step.to_json()).collect::<Vec<_>>(),
        "document": tr.doc.to_json(),
        "selection": selection,
        "stored_marks": stored.as_ref().map_or(Value::Null, |marks| Value::Array(marks.iter().map(|m| m.to_json()).collect())),
        "stored_text_attributes": stored.as_ref().map_or(Value::Null, |marks| {
            Value::Object(marks.iter().map(|m| (crate::pm::schema::schema().marks[m.ty].name.clone(), Value::Object((*m.attrs).clone()))).collect())
        }),
    }))
}
