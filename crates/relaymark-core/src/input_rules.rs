//! Typed Markdown shortcuts ("input rules"): `- ` starts a bullet list, `[ ] `
//! a checklist, `**bold**` makes bold text, and so on. Every RelayMark editor
//! applies the same rules: the web editor through TipTap's own input rules,
//! native editors through this module. spec/relaymark/editor/input-rules-v1.json
//! holds the cases both must pass, so a rule one editor lacks fails a test.
//!
//! Each rule is ported from the TipTap extension that defines it on the web and
//! applies the same transaction: the typed text never enters the document, the
//! matched text is replaced.

use serde_json::{Map as JsonMap, Value};

use crate::content_edit::{admitted, command_result};
use crate::error::{Result, bail};
use crate::json::{self, Map};
use crate::jsre::js_regex;
use crate::pm::model::{Fragment, Mark, Node, ResolvedPos};
use crate::pm::schema::{TypeId, schema};
use crate::pm::state::{Selection, Transaction};
use crate::pm::transform::{can_join, find_wrapping};

/// How much text before the caret a rule may read, as TipTap's `maxMatch`.
const MAX_MATCH: usize = 500;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Kind {
    /// `wrappingInputRule`: wrap the textblock in this node type.
    Wrap,
    /// `textblockTypeInputRule`: change the textblock to this node type.
    Textblock,
    /// `nodeInputRule`: put this block node before the textblock.
    Block,
    /// `markInputRule`: mark the delimited text.
    Mark,
}

struct Rule {
    /// The node or mark type the rule makes, which is also its name.
    name: &'static str,
    kind: Kind,
    find: fn() -> &'static regex::Regex,
    /// A delimiter may not enclose only whitespace (TipTap's `(?!\s+…)`).
    delimiter: Option<&'static str>,
}

/// In the web editor's extension order, so an overlap resolves the same way.
const RULES: &[Rule] = &[
    Rule { name: "blockquote", kind: Kind::Wrap, find: || js_regex!(r"^\s*>\s$"), delimiter: None },
    Rule { name: "bold", kind: Kind::Mark, find: || js_regex!(r"(?:^|\s)(\*\*((?:[^*]+))\*\*)$"), delimiter: Some("**") },
    Rule { name: "bold", kind: Kind::Mark, find: || js_regex!(r"(?:^|\s)(__((?:[^_]+))__)$"), delimiter: Some("__") },
    Rule { name: "code", kind: Kind::Mark, find: || js_regex!(r"(^|[^`])`([^`]+)`$"), delimiter: None },
    Rule { name: "bulletList", kind: Kind::Wrap, find: || js_regex!(r"^\s*([-+*])\s$"), delimiter: None },
    Rule { name: "horizontalRule", kind: Kind::Block, find: || js_regex!(r"^(?:---|—-|___\s|\*\*\*\s)$"), delimiter: None },
    Rule { name: "italic", kind: Kind::Mark, find: || js_regex!(r"(?:^|\s)(\*((?:[^*]+))\*)$"), delimiter: Some("*") },
    Rule { name: "italic", kind: Kind::Mark, find: || js_regex!(r"(?:^|\s)(_((?:[^_]+))_)$"), delimiter: Some("_") },
    Rule { name: "orderedList", kind: Kind::Wrap, find: || js_regex!(r"^(\d+)\.\s$"), delimiter: None },
    Rule { name: "strike", kind: Kind::Mark, find: || js_regex!(r"(?:^|\s)(~~((?:[^~]+))~~)$"), delimiter: Some("~~") },
    Rule { name: "heading", kind: Kind::Textblock, find: || js_regex!(r"^(#{1,6})\s$"), delimiter: None },
    Rule { name: "taskItem", kind: Kind::Wrap, find: || js_regex!(r"^\s*(?:[-+*]\s)?\[( |x|X)\]\s$"), delimiter: None },
    Rule { name: "codeBlock", kind: Kind::Textblock, find: || js_regex!(r"^```([a-z]+)?[\s\n]$"), delimiter: None },
    Rule { name: "codeBlock", kind: Kind::Textblock, find: || js_regex!(r"^~~~([a-z]+)?[\s\n]$"), delimiter: None },
    Rule { name: "highlight", kind: Kind::Mark, find: || js_regex!(r"(?:^|\s)(==((?:[^=]+))==)$"), delimiter: Some("==") },
];

/// One rule's match: the whole matched text and its capture groups, as JavaScript reports them.
struct Found<'r> {
    rule: &'r Rule,
    whole: String,
    groups: Vec<Option<String>>,
}

fn find(text: &str) -> Option<Found<'static>> {
    RULES.iter().find_map(|rule| {
        let captures = (rule.find)().captures(text)?;
        let groups: Vec<Option<String>> = captures.iter().skip(1).map(|g| g.map(|m| m.as_str().to_owned())).collect();
        // `(?!\s+…)` after the opening delimiter: the content is not only whitespace.
        if let (Some(_), Some(Some(content))) = (rule.delimiter, groups.last())
            && content.chars().all(|c| js_regex!(r"^\s$").is_match(c.encode_utf8(&mut [0; 4])))
        {
            return None;
        }
        Some(Found { rule, whole: captures[0].to_owned(), groups })
    })
}

/// The characters a rule can end with: whitespace, as JavaScript's `\s` reads
/// it, and the closing delimiters. Typing anything else never completes a
/// rule, so hosts skip the question for it.
pub fn triggers() -> &'static str {
    "*_~`=-\t\n\u{0B}\u{0C}\r \u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}"
}

/// Whether typing `typed` after `before` (the textblock's text up to the caret)
/// could apply a rule. Hosts ask this cheap question on each keystroke and
/// build the document only when it says yes.
pub fn matches(before: &str, typed: &str) -> bool {
    let mut text = String::with_capacity(before.len() + typed.len());
    text.push_str(before);
    text.push_str(typed);
    find(&text).is_some()
}

/// `{selection, text}` typed into `document`: the rule's Steps and result, in
/// the shape of the editing commands' evidence plus `rule`, or null when no
/// rule applies and the text is typed as usual.
pub fn apply(document: &Value, request: &Value) -> Result<Value> {
    let valid_keys = request.as_object().is_some_and(|m| m.len() == 2 && m.contains_key("selection") && m.contains_key("text"));
    let (Some(text), Some(selection_json), true) = (request.get("text").and_then(Value::as_str), request.get("selection"), valid_keys) else {
        bail!("Invalid input rule request");
    };
    if text.is_empty() || json::utf16_len(text) > 16 {
        bail!("Invalid input rule request");
    }
    let doc = admitted(document)?;
    let selection = Selection::from_json(&doc, selection_json)?;
    let (from, to) = (selection.from(), selection.to());
    let rp = doc.resolve(from)?;
    // TipTap's guards: never inside code, never against inline code.
    let parent = rp.parent();
    if !parent.is_textblock() || schema().nodes[parent.ty()].pre {
        return Ok(Value::Null);
    }
    let code = schema().mark_type("code");
    if [rp.node_before(), rp.node_after()].into_iter().flatten().next().is_some_and(|n| n.marks().iter().any(|m| Some(m.ty) == code)) {
        return Ok(Value::Null);
    }
    let before = text_before(&rp);
    let Some(found) = find(&(before + text)) else { return Ok(Value::Null) };
    let typed = json::utf16_len(text);
    let whole = json::utf16_len(&found.whole);
    let in_document = whole.saturating_sub(typed);
    if whole > typed {
        let Some(start) = rp.parent_offset.checked_sub(in_document) else { return Ok(Value::Null) };
        let prefix: String = String::from_utf16_lossy(&found.whole.encode_utf16().take(in_document).collect::<Vec<_>>());
        if parent.content().text_between(start, rp.parent_offset, "") != prefix {
            return Ok(Value::Null);
        }
    }
    let range = (from - in_document, to);
    let mut tr = Transaction::new(doc.clone(), selection, None);
    let applied = match found.rule.kind {
        Kind::Wrap => wrap(&mut tr, &found, range)?,
        Kind::Textblock => textblock(&mut tr, &found, range)?,
        Kind::Block => block(&mut tr, &found, range)?,
        Kind::Mark => mark(&mut tr, &found, range)?,
    };
    if !applied || tr.steps.is_empty() {
        return Ok(Value::Null);
    }
    let mut result = command_result(&doc, tr, "input_rule")?;
    result["rule"] = Value::String(found.rule.name.to_owned());
    Ok(result)
}

/// `getTextContentFromNodes`: the textblock's text before the caret, with
/// `%leaf%` for each inline atom.
fn text_before(rp: &ResolvedPos) -> String {
    let parent = rp.parent();
    let end = rp.parent_offset;
    let mut text = String::new();
    parent.nodes_between(
        end.saturating_sub(MAX_MATCH),
        end,
        &mut |node, pos, _, _| {
            match node.text_units() {
                Some(units) => text.push_str(&String::from_utf16_lossy(&units[..end.saturating_sub(pos).min(units.len())])),
                None if node.is_atom() => text.push_str("%leaf%"),
                None => {}
            }
            true
        },
        0,
    );
    text
}

fn node_type(name: &str) -> Result<TypeId> {
    match schema().node_type(name) {
        Some(ty) => Ok(ty),
        None => bail!("Unknown node type {name}"),
    }
}

fn attrs(pairs: &[(&str, Value)]) -> Map {
    let mut map = JsonMap::new();
    for (key, value) in pairs {
        map.insert((*key).to_owned(), value.clone());
    }
    map
}

fn rule_attrs(found: &Found) -> Map {
    let first = found.groups.first().cloned().flatten();
    match found.rule.name {
        "orderedList" => attrs(&[("start", Value::from(first.and_then(|n| n.parse::<u64>().ok()).unwrap_or(1)))]),
        "taskItem" => attrs(&[("checked", Value::Bool(first.is_some_and(|c| c.eq_ignore_ascii_case("x"))))]),
        "heading" => attrs(&[("level", Value::from(first.map_or(1, |h| h.len())))]),
        "codeBlock" => attrs(&[("language", first.map_or(Value::Null, Value::String))]),
        _ => Map::new(),
    }
}

/// `wrappingInputRule`, and for a checklist typed in a bullet item, the web's
/// conversion of that item into a checklist between the bullet list's halves.
fn wrap(tr: &mut Transaction, found: &Found, (from, to): (usize, usize)) -> Result<bool> {
    let ty = node_type(found.rule.name)?;
    let attributes = rule_attrs(found);
    if found.rule.name == "taskItem" {
        let rp = tr.doc.resolve(from)?;
        if let Some(depth) = (1..=rp.depth).rev().find(|&d| rp.node(d).type_name() == "bulletList") {
            return task_in_bullet(tr, &rp, depth, ty, &attributes, (from, to));
        }
    }
    tr.delete(from, to)?;
    let rp = tr.doc.resolve(from)?;
    let Some(range) = rp.block_range(&rp, None) else { return Ok(false) };
    let Some(wrapping) = find_wrapping(&range, ty, Some(attributes), None)? else { return Ok(false) };
    tr.wrap(&range, &wrapping)?;
    let joined = tr.doc.resolve(from - 1)?.node_before();
    if let Some(before) = joined
        && before.ty() == ty
        && can_join(&tr.doc, from - 1)?
        && (found.rule.name != "orderedList" || ordered_continues(found, &before))
    {
        tr.join(from - 1, 1)?;
    }
    Ok(true)
}

/// The ordered list rule joins the list before only when the typed number continues it.
fn ordered_continues(found: &Found, before: &Node) -> bool {
    let start = before.attr("start").as_u64().unwrap_or(1) as usize;
    found.groups.first().cloned().flatten().and_then(|n| n.parse::<usize>().ok()) == Some(before.child_count() + start)
}

fn task_in_bullet(tr: &mut Transaction, rp: &ResolvedPos, depth: usize, ty: TypeId, attributes: &Map, (from, to): (usize, usize)) -> Result<bool> {
    let list = rp.node(depth).clone();
    let index = rp.index(depth);
    let list_pos = rp.before(depth)?;
    tr.delete(from, to)?;
    let paragraph = tr.doc.resolve(from)?.parent().clone();
    let item = Node::create(ty, Some(attributes), Fragment::from_node(paragraph), Vec::new())?;
    let children: Vec<Node> = (0..list.child_count()).map(|i| list.child(i).clone()).collect();
    let mut blocks = Vec::new();
    let mut prefix = 0;
    if index > 0 {
        let head = Node::create(list.ty(), Some(list.attrs().as_ref()), Fragment::from_array(children[..index].to_vec()), Vec::new())?;
        prefix = head.node_size();
        blocks.push(head);
    }
    blocks.push(Node::create(node_type("taskList")?, None, Fragment::from_node(item), Vec::new())?);
    if index + 1 < children.len() {
        blocks.push(Node::create(list.ty(), Some(list.attrs().as_ref()), Fragment::from_array(children[index + 1..].to_vec()), Vec::new())?);
    }
    let Some(current) = tr.doc.node_at(list_pos) else { bail!("No list at the input rule's position") };
    tr.replace_with(list_pos, list_pos + current.node_size(), Fragment::from_array(blocks))?;
    let caret = list_pos + prefix + 3;
    let selection = Selection::text_create(&tr.doc, caret, caret)?;
    tr.set_selection(selection)?;
    Ok(true)
}

/// `textblockTypeInputRule`.
fn textblock(tr: &mut Transaction, found: &Found, (from, to): (usize, usize)) -> Result<bool> {
    let ty = node_type(found.rule.name)?;
    let rp = tr.doc.resolve(from)?;
    let depth = rp.depth - 1;
    if !rp.node(depth).can_replace_with(rp.index(depth), rp.index_after(depth), ty, None)? {
        return Ok(false);
    }
    let attributes = rule_attrs(found);
    tr.delete(from, to)?;
    tr.set_block_type(from, from, ty, Some(&attributes))?;
    Ok(true)
}

/// `nodeInputRule` for a block node: it goes before the textblock, and the matched text is deleted.
fn block(tr: &mut Transaction, found: &Found, (from, to): (usize, usize)) -> Result<bool> {
    let node = Node::create(node_type(found.rule.name)?, None, Fragment::empty(), Vec::new())?;
    tr.insert(from - 1, Fragment::from_node(node))?;
    let (start, end) = (tr.mapping.map(from, 1), tr.mapping.map(to, 1));
    tr.delete(start, end)?;
    Ok(true)
}

/// `markInputRule`.
fn mark(tr: &mut Transaction, found: &Found, (from, to): (usize, usize)) -> Result<bool> {
    let s = schema();
    let Some(ty) = s.mark_type(found.rule.name) else { bail!("Unknown mark type {}", found.rule.name) };
    let Some(Some(content)) = found.groups.last() else { return Ok(true) };
    let units = |text: &str| json::utf16_len(text);
    let starting_spaces = found.whole.chars().take_while(|c| js_regex!(r"^\s$").is_match(c.encode_utf8(&mut [0; 4]))).map(|c| c.len_utf16()).sum::<usize>();
    let Some(offset) = found.whole.find(content.as_str()) else { return Ok(false) };
    let text_start = from + units(&found.whole[..offset]);
    let text_end = text_start + units(content);
    // A mark already there that excludes this one (inline code excludes all) stops the rule.
    let mut excluded = false;
    tr.doc.nodes_between(
        from,
        to,
        &mut |node, pos, _, _| {
            if node.is_inline() && pos + node.node_size() > text_start && node.marks().iter().any(|m| m.ty != ty && s.excludes(m.ty, ty)) {
                excluded = true;
            }
            true
        },
        0,
    );
    if excluded {
        return Ok(false);
    }
    if text_end < to {
        tr.delete(text_end, to)?;
    }
    if text_start > from {
        tr.delete(from + starting_spaces, text_start)?;
    }
    let mark_end = from + starting_spaces + units(content);
    tr.add_mark(from + starting_spaces, mark_end, &Mark::new(ty, None)?)?;
    // `removeStoredMark`: text typed next is not marked.
    let stored = match tr.stored_marks() {
        Some(marks) => marks.clone(),
        None => tr.selection()?.head_r().marks(),
    };
    tr.set_stored_marks(Some(stored.into_iter().filter(|m| m.ty != ty).collect()));
    Ok(true)
}

#[cfg(test)]
mod tests {
    use serde_json::{Value, json};

    /// spec/relaymark/editor/input-rules-v1.json, the cases the web editor passes too.
    #[test]
    fn every_shared_case() {
        let fixture: Value = serde_json::from_str(include_str!("../../../spec/relaymark/editor/input-rules-v1.json")).expect("fixture");
        let mut failures = Vec::new();
        for case in fixture["cases"].as_array().expect("cases") {
            let name = case["name"].as_str().expect("name");
            let before = normalized_document(&case["before"]);
            let caret = case["caret"].clone();
            let request = json!({"selection": {"type": "text", "anchor": caret, "head": caret}, "text": case["text"]});
            let result = match super::apply(&before, &request) {
                Ok(result) => result,
                Err(error) => {
                    failures.push(format!("{name}: {}", error.message()));
                    continue;
                }
            };
            if case["after"].is_null() {
                if !result.is_null() {
                    failures.push(format!("{name}: applied {} where no rule applies", result["rule"]));
                }
                continue;
            }
            if result.is_null() {
                failures.push(format!("{name}: no rule applied"));
                continue;
            }
            if stripped(&result["document"]) != stripped(&normalized_document(&case["after"])) {
                failures.push(format!("{name}: document {}", stripped(&result["document"])));
            }
            if result["selection"]["head"] != case["selection"] {
                failures.push(format!("{name}: caret {} not {}", result["selection"]["head"], case["selection"]));
            }
        }
        assert!(failures.is_empty(), "{}", failures.join("\n"));
    }

    /// Bug caught: a rule ending in a character hosts never ask about, so it never fires natively.
    #[test]
    fn every_case_ends_in_a_trigger() {
        let fixture: Value = serde_json::from_str(include_str!("../../../spec/relaymark/editor/input-rules-v1.json")).expect("fixture");
        for case in fixture["cases"].as_array().expect("cases").iter().filter(|case| !case["after"].is_null()) {
            let last = case["text"].as_str().and_then(|text| text.chars().last()).expect("typed text");
            assert!(super::triggers().contains(last), "{}: {last:?} is not a trigger", case["name"]);
        }
    }

    #[test]
    fn matches_only_text_a_rule_reads() {
        assert!(super::matches("[ ]", " "));
        assert!(super::matches("Say **this*", "*"));
        assert!(!super::matches("a -", " "));
        assert!(!super::matches("plain text", " "));
    }

    /// Schema defaults filled and each block identified, as an admitted document is.
    fn normalized_document(value: &Value) -> Value {
        fn identify(value: &mut Value, next: &mut u64) {
            if let Some(attrs) = value.get_mut("attrs").and_then(Value::as_object_mut)
                && attrs.get("relaymarkId").is_some_and(Value::is_null)
            {
                *next += 1;
                attrs.insert("relaymarkId".into(), json!(format!("b{next:012x}40008{next:015x}")));
            }
            for child in value.get_mut("content").and_then(Value::as_array_mut).into_iter().flatten() {
                identify(child, next);
            }
        }
        let mut document = crate::pm::model::Node::from_json(value).expect("fixture document").to_json();
        identify(&mut document, &mut 0);
        document
    }

    /// Block identity is allocated per editor.
    fn stripped(value: &Value) -> Value {
        match value {
            Value::Object(map) => Value::Object(
                map.iter()
                    .filter(|(key, _)| key.as_str() != "relaymarkId" && key.as_str() != "headingId")
                    .map(|(key, value)| (key.clone(), stripped(value)))
                    .collect(),
            ),
            Value::Array(items) => Value::Array(items.iter().map(stripped).collect()),
            other => other.clone(),
        }
    }
}
