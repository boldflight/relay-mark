//! The canonical editor schema, read from `spec/relaymark/editor-schema.json`,
//! the one schema source shared with TipTap (generated JS), the Elixir adapter
//! (packaged copy) and the Swift ProseMirror port (generated Swift).
//!
//! [`normalize`] reproduces what the maintained ProseMirror model does to
//! editor JSON: `Node.fromJSON` (attribute defaults, mark ordering, joining
//! adjacent text with equal marks), `Node.check` (content expressions, allowed
//! and exclusive marks) and `Node.toJSON`.

use std::collections::HashMap;
use std::sync::OnceLock;

use regex::Regex;
use serde_json::Value;

use crate::error::{Result, bail};
use crate::json::{self, Map};

pub const EDITOR_SCHEMA_JSON: &str = include_str!("../../../spec/relaymark/editor-schema.json");
pub const ATTRIBUTE_ENCODING_JSON: &str = include_str!("../../../spec/relaymark/xml-attribute-encoding.json");
pub const CONTRACT_JSON: &str = include_str!("../../../spec/relaymark/contract.json");

pub struct NodeSpec {
    pub name: String,
    pub attrs: Vec<(String, Value)>,
    /// `None` admits every mark, as ProseMirror's `markSet: null`.
    pub mark_set: Option<Vec<String>>,
    content: Option<Regex>,
}

pub struct MarkSpec {
    pub name: String,
    pub attrs: Vec<(String, Value)>,
    pub excludes: Vec<String>,
}

pub struct EditorSchema {
    pub source: Value,
    pub nodes: Vec<NodeSpec>,
    pub marks: Vec<MarkSpec>,
    node_index: HashMap<String, usize>,
    mark_index: HashMap<String, usize>,
}

pub fn editor_schema() -> &'static EditorSchema {
    static SCHEMA: OnceLock<EditorSchema> = OnceLock::new();
    SCHEMA.get_or_init(|| EditorSchema::load(EDITOR_SCHEMA_JSON))
}

fn node_char(index: usize) -> char {
    char::from_u32(0xE000 + index as u32).unwrap_or('\u{E000}')
}

fn attr_specs(value: Option<&Value>) -> Vec<(String, Value)> {
    value
        .and_then(Value::as_object)
        .map(|attrs| attrs.iter().map(|(name, spec)| (name.clone(), json::field(spec, "default").cloned().unwrap_or(Value::Null))).collect())
        .unwrap_or_default()
}

impl EditorSchema {
    fn load(source_text: &str) -> Self {
        let source: Value = serde_json::from_str(source_text).expect("packaged editor schema is JSON");
        let node_values = source["nodes"].as_array().expect("schema nodes").clone();
        let mark_values = source["marks"].as_array().expect("schema marks").clone();
        let names: Vec<String> = node_values.iter().map(|n| n["name"].as_str().expect("node name").to_owned()).collect();
        let groups: Vec<Vec<String>> = node_values.iter().map(|n| n["group"].as_str().unwrap_or("").split_whitespace().map(str::to_owned).collect()).collect();
        let class_for = |name: &str| -> String {
            let members: String = match names.iter().position(|candidate| candidate == name) {
                Some(index) => node_char(index).to_string(),
                None => (0..names.len()).filter(|&i| groups[i].iter().any(|g| g == name)).map(node_char).collect(),
            };
            assert!(!members.is_empty(), "unknown content name {name}");
            format!("[{members}]")
        };
        let nodes = node_values
            .iter()
            .map(|node| {
                let content = node["content"].as_str().filter(|expr| !expr.is_empty()).map(|expr| {
                    let pattern = format!("^(?:{})$", content_pattern(expr, &class_for));
                    Regex::new(&pattern).expect("content expression")
                });
                NodeSpec {
                    name: node["name"].as_str().unwrap_or_default().to_owned(),
                    attrs: attr_specs(node.get("attrs")),
                    mark_set: node["markSet"].as_array().map(|marks| marks.iter().filter_map(|m| m.as_str().map(str::to_owned)).collect()),
                    content,
                }
            })
            .collect::<Vec<_>>();
        let marks = mark_values
            .iter()
            .map(|mark| MarkSpec {
                name: mark["name"].as_str().unwrap_or_default().to_owned(),
                attrs: attr_specs(mark.get("attrs")),
                excludes: mark["excludes"].as_array().map(|items| items.iter().filter_map(|m| m.as_str().map(str::to_owned)).collect()).unwrap_or_default(),
            })
            .collect::<Vec<_>>();
        let node_index = nodes.iter().enumerate().map(|(i, n)| (n.name.clone(), i)).collect();
        let mark_index = marks.iter().enumerate().map(|(i, m)| (m.name.clone(), i)).collect();
        Self { source, nodes, marks, node_index, mark_index }
    }

    pub fn mark_rank(&self, name: &str) -> Option<usize> {
        self.mark_index.get(name).copied()
    }

    pub fn mark(&self, name: &str) -> Option<&MarkSpec> {
        self.mark_index.get(name).map(|&index| &self.marks[index])
    }

    /// `Node.fromJSON` + `check()` + `toJSON()` of a whole editor document.
    pub fn normalize(&self, document: &Value) -> Result<Value> {
        let node = self.node_from_json(document)?;
        self.check(&node)?;
        Ok(node.into_json())
    }

    fn node_from_json(&self, json: &Value) -> Result<PmNode> {
        let Some(object) = json.as_object() else { bail!("Invalid input for Node.fromJSON") };
        let marks = match object.get("marks") {
            Some(value) if json::truthy(Some(value)) => {
                let Some(items) = value.as_array() else { bail!("Invalid mark data for Node.fromJSON") };
                let mut marks = items.iter().map(|mark| self.mark_from_json(mark)).collect::<Result<Vec<_>>>()?;
                marks.sort_by_key(|mark| mark.rank);
                marks
            }
            _ => Vec::new(),
        };
        let type_name = object.get("type").and_then(Value::as_str).unwrap_or_default();
        if type_name == "text" {
            let Some(text) = object.get("text").and_then(Value::as_str) else { bail!("Invalid text node in JSON") };
            if text.is_empty() {
                bail!("Empty text nodes are not allowed");
            }
            return Ok(PmNode { kind: self.node_index["text"], attrs: Map::new(), content: Vec::new(), marks, text: Some(text.to_owned()) });
        }
        let Some(&kind) = self.node_index.get(type_name) else { bail!("Unknown node type: {type_name}") };
        let content = match object.get("content") {
            Some(value) if json::truthy(Some(value)) => {
                let Some(items) = value.as_array() else { bail!("Invalid input for Fragment.fromJSON") };
                let mut joined: Vec<PmNode> = Vec::with_capacity(items.len());
                for item in items {
                    let child = self.node_from_json(item)?;
                    if let Some(last) = joined.last_mut()
                        && last.text.is_some()
                        && child.text.is_some()
                        && last.marks == child.marks
                    {
                        last.text.as_mut().unwrap().push_str(child.text.as_deref().unwrap());
                        continue;
                    }
                    joined.push(child);
                }
                joined
            }
            _ => Vec::new(),
        };
        let attrs = compute_attrs(&self.nodes[kind].attrs, object.get("attrs"));
        Ok(PmNode { kind, attrs, content, marks, text: None })
    }

    fn mark_from_json(&self, json: &Value) -> Result<PmMark> {
        if !json::truthy(Some(json)) {
            bail!("Invalid input for Mark.fromJSON");
        }
        let name = json::str_field(json, "type").unwrap_or_default();
        let Some(rank) = self.mark_rank(name) else { bail!("There is no mark type {name} in this schema") };
        Ok(PmMark { rank, attrs: compute_attrs(&self.marks[rank].attrs, json::field(json, "attrs")) })
    }

    fn check(&self, node: &PmNode) -> Result<()> {
        let spec = &self.nodes[node.kind];
        let children: String = node.content.iter().map(|child| node_char(child.kind)).collect();
        let valid_sequence = match &spec.content {
            Some(pattern) => pattern.is_match(&children),
            None => children.is_empty(),
        };
        let marks_allowed = node.content.iter().all(|child| match &spec.mark_set {
            None => true,
            Some(allowed) => child.marks.iter().all(|mark| allowed.contains(&self.marks[mark.rank].name)),
        });
        if !valid_sequence || !marks_allowed {
            bail!("Invalid content for node {}", spec.name);
        }
        let mut set: Vec<&PmMark> = Vec::new();
        for mark in &node.marks {
            set = self.add_to_set(mark, set);
        }
        if set.len() != node.marks.len() || set.iter().zip(&node.marks).any(|(a, b)| *a != b) {
            bail!("Invalid collection of marks for node {}", spec.name);
        }
        node.content.iter().try_for_each(|child| self.check(child))
    }

    /// `Mark.addToSet`, including exclusion and rank placement.
    fn add_to_set<'m>(&self, mark: &'m PmMark, set: Vec<&'m PmMark>) -> Vec<&'m PmMark> {
        let excludes = |a: &PmMark, b: &PmMark| self.marks[a.rank].excludes.contains(&self.marks[b.rank].name);
        let mut copy: Option<Vec<&PmMark>> = None;
        let mut placed = false;
        for (index, other) in set.iter().enumerate() {
            if mark == *other {
                return set;
            }
            if excludes(mark, other) {
                copy.get_or_insert_with(|| set[..index].to_vec());
            } else if excludes(other, mark) {
                return set;
            } else {
                if !placed && other.rank > mark.rank {
                    copy.get_or_insert_with(|| set[..index].to_vec()).push(mark);
                    placed = true;
                }
                if let Some(copy) = copy.as_mut() {
                    copy.push(other);
                }
            }
        }
        let mut copy = copy.unwrap_or_else(|| set.clone());
        if !placed {
            copy.push(mark);
        }
        copy
    }
}

/// ProseMirror `computeAttrs`: every declared attribute, given value or default.
fn compute_attrs(specs: &[(String, Value)], given: Option<&Value>) -> Map {
    let given = given.and_then(Value::as_object);
    specs.iter().map(|(name, default)| (name.clone(), given.and_then(|g| g.get(name)).cloned().unwrap_or_else(|| default.clone()))).collect()
}

#[derive(Debug, Clone, PartialEq)]
struct PmMark {
    rank: usize,
    attrs: Map,
}

struct PmNode {
    kind: usize,
    attrs: Map,
    content: Vec<PmNode>,
    marks: Vec<PmMark>,
    text: Option<String>,
}

impl PmNode {
    fn into_json(self) -> Value {
        let schema = editor_schema();
        let mut object = Map::with_capacity(4);
        object.insert("type".into(), Value::String(schema.nodes[self.kind].name.clone()));
        if !self.attrs.is_empty() {
            object.insert("attrs".into(), Value::Object(self.attrs));
        }
        if !self.content.is_empty() {
            object.insert("content".into(), Value::Array(self.content.into_iter().map(PmNode::into_json).collect()));
        }
        if !self.marks.is_empty() {
            let marks = self
                .marks
                .into_iter()
                .map(|mark| {
                    let mut json = Map::with_capacity(2);
                    json.insert("type".into(), Value::String(schema.marks[mark.rank].name.clone()));
                    if !mark.attrs.is_empty() {
                        json.insert("attrs".into(), Value::Object(mark.attrs));
                    }
                    Value::Object(json)
                })
                .collect();
            object.insert("marks".into(), Value::Array(marks));
        }
        if let Some(text) = self.text {
            object.insert("text".into(), Value::String(text));
        }
        Value::Object(object)
    }
}

/// Translate a ProseMirror content expression into a regular expression over
/// one private-use character per node type.
fn content_pattern(expression: &str, class_for: &dyn Fn(&str) -> String) -> String {
    let mut pattern = String::new();
    let mut chars = expression.chars().peekable();
    while let Some(character) = chars.next() {
        match character {
            '(' | ')' | '|' | '*' | '+' | '?' => pattern.push(character),
            '{' => {
                pattern.push('{');
                for next in chars.by_ref() {
                    pattern.push(next);
                    if next == '}' {
                        break;
                    }
                }
            }
            c if c.is_whitespace() => {}
            c => {
                let mut name = c.to_string();
                while let Some(&next) = chars.peek() {
                    if next.is_alphanumeric() || next == '_' {
                        name.push(next);
                        chars.next();
                    } else {
                        break;
                    }
                }
                pattern.push_str(&class_for(&name));
            }
        }
    }
    pattern
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn content_expressions_and_text_joining_follow_prosemirror() {
        let schema = editor_schema();
        let doc = json!({"type":"doc","content":[{"type":"paragraph","content":[
            {"type":"text","text":"A"},{"type":"text","text":"B"},
            {"type":"text","text":"C","marks":[{"type":"bold"}]}]}]});
        let normalized = schema.normalize(&doc).unwrap();
        assert_eq!(normalized["content"][0]["content"][0]["text"], "AB");
        assert_eq!(normalized["content"][0]["attrs"], json!({"relaymarkId": null}));
        let callout_without_body = json!({"type":"doc","content":[{"type":"callout","content":[{"type":"calloutTitle"}]}]});
        assert!(schema.normalize(&callout_without_body).is_err());
        let code_with_bold = json!({"type":"doc","content":[{"type":"paragraph","content":[
            {"type":"text","text":"x","marks":[{"type":"bold"},{"type":"code"}]}]}]});
        assert!(schema.normalize(&code_with_bold).is_err());
    }
}
