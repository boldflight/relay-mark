//! Draft Tasks: which unlinked checklist items a person started on purpose
//! ("armed"), when one is finished, and what each would create. Every RelayMark
//! editor decides this the same way; spec/relaymark/editor/task-drafts-v1.json
//! holds the cases.
//!
//! The armed set is the client's local state and never enters the document:
//! received, pasted and historical checklists never create Tasks on their own.
//! Callers pass the set in and get the next one back. The Yjs anchor for a
//! finished draft belongs to the platform, which owns the live binding.

use std::collections::HashSet;

use serde_json::{Value, json};

use crate::error::{Result, bail};
use crate::json;
use crate::pm::model::Node;

/// One unlinked or linked task item with a well-formed block identity.
struct Item {
    block_id: String,
    pos: usize,
    path: Vec<usize>,
    linked: bool,
    /// The first paragraph's exact text and its node size.
    text: String,
    title_size: usize,
    done: bool,
    parent_entity_id: Option<String>,
}

impl Item {
    fn title(&self) -> &str {
        json::js_trim(&self.text)
    }

    /// The web's `activeTaskDraft`: the caret is in the item's first paragraph.
    fn holds(&self, caret: usize) -> bool {
        caret > self.pos && caret <= self.pos + 1 + self.title_size
    }
}

/// `taskDrafts`: every unlinked task item with a well-formed block identity.
pub fn drafts(document: &Value, options: &Value) -> Result<Value> {
    let armed = armed_option(options)?;
    let drafts = items(document)?
        .into_iter()
        .filter(|item| !item.linked)
        .map(|item| {
            json!({
                "block_id": item.block_id,
                "operation_id": operation_id(&item.block_id),
                "title": item.title(),
                "text": item.text,
                "done": item.done,
                "intent": if armed.contains(&item.block_id) { "authored" } else { "local" },
                "parent_entity_id": item.parent_entity_id,
                "path": item.path,
            })
        })
        .collect();
    Ok(Value::Array(drafts))
}

/// The armed set after an editing event, from the documents before and after it.
pub fn arm(documents: &Value, options: &Value) -> Result<Value> {
    let Some([before, after]) = documents.as_array().map(Vec::as_slice).and_then(|pair| <&[Value; 2]>::try_from(pair).ok()) else {
        bail!("Expected the documents before and after the event");
    };
    let mut armed = armed_option(options)?;
    let event = options.get("event").unwrap_or(&Value::Null);
    let ids = || -> Result<HashSet<String>> {
        let Some(ids) = event.get("ids").and_then(Value::as_array) else { bail!("Invalid task draft event") };
        ids.iter().map(|id| id.as_str().map(str::to_owned).ok_or_else(|| crate::Error::new("Invalid task draft event"))).collect()
    };
    let after = items(after)?;
    // New items are those that were no task item before; the platform assigns
    // identity to new blocks, so a split or conversion gives each a fresh id.
    let new = || -> Result<Vec<&Item>> {
        let earlier: HashSet<String> = items(before)?.into_iter().map(|item| item.block_id).collect();
        Ok(after.iter().filter(|item| !item.linked && !earlier.contains(&item.block_id)).collect())
    };
    match event.get("kind").and_then(Value::as_str) {
        Some("input_rule") => armed.extend(new()?.into_iter().map(|item| item.block_id.clone())),
        // Converting lines that already have text makes local checklist items.
        Some("command") => armed.extend(new()?.into_iter().filter(|item| item.title().is_empty()).map(|item| item.block_id.clone())),
        Some("split") => {
            let Some(from) = event.get("from").and_then(Value::as_str) else { bail!("Invalid task draft event") };
            if armed.contains(from) && after.iter().any(|item| item.block_id == from && !item.linked) {
                armed.extend(new()?.into_iter().map(|item| item.block_id.clone()));
            }
        }
        Some("arm") => armed.extend(ids()?),
        Some("disarm") => {
            let ids = ids()?;
            armed.retain(|id| !ids.contains(id));
        }
        // A remote change, paste or history step only prunes.
        Some("external") => {}
        _ => bail!("Invalid task draft event"),
    }
    let armed: Vec<&str> = after.iter().filter(|item| !item.linked && armed.contains(&item.block_id)).map(|item| item.block_id.as_str()).collect();
    Ok(json!({ "armed": armed }))
}

/// The armed drafts with a title that a key press, caret move or checkbox tap finishes.
pub fn boundary(document: &Value, options: &Value) -> Result<Value> {
    let armed = armed_option(options)?;
    let drafts: Vec<Item> = items(document)?.into_iter().filter(|item| !item.linked).collect();
    let finished = |item: &&Item| armed.contains(&item.block_id) && !item.title().is_empty();
    let caret = |key: &str| -> Result<Option<&Item>> {
        let Some(caret) = options.get(key).and_then(Value::as_u64) else { bail!("Invalid task draft boundary") };
        Ok(drafts.iter().find(|item| item.holds(caret as usize)))
    };
    // Return while an input method is composing confirms the composition only.
    if json::truthy(options.get("composing")) {
        return Ok(json!([]));
    }
    let done = match options.get("key").and_then(Value::as_str) {
        Some("return") => caret("before")?.filter(finished),
        Some("move") => {
            let left = caret("before")?;
            let entered = caret("after")?;
            left.filter(|item| entered.is_none_or(|other| other.block_id != item.block_id)).filter(finished)
        }
        Some("checkbox") => {
            let Some(block) = options.get("block").and_then(Value::as_str) else { bail!("Invalid task draft boundary") };
            drafts.iter().find(|item| item.block_id == block).filter(finished)
        }
        _ => bail!("Invalid task draft boundary"),
    };
    Ok(json!(done.map(|item| vec![item.block_id.as_str()]).unwrap_or_default()))
}

fn armed_option(options: &Value) -> Result<HashSet<String>> {
    match options.get("armed") {
        None | Some(Value::Null) => Ok(HashSet::new()),
        Some(Value::Array(ids)) => ids.iter().map(|id| id.as_str().map(str::to_owned).ok_or_else(|| crate::Error::new("Invalid armed task drafts"))).collect(),
        Some(_) => bail!("Invalid armed task drafts"),
    }
}

/// Every task item with a well-formed block identity, in document order.
fn items(document: &Value) -> Result<Vec<Item>> {
    let doc = Node::from_json(document)?;
    doc.check()?;
    let mut found = Vec::new();
    visit(&doc, 0, &mut Vec::new(), &mut Vec::new(), &mut found);
    Ok(found)
}

fn visit<'d>(node: &'d Node, content_start: usize, path: &mut Vec<usize>, ancestors: &mut Vec<&'d Node>, found: &mut Vec<Item>) {
    let mut pos = content_start;
    for index in 0..node.child_count() {
        let child = node.child(index);
        path.push(index);
        if child.type_name() == "taskItem"
            && let Some(block_id) = child.attr("relaymarkId").as_str().filter(|id| well_formed(id))
        {
            let first = child.first_child();
            found.push(Item {
                block_id: block_id.to_owned(),
                pos,
                path: path.clone(),
                linked: json::truthy(Some(child.attr("entityId"))),
                text: first.map(Node::text_content).unwrap_or_default(),
                title_size: first.map_or(0, Node::node_size),
                done: json::truthy(Some(child.attr("checked"))),
                parent_entity_id: parent(ancestors),
            });
        }
        if !child.is_textblock() && !child.is_leaf() {
            ancestors.push(child);
            visit(child, pos + 1, path, ancestors, found);
            ancestors.pop();
        }
        path.pop();
        pos += child.node_size();
    }
}

/// The web's `taskParentId`: the nearest enclosing linked task item, or the
/// last Task reference in an enclosing list item's first paragraph.
fn parent(ancestors: &[&Node]) -> Option<String> {
    for node in ancestors.iter().rev() {
        let entity = |value: &Value| value.as_str().filter(|id| !id.is_empty()).map(str::to_owned);
        if node.type_name() == "taskItem"
            && let Some(id) = entity(node.attr("entityId"))
        {
            return Some(id);
        }
        if matches!(node.type_name(), "taskItem" | "listItem") {
            let mut reference = None;
            if let Some(first) = node.first_child() {
                first.descendants(&mut |child, _, _, _| {
                    if child.type_name() == "relayReference" && child.attr("entityType").as_str().is_some_and(|kind| kind.eq_ignore_ascii_case("task")) {
                        reference = entity(child.attr("entityId"));
                    }
                    true
                });
            }
            if reference.is_some() {
                return reference;
            }
        }
    }
    None
}

/// `b` and 32 lowercase hexadecimal digits, as editors assign block identity.
fn well_formed(id: &str) -> bool {
    id.len() == 33 && id.starts_with('b') && id[1..].bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

/// The web's `taskOperationId`: the block identity as a lowercase UUID, the
/// server's idempotency key for the draft's creation.
fn operation_id(block_id: &str) -> String {
    let hex = &block_id[1..];
    format!("{}-{}-{}-{}-{}", &hex[0..8], &hex[8..12], &hex[12..16], &hex[16..20], &hex[20..32])
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    /// spec/relaymark/editor/task-drafts-v1.json, the cases the web editor passes too,
    /// run by job name as Swift and the Elixir NIF call them.
    #[test]
    fn every_shared_case() {
        let fixture: Value = serde_json::from_str(include_str!("../../../spec/relaymark/editor/task-drafts-v1.json")).expect("fixture");
        let mut failures = Vec::new();
        for case in fixture["cases"].as_array().expect("cases") {
            let name = case["name"].as_str().expect("name");
            let job = case["job"].as_str().expect("job");
            let input = serde_json::to_vec(&case["input"]).expect("input");
            let options = serde_json::to_vec(&case["options"]).expect("options");
            match crate::jobs::run(job, &input, &options) {
                Ok(bytes) => {
                    let value: Value = serde_json::from_slice(&bytes).expect("job output");
                    if value != case["expected"] {
                        failures.push(format!("{name}: {value}"));
                    }
                }
                Err(error) => failures.push(format!("{name}: {error}")),
            }
        }
        assert!(failures.is_empty(), "{}", failures.join("\n"));
    }

    /// A block an editor has not identified yet has no draft and no fallback
    /// idempotency key. Editors assign identity before asking, so this stays
    /// out of the shared cases.
    #[test]
    fn an_unidentified_item_has_no_draft() {
        let document = serde_json::json!({"type": "doc", "content": [{"type": "taskList", "content": [
            {"type": "taskItem", "attrs": {"relaymarkId": null}, "content": [{"type": "paragraph", "content": [{"type": "text", "text": "No id"}]}]}
        ]}]});
        assert_eq!(super::drafts(&document, &Value::Null).expect("drafts"), serde_json::json!([]));
    }
}
