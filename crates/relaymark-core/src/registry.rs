//! The directive registry, read from `spec/relaymark/directives/*.json`, and
//! the generic directive editor nodes derived from it.

use std::sync::OnceLock;

use serde_json::Value;

use crate::error::{Result, bail};
use crate::json::{self, Map};

const DIRECTIVE_SOURCES: &[&str] = &[
    include_str!("../../../spec/relaymark/directives/relay.action_row.json"),
    include_str!("../../../spec/relaymark/directives/relay.agent_suggestion.json"),
    include_str!("../../../spec/relaymark/directives/relay.callout.json"),
    include_str!("../../../spec/relaymark/directives/relay.callout_title.json"),
    include_str!("../../../spec/relaymark/directives/relay.claim.json"),
    include_str!("../../../spec/relaymark/directives/relay.comparison.json"),
    include_str!("../../../spec/relaymark/directives/relay.data_view.json"),
    include_str!("../../../spec/relaymark/directives/relay.entity_reference.json"),
    include_str!("../../../spec/relaymark/directives/relay.evidence_ref.json"),
    include_str!("../../../spec/relaymark/directives/relay.file_ref.json"),
    include_str!("../../../spec/relaymark/directives/relay.form_option.json"),
    include_str!("../../../spec/relaymark/directives/relay.form_question.json"),
    include_str!("../../../spec/relaymark/directives/relay.layout.json"),
    include_str!("../../../spec/relaymark/directives/relay.note_ref.json"),
    include_str!("../../../spec/relaymark/directives/relay.paper_control.json"),
    include_str!("../../../spec/relaymark/directives/relay.property_sheet.json"),
    include_str!("../../../spec/relaymark/directives/relay.source_bundle.json"),
    include_str!("../../../spec/relaymark/directives/relay.transcript_segment.json"),
    include_str!("../../../spec/relaymark/directives/relay.url_ref.json"),
    include_str!("../../../spec/relaymark/directives/relay.video_embed.json"),
];

pub struct Directive {
    pub name: String,
    pub ast_type: String,
    pub spec: Value,
}

impl Directive {
    pub fn attributes(&self) -> Option<&Map> {
        self.spec.get("attributes").and_then(Value::as_object)
    }

    pub fn capability(&self) -> Option<&str> {
        self.spec.get("capability").and_then(Value::as_str)
    }

    pub fn fallback(&self) -> Option<&str> {
        self.spec.get("fallback").and_then(Value::as_str)
    }

    pub fn policy_flag(&self, name: &str) -> bool {
        json::field(&self.spec, "policy").and_then(|policy| policy.get(name)).and_then(Value::as_bool) == Some(true)
    }
}

/// A generic authored directive represented by one editor node.
pub struct DirectiveNode {
    pub ast_type: &'static str,
    pub name: &'static str,
    pub attributes: Map,
    pub allowed_children: Vec<String>,
    pub minimum_children: usize,
}

const DIRECTIVE_NODES: &[(&str, &str)] = &[
    ("relay.source_bundle", "relaySourceBundle"),
    ("relay.claim", "relayClaim"),
    ("relay.evidence_ref", "relayEvidence"),
    ("relay.comparison", "relayComparison"),
    ("relay.transcript_segment", "relayTranscript"),
    ("relay.action_row", "relayAction"),
    ("relay.property_sheet", "relayPropertySheet"),
    ("relay.layout", "relayLayout"),
    ("relay.file_ref", "relayFile"),
    ("relay.note_ref", "relayNote"),
    ("relay.url_ref", "relayUrl"),
];

/// Editor node names for each AST block type.
#[cfg(test)]
fn pm_names_for(ast_type: &str) -> Option<&'static [&'static str]> {
    Some(match ast_type {
        "paragraph" => &["paragraph"],
        "heading" => &["heading"],
        "quote" => &["blockquote"],
        "list" => &["bulletList", "orderedList"],
        "list_item" => &["listItem"],
        "task_list" => &["taskList"],
        "task_item" => &["taskItem"],
        "code" => &["codeBlock"],
        "horizontal_rule" => &["horizontalRule"],
        "image" => &["image"],
        "table" => &["table"],
        "table_row" => &["tableRow"],
        "table_cell" => &["tableCell", "tableHeader"],
        "relay.callout" => &["callout"],
        "relay.callout_title" => &["calloutTitle"],
        "relay.video_embed" => &["videoEmbed"],
        "relay.entity_reference" => &["relayEntityReference"],
        "relay.agent_suggestion" => &["agentSuggestion"],
        "relay.data_view" => &["relayDataView"],
        "relay.form_question" => &["questionBlock"],
        "relay.form_option" => &["questionOption"],
        "relay.paper_control" => &["relayButton", "relayAnchor", "relayConnection"],
        other => return DIRECTIVE_NODES.iter().find(|(ty, _)| *ty == other).map(|(_, name)| std::slice::from_ref(name)),
    })
}

pub struct Registry {
    pub directives: Vec<Directive>,
    pub nodes: Vec<DirectiveNode>,
}

pub fn registry() -> &'static Registry {
    static REGISTRY: OnceLock<Registry> = OnceLock::new();
    REGISTRY.get_or_init(load)
}

fn load() -> Registry {
    let directives: Vec<Directive> = DIRECTIVE_SOURCES
        .iter()
        .map(|source| {
            let spec: Value = serde_json::from_str(source).expect("packaged directive is JSON");
            Directive {
                name: spec["name"].as_str().expect("directive name").to_owned(),
                ast_type: spec["ast_type"].as_str().expect("directive type").to_owned(),
                spec,
            }
        })
        .collect();
    let nodes = DIRECTIVE_NODES
        .iter()
        .map(|&(ast_type, name)| {
            let spec = &directives.iter().find(|d| d.ast_type == ast_type).expect("registered directive").spec;
            let allowed_children: Vec<String> =
                spec["children"]["allowed_types"].as_array().expect("directive children").iter().map(|t| t.as_str().unwrap_or_default().to_owned()).collect();
            let minimum_children = spec["children"]["min"].as_u64().unwrap_or(0) as usize;
            DirectiveNode { ast_type, name, attributes: spec["attributes"].as_object().cloned().unwrap_or_default(), allowed_children, minimum_children }
        })
        .collect();
    Registry { directives, nodes }
}

pub fn directive_for_name(name: &str) -> Option<&'static Directive> {
    registry().directives.iter().find(|d| d.name == name)
}

pub fn directive_for_type(ast_type: &str) -> Option<&'static Directive> {
    registry().directives.iter().find(|d| d.ast_type == ast_type)
}

pub fn directive_node_for_name(name: &str) -> Option<&'static DirectiveNode> {
    registry().nodes.iter().find(|n| n.name == name)
}

pub fn directive_node_for_type(ast_type: &str) -> Option<&'static DirectiveNode> {
    registry().nodes.iter().find(|n| n.ast_type == ast_type)
}

/// Authored directive properties: declared attributes only, defaults applied,
/// in registry order, each with its declared type.
pub fn authored_directive_props(shape: &DirectiveNode, attrs: &Value) -> Result<Map> {
    let Some(attrs) = attrs.as_object() else { bail!("Invalid directive attrs") };
    for key in attrs.keys() {
        if key != "relaymarkId" && !shape.attributes.contains_key(key) {
            bail!("Unsupported authored directive field {key}");
        }
    }
    let mut props = Map::new();
    for (key, spec) in &shape.attributes {
        let value = match attrs.get(key) {
            Some(value) if !value.is_null() => value.clone(),
            _ => {
                if let Some(default) = spec.get("default") {
                    default.clone()
                } else if spec.get("required").and_then(Value::as_bool) == Some(true) {
                    bail!("Missing authored directive {key}");
                } else {
                    continue;
                }
            }
        };
        let kind = spec.get("type").and_then(Value::as_str).unwrap_or_default();
        let okay = match kind {
            "string" | "enum" => value.is_string(),
            "boolean" => value.is_boolean(),
            "integer" => json::is_safe_integer(&value),
            "number" => json::is_finite_number(&value),
            "array" => value.is_array(),
            "object" => value.is_object(),
            _ => false,
        };
        let enum_ok = kind != "enum" || spec.get("values").and_then(Value::as_array).is_some_and(|values| values.contains(&value));
        let items_ok = spec.get("items").and_then(Value::as_str) != Some("string") || value.as_array().is_some_and(|items| items.iter().all(Value::is_string));
        if !okay || !enum_ok || !items_ok {
            bail!("Invalid authored directive {key}");
        }
        if !json::depth_within(&value, 64) {
            bail!("Directive JSON nesting");
        }
        props.insert(key.clone(), value);
    }
    Ok(props)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::schema::editor_schema;

    /// The editor schema repeats each directive node's content expression; the
    /// registry derives it. Drift between the two files would split meaning.
    #[test]
    fn directive_nodes_match_the_editor_schema() {
        for node in &registry().nodes {
            let declared = editor_schema().source["nodes"]
                .as_array()
                .unwrap()
                .iter()
                .find(|n| n["name"] == node.name)
                .unwrap_or_else(|| panic!("{} missing from editor schema", node.name));
            let names: Vec<&str> =
                node.allowed_children.iter().flat_map(|child| pm_names_for(child).expect("directive child has an editor node").iter().copied()).collect();
            let alternatives = if names.len() == 1 { names[0].to_owned() } else { format!("({})", names.join(" | ")) };
            let content = alternatives + if node.minimum_children > 0 { "+" } else { "*" };
            assert_eq!(declared["content"], content.as_str(), "{}", node.name);
            let declared_attrs: Vec<&String> = declared["attrs"].as_object().unwrap().keys().filter(|k| *k != "relaymarkId").collect();
            let registry_attrs: Vec<&String> = node.attributes.keys().collect();
            assert_eq!(declared_attrs, registry_attrs, "{}", node.name);
        }
    }
}
