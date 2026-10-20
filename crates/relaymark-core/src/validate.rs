//! Semantic validation of a conformance AST: directive contracts, evidence
//! resolution, action proposal lifecycles, Scripture release evidence, the
//! Agent Answer profile and document identity namespaces. Diagnostics, never
//! exceptions; the wording is part of the conformance fixtures.

use std::collections::{HashMap, HashSet};

use serde_json::{Value, json};

use crate::adapter::validate_question_props;
use crate::controls::{assert_control_props, assert_entity_reference_props};
use crate::json::{self, nonempty};
use crate::jsre::js_regex;
use crate::node_kind::is_block_node;
use crate::registry::directive_for_type;

fn error(code: impl Into<String>, message: impl Into<String>) -> Value {
    json!({"level": "error", "code": code.into(), "message": message.into()})
}

fn text(value: Option<&Value>) -> String {
    match value {
        None | Some(Value::Null) => String::new(),
        Some(Value::String(text)) => text.clone(),
        Some(other) => json::stringify(other),
    }
}

/// `value || "unknown"` for a message.
fn or_unknown(value: Option<&Value>) -> String {
    if json::truthy(value) { text(value) } else { "unknown".into() }
}

fn props<'a>(block: &'a Value, key: &str) -> Option<&'a Value> {
    block.get("props").and_then(|p| p.as_object()).and_then(|p| p.get(key))
}

fn type_of(block: &Value) -> Option<&str> {
    block.get("type").and_then(Value::as_str)
}

fn child_blocks(block: &Value) -> impl Iterator<Item = &Value> {
    block.get("content").and_then(Value::as_array).into_iter().flatten().filter(|c| is_block_node(c))
}

fn visit_blocks<'a>(blocks: &'a [Value], visitor: &mut dyn FnMut(&'a Value)) {
    for block in blocks {
        visitor(block);
        for child in child_blocks(block) {
            visit_blocks(std::slice::from_ref(child), visitor);
        }
    }
}

fn blocks_of(document: &Value) -> &[Value] {
    document.get("blocks").and_then(Value::as_array).map(Vec::as_slice).unwrap_or(&[])
}

fn resources_of(document: &Value) -> &[Value] {
    document.get("resources").and_then(Value::as_array).map(Vec::as_slice).unwrap_or(&[])
}

/// Diagnostics for a conformance AST; `context` carries host-only facts such
/// as `{"surface": "scripture_ask"}` and is never serialized.
pub fn validate_document(document: &Value, context: &Value) -> Vec<Value> {
    let mut diagnostics = Vec::new();
    if type_of(document) != Some("relaymark.document") {
        diagnostics.push(error("relaymark.document.type", "Document type must be relaymark.document."));
    }
    if document.get("version").is_some() {
        diagnostics.push(error("relaymark.document.obsolete_version", "The document envelope owns compatibility; nested AST versions are obsolete."));
    }
    let targets = collect_evidence_targets(document);
    let scripture = collect_scripture_resources(document);
    validate_scripture_resources(document, &mut diagnostics);
    let mut seen = HashSet::new();
    for block in blocks_of(document) {
        validate_block(block, &mut diagnostics, &mut seen, Some(&targets), &scripture, None, 0);
    }
    validate_agent_answer(document, &mut diagnostics, context);
    validate_identities(document, &mut diagnostics);
    diagnostics
}

/// Diagnostics for one directive node in isolation (no evidence resolution).
pub fn validate_directive_node(block: &Value) -> Vec<Value> {
    let mut diagnostics = Vec::new();
    validate_relay_block(block, &mut diagnostics, None, &HashMap::new());
    diagnostics
}

type Scripture<'a> = HashMap<String, Vec<&'a Value>>;

fn validate_block(
    block: &Value,
    diagnostics: &mut Vec<Value>,
    seen: &mut HashSet<String>,
    targets: Option<&HashSet<String>>,
    scripture: &Scripture<'_>,
    parent: Option<&str>,
    task_depth: usize,
) {
    let id = block.get("id");
    if !json::truthy(id) {
        diagnostics.push(error("relaymark.block.id", "Every block must have an id."));
    } else if !seen.insert(json::stringify(id.unwrap_or(&Value::Null))) {
        diagnostics.push(error("relaymark.block.duplicate_id", format!("Duplicate block id '{}'.", text(id))));
    }
    if !json::truthy(block.get("type")) {
        diagnostics.push(error("relaymark.block.type", format!("Block '{}' must have a type.", or_unknown(id))));
    }
    let kind = type_of(block).unwrap_or_default();
    if kind.starts_with("relay.") {
        validate_relay_block(block, diagnostics, targets, scripture);
    }
    let content = block.get("content").and_then(Value::as_array);
    if kind == "relay.callout" {
        let children = content.map(Vec::as_slice).unwrap_or(&[]);
        let titles: Vec<usize> = children.iter().enumerate().filter(|(_, c)| type_of(c) == Some("relay.callout_title")).map(|(i, _)| i).collect();
        if titles.len() > 1 || (titles.len() == 1 && titles[0] != 0) || children.len() <= titles.len() {
            diagnostics.push(error("relaymark.callout.children", "Callout needs body blocks and at most one first title."));
        }
    }
    if kind == "relay.callout_title" && parent != Some("relay.callout") {
        diagnostics.push(error("relaymark.callout.title_parent", "Callout title must be a direct callout child."));
    }
    if kind == "relay.form_question" || kind == "relay.form_option" {
        let option = kind == "relay.form_option";
        let outcome = (|| -> crate::Result<()> {
            validate_question_props(block.get("props").unwrap_or(&Value::Null), option)?;
            if option && parent != Some("relay.form_question") {
                return Err(crate::Error::new("Form option parent"));
            }
            if !option {
                let shape_ok =
                    content.is_some_and(|c| c.first().and_then(type_of) == Some("paragraph") && c[1..].iter().all(|n| type_of(n) == Some("relay.form_option")));
                if !shape_ok {
                    return Err(crate::Error::new("Form label/options shape"));
                }
                let ids: Vec<String> =
                    content.map(Vec::as_slice).unwrap_or(&[])[1..].iter().map(|n| json::stringify(props(n, "id").unwrap_or(&Value::Null))).collect();
                if ids.iter().collect::<HashSet<_>>().len() != ids.len() {
                    return Err(crate::Error::new("Duplicate option identity"));
                }
            }
            Ok(())
        })();
        if let Err(failure) = outcome {
            diagnostics.push(error("relaymark.form.authored", failure.message()));
        }
    }
    if kind == "task_list" {
        let valid = task_depth < 16 && content.is_some_and(|c| !c.is_empty() && c.len() <= 4096 && c.iter().all(|child| type_of(child) == Some("task_item")));
        if !valid {
            diagnostics.push(error("relaymark.task_list.children", "Task list needs task items within the depth and size limits."));
        }
        if block.get("props").and_then(Value::as_object).is_some_and(|p| !p.is_empty()) {
            diagnostics.push(error("relaymark.task_list.props", "Task list has no properties."));
        }
    }
    if kind == "task_item" {
        let empty = serde_json::Map::new();
        let item_props = block.get("props").filter(|p| json::truthy(Some(p))).and_then(Value::as_object).unwrap_or(&empty);
        let entity = item_props.get("entityId");
        let valid_entity = matches!(entity, Some(Value::Null))
            || entity.and_then(Value::as_str).is_some_and(|e| js_regex!(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$").is_match(e));
        if !item_props.get("checked").is_some_and(Value::is_boolean) || !valid_entity || item_props.keys().any(|k| k != "checked" && k != "entityId") {
            diagnostics.push(error("relaymark.task_item.props", "Task item needs checked and canonical entityId properties."));
        }
        let children_ok = parent == Some("task_list")
            && content.is_some_and(|c| {
                !c.is_empty()
                    && c.len() <= 4096
                    && type_of(&c[0]) == Some("paragraph")
                    && c[1..].iter().all(|child| {
                        is_block_node(child)
                            && !["list_item", "task_item", "table_row", "table_cell", "relay.callout_title"].contains(&type_of(child).unwrap_or_default())
                    })
            });
        if !children_ok {
            diagnostics.push(error("relaymark.task_item.children", "Task item needs a first paragraph and supported child blocks."));
        }
    }
    for child in child_blocks(block) {
        let depth = task_depth + usize::from(kind == "task_list");
        validate_block(child, diagnostics, seen, targets, scripture, Some(kind), depth);
    }
}

fn evidence_refs_for(block: &Value) -> Vec<Value> {
    if let Some(refs) = block.get("evidence_refs").and_then(Value::as_array).filter(|r| !r.is_empty()) {
        return refs.clone();
    }
    props(block, "evidence").and_then(Value::as_array).cloned().unwrap_or_default()
}

fn validate_relay_block(block: &Value, diagnostics: &mut Vec<Value>, targets: Option<&HashSet<String>>, scripture: &Scripture<'_>) {
    let kind = type_of(block).unwrap_or_default();
    let Some(directive) = directive_for_type(kind) else {
        diagnostics.push(error("relaymark.directive.unknown_type", format!("Unknown Relay block type '{kind}'.")));
        return;
    };
    let attributes = directive.attributes().cloned().unwrap_or_default();
    for (name, attribute) in &attributes {
        match props(block, name) {
            None if attribute.get("required").and_then(Value::as_bool) == Some(true) => {
                diagnostics.push(error("relaymark.attribute.required", format!("{kind}.{name} is required.")));
            }
            Some(value) => validate_attribute(kind, name, value, attribute, diagnostics),
            None => {}
        }
    }
    for name in block.get("props").and_then(Value::as_object).into_iter().flatten().map(|(k, _)| k) {
        if !attributes.contains_key(name) {
            diagnostics.push(error("relaymark.attribute.unknown", format!("{kind}.{name} is not declared by the directive contract.")));
        }
    }
    if directive.policy_flag("requires_review") && props(block, "review").is_none() {
        diagnostics.push(error("relaymark.policy.review_required", format!("{kind} requires a review state.")));
    }
    let evidence = evidence_refs_for(block);
    if directive.policy_flag("requires_evidence") && !evidence.iter().any(nonempty) {
        diagnostics.push(error("relaymark.policy.evidence_required", format!("{kind} requires at least one evidence reference.")));
    }
    for reference in &evidence {
        if !nonempty(reference) {
            diagnostics.push(error("relaymark.evidence.invalid_reference", format!("{kind} evidence references must be non-empty strings.")));
            continue;
        }
        let reference = reference.as_str().unwrap_or_default();
        if targets.is_some_and(|t| !t.contains(reference)) {
            diagnostics.push(error("relaymark.evidence.unresolved_reference", format!("{kind} evidence reference '{reference}' does not resolve.")));
        }
    }
    match kind {
        "relay.action_row" => validate_action(block, diagnostics),
        "relay.source_bundle" => {
            if !props(block, "id").is_some_and(nonempty) {
                diagnostics.push(error("relaymark.source_bundle.identity", "relay.source_bundle requires a non-empty host id."));
            }
            if let Some(revision) = props(block, "revision")
                && (!json::is_integer(revision) || revision.as_f64().unwrap_or(-1.0) < 0.0)
            {
                diagnostics.push(error("relaymark.source_bundle.revision", "relay.source_bundle.revision must be a non-negative integer."));
            }
        }
        "relay.evidence_ref" => validate_evidence_ref(block, diagnostics, scripture),
        "relay.claim" => {
            if let Some(confidence) = props(block, "confidence").and_then(Value::as_f64)
                && !(0.0..=1.0).contains(&confidence)
            {
                diagnostics.push(error("relaymark.claim.confidence_range", "relay.claim.confidence must be between 0.0 and 1.0."));
            }
        }
        "relay.comparison" => validate_comparison(block, diagnostics),
        "relay.entity_reference" => {
            if !props(block, "id").is_some_and(nonempty) {
                diagnostics.push(error("relaymark.entity_reference.id", "relay.entity_reference.id must be a non-empty host reference."));
            }
            if props(block, "source").is_some() {
                let agrees = assert_entity_reference_props(block.get("props")).is_ok_and(|authored| {
                    let content = block.get("content").and_then(Value::as_array).map(Vec::as_slice).unwrap_or(&[]);
                    let parsed_body = content.len() == 1
                        && type_of(&content[0]) == Some("paragraph")
                        && content[0]["content"]
                            .as_array()
                            .is_some_and(|c| c.len() == 1 && type_of(&c[0]) == Some("text") && c[0]["text"] == authored.body.as_str());
                    content.is_empty() || parsed_body
                });
                if !agrees {
                    diagnostics.push(error(
                        "relaymark.entity_reference.source",
                        "relay.entity_reference.source must agree with identity, label, projection, and body.",
                    ));
                }
            }
        }
        "relay.paper_control" => {
            let valid = assert_control_props(block.get("props")).is_ok() && block.get("content").and_then(Value::as_array).is_some_and(Vec::is_empty);
            if !valid {
                diagnostics.push(error("relaymark.paper_control.source", "Paper control fields, source, and empty content must agree."));
            }
        }
        "relay.video_embed" => {
            if !props(block, "videoId")
                .and_then(Value::as_str)
                .is_some_and(|v| js_regex!(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$").is_match(v))
            {
                diagnostics.push(error("relaymark.video_embed.id", "relay.video_embed.videoId must be a canonical lowercase UUID."));
            }
            if block.get("content").and_then(Value::as_array).is_some_and(|c| !c.is_empty()) {
                diagnostics.push(error("relaymark.video_embed.children", "relay.video_embed cannot have children."));
            }
        }
        "relay.property_sheet" => {
            validate_binding(props(block, "binding"), "relay.property_sheet.binding", diagnostics);
            validate_distinct_keys(props(block, "fields"), "relay.property_sheet.fields", diagnostics);
        }
        "relay.data_view" => {
            validate_binding(props(block, "source"), "relay.data_view.source", diagnostics);
            for field in ["columns", "sort"] {
                if let Some(value) = props(block, field) {
                    validate_distinct_keys(Some(value), &format!("relay.data_view.{field}"), diagnostics);
                }
            }
            if props(block, "group").is_some_and(|g| !binding_segment(g)) {
                diagnostics.push(error("relaymark.data_view.group", "relay.data_view.group must be a host field key."));
            }
            if let Some(limit) = props(block, "limit")
                && (!json::is_integer(limit) || !(1.0..=1000.0).contains(&limit.as_f64().unwrap_or(0.0)))
            {
                diagnostics.push(error("relaymark.data_view.limit", "relay.data_view.limit must be an integer from 1 through 1000."));
            }
        }
        "relay.layout" => {
            if let Some(columns) = props(block, "columns")
                && (!json::is_integer(columns) || !(1.0..=4.0).contains(&columns.as_f64().unwrap_or(0.0)))
            {
                diagnostics.push(error("relaymark.layout.columns", "relay.layout.columns must be an integer from 1 through 4."));
            }
        }
        _ => {}
    }
}

fn validate_binding(value: Option<&Value>, label: &str, diagnostics: &mut Vec<Value>) {
    let valid = value.is_some_and(nonempty) && value.and_then(Value::as_str).is_some_and(|v| js_regex!(r"^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$").is_match(v));
    if !valid {
        diagnostics.push(error("relaymark.binding.invalid", format!("{label} must be a dotted host binding address.")));
    }
}

fn binding_segment(value: &Value) -> bool {
    nonempty(value) && value.as_str().is_some_and(|v| js_regex!(r"^-?[a-z][a-z0-9_]*$").is_match(v))
}

fn validate_distinct_keys(value: Option<&Value>, label: &str, diagnostics: &mut Vec<Value>) {
    let valid = value.and_then(Value::as_array).is_some_and(|items| {
        !items.is_empty() && items.iter().all(binding_segment) && items.iter().map(json::stringify).collect::<HashSet<_>>().len() == items.len()
    });
    if !valid {
        diagnostics.push(error("relaymark.binding.keys", format!("{label} must contain distinct, non-empty host field keys.")));
    }
}

fn validate_action(block: &Value, diagnostics: &mut Vec<Value>) {
    let p = |key: &str| props(block, key);
    if !p("action").is_some_and(nonempty) || !p("action").and_then(Value::as_str).is_some_and(|a| js_regex!(r"^[a-z][a-z0-9_.-]*$").is_match(a)) {
        diagnostics.push(error("relaymark.action.id", "relay.action_row.action must be a stable registered action id."));
    }
    let lifecycle = ["proposal_record_id", "proposal_revision", "decision_id", "execution_id", "undo_id"];
    let review = p("review").and_then(Value::as_str);
    let aware = review == Some("undone") || p("proposal_id").is_some() || lifecycle.iter().any(|field| p(field).is_some());
    if !aware {
        return;
    }
    if !p("proposal_id").is_some_and(nonempty) {
        diagnostics.push(error("relaymark.action.proposal_id", "relay.action_row lifecycle fields require a non-empty proposal_id."));
        return;
    }
    if !p("proposal_record_id").is_some_and(nonempty) {
        diagnostics.push(error(
            "relaymark.action.proposal_record_id",
            "relay.action_row lifecycle fields require a non-empty proposal_record_id for authorized review and undo.",
        ));
    } else if p("proposal_record_id") == p("proposal_id") {
        diagnostics
            .push(error("relaymark.action.proposal_identity", "relay.action_row.proposal_record_id must be distinct from the generator/client proposal_id."));
    }
    if !p("proposal_revision").is_some_and(|r| json::is_integer(r) && r.as_f64().unwrap_or(0.0) >= 1.0) {
        diagnostics
            .push(error("relaymark.action.proposal_revision", "relay.action_row.proposal_revision must be a positive integer for lifecycle-aware proposals."));
    }
    for field in ["decision_id", "execution_id", "undo_id"] {
        if p(field).is_some_and(|v| !nonempty(v)) {
            diagnostics.push(error("relaymark.action.lifecycle_id", format!("relay.action_row.{field} must be a non-empty string when present.")));
        }
    }
    let has = |field: &str| p(field).is_some();
    let filled = |field: &str| p(field).is_some_and(nonempty);
    match review {
        Some(state @ ("draft" | "ready")) => {
            if ["decision_id", "execution_id", "undo_id"].iter().any(|f| has(f)) {
                diagnostics.push(error(
                    "relaymark.action.lifecycle_state",
                    format!("relay.action_row in {state} review must not carry decision, execution, or undo ids."),
                ));
            }
        }
        Some("accepted") => {
            if !filled("decision_id") || !filled("execution_id") || has("undo_id") {
                diagnostics.push(error(
                    "relaymark.action.lifecycle_state",
                    "Accepted relay.action_row proposals require decision_id and execution_id and must not carry undo_id.",
                ));
            }
        }
        Some("rejected") => {
            if !filled("decision_id") || has("execution_id") || has("undo_id") {
                diagnostics.push(error(
                    "relaymark.action.lifecycle_state",
                    "Rejected relay.action_row proposals require decision_id and must not carry execution_id or undo_id.",
                ));
            }
        }
        Some("undone") => {
            if !filled("decision_id") || !filled("execution_id") || !filled("undo_id") || p("decision_id") == p("undo_id") {
                diagnostics.push(error(
                    "relaymark.action.lifecycle_state",
                    "Undone relay.action_row proposals retain the accept decision_id and execution_id and require a distinct undo_id.",
                ));
            }
        }
        _ => {}
    }
}

fn validate_evidence_ref(block: &Value, diagnostics: &mut Vec<Value>, scripture: &Scripture<'_>) {
    let p = |key: &str| props(block, key);
    if !p("id").is_some_and(nonempty) || !p("source").is_some_and(nonempty) {
        diagnostics.push(error("relaymark.evidence.identity", "relay.evidence_ref requires non-empty id and source values."));
    }
    for field in ["source_type", "source_revision"] {
        if p(field).is_some_and(|v| !nonempty(v)) {
            diagnostics.push(error("relaymark.evidence.source", format!("relay.evidence_ref.{field} must be a non-empty string when present.")));
        }
    }
    if p("source_type").and_then(Value::as_str) == Some("scripture") {
        validate_scripture_evidence(block, scripture, diagnostics);
    }
}

fn sha256_digest(value: Option<&Value>) -> bool {
    value.and_then(Value::as_str).is_some_and(|v| js_regex!(r"^sha256:[0-9a-f]{64}$").is_match(v))
}

fn validate_scripture_resources(document: &Value, diagnostics: &mut Vec<Value>) {
    for resource in resources_of(document) {
        if resource.get("type").and_then(Value::as_str) != Some("scripture") {
            continue;
        }
        let id = or_unknown(resource.get("id"));
        let empty = json!({});
        let p = resource.get("props").filter(|p| json::truthy(Some(p))).unwrap_or(&empty);
        for field in ["profile", "translation_id", "edition_id", "corpus_release_id", "versification_id", "attribution"] {
            if !p.get(field).is_some_and(nonempty) {
                diagnostics.push(error("relaymark.scripture.release", format!("scripture resource '{id}' requires {field}.")));
            }
        }
        if p.get("profile").and_then(Value::as_str) != Some("relaymark.scripture_release") {
            diagnostics.push(error("relaymark.scripture.release_profile", format!("scripture resource '{id}' must use relaymark.scripture_release.")));
        }
        for (label, fields) in [
            ("source", &["name", "uri", "digest"][..]),
            ("license", &["id", "name", "url"][..]),
            ("provenance", &["coordinate_inventory_digest", "normalized_index_input_digest"][..]),
        ] {
            match p.get(label).and_then(Value::as_object) {
                None => diagnostics.push(error("relaymark.scripture.release", format!("scripture resource '{id}' requires a {label} object."))),
                Some(object) => {
                    for field in fields {
                        if !object.get(*field).is_some_and(nonempty) {
                            diagnostics.push(error("relaymark.scripture.release", format!("scripture resource '{id}' requires {label}.{field}.")));
                        }
                    }
                }
            }
        }
        let digest = |value: Option<&Value>, field: &str, diagnostics: &mut Vec<Value>| {
            if !sha256_digest(value) {
                diagnostics.push(error("relaymark.scripture.digest", format!("scripture resource '{id}' requires {field} as a lowercase sha256 digest.")));
            }
        };
        let nested = |outer: &str, inner: &str| p.get(outer).and_then(|o| o.as_object()).and_then(|o| o.get(inner));
        digest(nested("source", "digest"), "source.digest", diagnostics);
        digest(nested("provenance", "coordinate_inventory_digest"), "provenance.coordinate_inventory_digest", diagnostics);
        digest(nested("provenance", "normalized_index_input_digest"), "provenance.normalized_index_input_digest", diagnostics);
        if let Some(archive) = nested("provenance", "source_archive_digest") {
            digest(Some(archive), "provenance.source_archive_digest", diagnostics);
        }
        if !resource.get("scope").and_then(Value::as_str).is_some_and(|s| ["private", "org", "unlisted", "public"].contains(&s)) {
            diagnostics.push(error("relaymark.scripture.release_scope", format!("scripture resource '{id}' requires an explicit valid scope.")));
        }
    }
}

fn collect_scripture_resources(document: &Value) -> Scripture<'_> {
    let mut resources: Scripture<'_> = HashMap::new();
    for resource in resources_of(document) {
        if resource.get("type").and_then(Value::as_str) != Some("scripture") || !resource.get("id").is_some_and(nonempty) {
            continue;
        }
        resources.entry(resource["id"].as_str().unwrap_or_default().to_owned()).or_default().push(resource);
    }
    resources
}

fn scope_rank(scope: Option<&Value>) -> Option<usize> {
    let scope = scope?.as_str()?;
    ["private", "org", "unlisted", "public"].iter().position(|s| *s == scope)
}

fn plain_text(node: &Value) -> String {
    match node {
        Value::Array(items) => items.iter().map(plain_text).collect(),
        Value::Object(_) if node.get("type").and_then(Value::as_str) == Some("text") => text(node.get("text")),
        Value::Object(_) => node.get("content").and_then(Value::as_array).map(|c| c.iter().map(plain_text).collect()).unwrap_or_default(),
        _ => String::new(),
    }
}

fn validate_scripture_evidence(block: &Value, scripture: &Scripture<'_>, diagnostics: &mut Vec<Value>) {
    let source = props(block, "source");
    let key = source.and_then(Value::as_str).unwrap_or_default();
    let matches = scripture.get(key).map(Vec::as_slice).unwrap_or(&[]);
    if matches.len() != 1 {
        let shown = if json::truthy(source) { text(source) } else { String::new() };
        diagnostics.push(error(
            "relaymark.scripture.source_resolution",
            format!("relay.evidence_ref scripture source '{shown}' must resolve to exactly one scripture resource."),
        ));
        return;
    }
    let resource = matches[0];
    let release = resource.get("props");
    if props(block, "source_revision") != release.and_then(|r| r.get("corpus_release_id")) {
        diagnostics
            .push(error("relaymark.scripture.source_revision", "relay.evidence_ref.source_revision must equal the scripture resource corpus_release_id."));
    }
    let allowed = matches!((scope_rank(resource.get("scope")), scope_rank(props(block, "scope"))), (Some(resource), Some(evidence)) if evidence <= resource);
    if !allowed {
        diagnostics.push(error("relaymark.scripture.scope", "relay.evidence_ref scope must not be broader than its scripture resource scope."));
    }
    let Some(selector) = props(block, "selector").filter(|s| s.is_object()) else {
        diagnostics.push(error("relaymark.scripture.selector", "Scripture evidence requires a scripture span selector."));
        return;
    };
    if selector.get("profile").and_then(Value::as_str) != Some("relaymark.scripture_span") {
        diagnostics.push(error("relaymark.scripture.selector_profile", "Scripture evidence selector must use relaymark.scripture_span."));
    }
    let start_valid = validate_coordinate(selector.get("start"), "start", diagnostics);
    let end_valid = validate_coordinate(selector.get("end"), "end", diagnostics);
    if start_valid
        && end_valid
        && (selector["start"]["book_id"] != selector["end"]["book_id"] || selector["start"]["coordinate_kind"] != selector["end"]["coordinate_kind"])
    {
        diagnostics.push(error("relaymark.scripture.span_boundary", "Scripture span start and end must use the same book and coordinate kind."));
    }
    if !sha256_digest(selector.get("content_digest")) {
        diagnostics.push(error("relaymark.scripture.content_digest", "Scripture evidence requires a lowercase sha256 content_digest."));
    }
    if !nonempty(&Value::String(plain_text(block))) {
        diagnostics.push(error("relaymark.scripture.excerpt", "Scripture evidence requires a non-empty exact excerpt."));
    }
}

fn validate_coordinate(coordinate: Option<&Value>, endpoint: &str, diagnostics: &mut Vec<Value>) -> bool {
    let Some(coordinate) = coordinate.filter(|c| c.is_object()) else {
        diagnostics.push(error("relaymark.scripture.coordinate", format!("Scripture selector {endpoint} must be a coordinate object.")));
        return false;
    };
    let common = coordinate.get("book_id").is_some_and(nonempty) && coordinate.get("verse_label").is_some_and(nonempty);
    let shape = match coordinate.get("coordinate_kind").and_then(Value::as_str) {
        Some("chapter") => {
            coordinate.get("chapter").is_some_and(|c| json::is_integer(c) && c.as_f64().unwrap_or(0.0) > 0.0) && coordinate.get("section_id").is_none()
        }
        Some("section") => coordinate.get("section_id").is_some_and(nonempty) && coordinate.get("chapter").is_none(),
        _ => false,
    };
    if !common || !shape {
        diagnostics.push(error(
            "relaymark.scripture.coordinate",
            format!("Scripture selector {endpoint} must be a lossless chapter or section coordinate with a string verse_label."),
        ));
        return false;
    }
    true
}

fn heading_level(block: Option<&Value>) -> Option<f64> {
    let block = block?;
    let level = props(block, "level")?;
    (type_of(block) == Some("heading") && json::is_integer(level)).then(|| level.as_f64().unwrap_or(0.0))
}

fn validate_agent_answer(document: &Value, diagnostics: &mut Vec<Value>, context: &Value) {
    let empty = json!({});
    let frontmatter = document.get("frontmatter").filter(|f| json::truthy(Some(f))).unwrap_or(&empty);
    if frontmatter.get("profile").and_then(Value::as_str) != Some("relaymark.agent_answer") {
        return;
    }
    if !frontmatter.get("title").is_some_and(nonempty) {
        diagnostics.push(error("relaymark.agent_answer.title", "relaymark.agent_answer requires a non-empty title."));
    }
    if !frontmatter.get("scope").and_then(Value::as_str).is_some_and(|s| ["private", "org", "unlisted", "public"].contains(&s)) {
        diagnostics.push(error("relaymark.agent_answer.scope", "relaymark.agent_answer requires an explicit private, org, unlisted, or public scope."));
    }
    match frontmatter.get("question").filter(|q| nonempty(q)).and_then(Value::as_str) {
        None => diagnostics.push(error("relaymark.agent_answer.question", "relaymark.agent_answer requires a non-empty exact question.")),
        Some(question) => {
            let expected = format!("sha256:{}", json::sha256_hex(question.as_bytes()));
            if frontmatter.get("question_id").and_then(Value::as_str) != Some(expected.as_str()) {
                diagnostics.push(error(
                    "relaymark.agent_answer.question_id",
                    "relaymark.agent_answer question_id must be the lowercase SHA-256 digest of the exact question UTF-8 bytes.",
                ));
            }
        }
    }
    match frontmatter.get("outcome").and_then(Value::as_str) {
        Some("answered") => validate_answered(document, diagnostics, context),
        Some("refused") => validate_refused(document, diagnostics),
        _ => diagnostics.push(error("relaymark.agent_answer.outcome", "relaymark.agent_answer outcome must be answered or refused.")),
    }
}

fn validate_answered(document: &Value, diagnostics: &mut Vec<Value>, context: &Value) {
    let blocks = blocks_of(document);
    let evidence_heading = blocks.iter().position(|b| heading_level(Some(b)) == Some(2.0) && plain_text(b) == "Evidence");
    let claims: &[Value] = match evidence_heading {
        Some(index) if index > 1 => &blocks[1..index],
        _ => &[],
    };
    let bundles: &[Value] = match evidence_heading {
        Some(index) => &blocks[index + 1..],
        None => &[],
    };
    let (mut level_one, mut level_two) = (0, 0);
    visit_blocks(blocks, &mut |block| match heading_level(Some(block)) {
        Some(1.0) => level_one += 1,
        Some(2.0) => level_two += 1,
        _ => {}
    });
    let structure = blocks.len() >= 4
        && heading_level(blocks.first()) == Some(1.0)
        && level_one == 1
        && level_two == 1
        && !claims.is_empty()
        && claims.iter().all(|b| type_of(b) == Some("relay.claim"))
        && !bundles.is_empty()
        && bundles.iter().all(|b| type_of(b) == Some("relay.source_bundle"));
    if !structure {
        diagnostics.push(error(
            "relaymark.agent_answer.answered_structure",
            "An answered relaymark.agent_answer paper requires one level-one heading, supported claims, an Evidence level-two heading, and source bundles in that order.",
        ));
    }
    let mut counts: HashMap<String, usize> = HashMap::new();
    let mut evidence_blocks: HashMap<String, Vec<&Value>> = HashMap::new();
    for bundle in bundles.iter().filter(|b| type_of(b) == Some("relay.source_bundle")) {
        visit_blocks(std::slice::from_ref(bundle), &mut |block| {
            if type_of(block) != Some("relay.evidence_ref") || !props(block, "id").is_some_and(nonempty) {
                return;
            }
            let id = props(block, "id").and_then(Value::as_str).unwrap_or_default().to_owned();
            *counts.entry(id.clone()).or_default() += 1;
            evidence_blocks.entry(id).or_default().push(block);
        });
    }
    for claim in claims.iter().filter(|b| type_of(b) == Some("relay.claim")) {
        let refs = evidence_refs_for(claim);
        let claim_id = or_unknown(claim.get("id"));
        if !props(claim, "key").is_some_and(nonempty)
            || props(claim, "status").and_then(Value::as_str) != Some("supported")
            || !nonempty(&Value::String(plain_text(claim)))
        {
            diagnostics
                .push(error("relaymark.agent_answer.claim", format!("Answered claim '{claim_id}' requires a non-empty key and text with supported status.")));
        }
        let distinct = refs.iter().map(json::stringify).collect::<HashSet<_>>().len();
        let unresolved = refs.iter().any(|r| !nonempty(r) || counts.get(r.as_str().unwrap_or_default()) != Some(&1));
        if refs.is_empty() || distinct != refs.len() || unresolved {
            diagnostics.push(error(
                "relaymark.agent_answer.claim_evidence",
                format!("Answered claim '{claim_id}' must cite one or more unique concrete evidence refs that each resolve exactly once inside the paper's source bundles."),
            ));
        }
    }
    if context.get("surface").and_then(Value::as_str) == Some("scripture_ask") {
        let invalid = claims.iter().filter(|b| type_of(b) == Some("relay.claim")).any(|claim| {
            evidence_refs_for(claim).iter().any(|reference| {
                let matches = reference.as_str().and_then(|r| evidence_blocks.get(r)).map(Vec::as_slice).unwrap_or(&[]);
                matches.len() != 1 || props(matches[0], "source_type").and_then(Value::as_str) != Some("scripture")
            })
        });
        if invalid {
            diagnostics.push(error(
                "relaymark.agent_answer.scripture_evidence",
                "A Scripture Ask host context requires every answered claim evidence ref to resolve to relay.evidence_ref source_type scripture.",
            ));
        }
    }
    let mut forbidden = false;
    visit_blocks(blocks, &mut |block| forbidden |= matches!(type_of(block), Some("relay.agent_suggestion" | "relay.action_row")));
    if forbidden {
        diagnostics
            .push(error("relaymark.agent_answer.read_only", "An answered relaymark.agent_answer paper must not contain agent suggestions or action rows."));
    }
    if document.get("frontmatter").and_then(|f| f.get("refusal_reason")).is_some() {
        diagnostics.push(error("relaymark.agent_answer.refusal_reason", "An answered relaymark.agent_answer paper must not contain refusal_reason."));
    }
}

fn validate_refused(document: &Value, diagnostics: &mut Vec<Value>) {
    let blocks = blocks_of(document);
    let (mut nested, mut level_one) = (0, 0);
    visit_blocks(blocks, &mut |block| {
        nested += 1;
        if heading_level(Some(block)) == Some(1.0) {
            level_one += 1;
        }
    });
    if document.get("frontmatter").and_then(|f| f.get("refusal_reason")).and_then(Value::as_str) != Some("insufficient_evidence") {
        diagnostics
            .push(error("relaymark.agent_answer.refusal_reason", "A refused relaymark.agent_answer paper requires refusal_reason insufficient_evidence."));
    }
    let structure = blocks.len() == 2
        && nested == 2
        && heading_level(blocks.first()) == Some(1.0)
        && level_one == 1
        && plain_text(&blocks[0]) == "Answer unavailable"
        && type_of(&blocks[1]) == Some("paragraph")
        && nonempty(&Value::String(plain_text(&blocks[1])));
    if !structure {
        diagnostics.push(error(
            "relaymark.agent_answer.refused_structure",
            "A refused relaymark.agent_answer paper requires only an Answer unavailable level-one heading followed by one non-empty explanation paragraph.",
        ));
    }
    let mut forbidden = false;
    visit_blocks(blocks, &mut |block| {
        forbidden |=
            matches!(type_of(block), Some("relay.claim" | "relay.source_bundle" | "relay.evidence_ref" | "relay.agent_suggestion" | "relay.action_row"));
    });
    if forbidden || !resources_of(document).is_empty() {
        diagnostics.push(error(
            "relaymark.agent_answer.refused_content",
            "A refused relaymark.agent_answer paper must not contain claims, sources, resources, evidence, suggestions, or actions.",
        ));
    }
}

fn validate_comparison(block: &Value, diagnostics: &mut Vec<Value>) {
    let empty = Vec::new();
    let subjects = props(block, "subjects").and_then(Value::as_array).unwrap_or(&empty);
    let criteria = props(block, "criteria").and_then(Value::as_array).unwrap_or(&empty);
    let valid_subjects: Vec<&str> = subjects.iter().filter(|s| nonempty(s)).filter_map(Value::as_str).collect();
    let valid_criteria: Vec<&str> = criteria.iter().filter(|s| nonempty(s)).filter_map(Value::as_str).collect();
    let unique = |items: &[&str]| items.iter().collect::<HashSet<_>>().len() == items.len();
    if valid_subjects.len() < 2 || !unique(&valid_subjects) {
        diagnostics.push(error("relaymark.comparison.subjects", "relay.comparison.subjects must contain at least two distinct, non-empty references."));
    }
    if valid_criteria.is_empty() || !unique(&valid_criteria) {
        diagnostics.push(error("relaymark.comparison.criteria", "relay.comparison.criteria must contain at least one distinct, non-empty key."));
    }
    if let Some(preferred) = props(block, "preferred").filter(|p| p.is_string())
        && !subjects.contains(preferred)
    {
        diagnostics.push(error("relaymark.comparison.preferred", "relay.comparison.preferred must be one of relay.comparison.subjects."));
    }
    if let Some(values) = props(block, "values").and_then(Value::as_object) {
        let mut seen_criteria = HashSet::new();
        for criterion in valid_criteria.iter().filter(|c| seen_criteria.insert(**c)) {
            let Some(criterion_values) = values.get(*criterion).and_then(Value::as_object) else {
                diagnostics.push(error(
                    "relaymark.comparison.values_criterion",
                    format!("relay.comparison.values.{criterion} must be an object keyed by subject reference."),
                ));
                continue;
            };
            let mut seen_subjects = HashSet::new();
            for subject in valid_subjects.iter().filter(|s| seen_subjects.insert(**s)) {
                if !criterion_values.contains_key(*subject) {
                    diagnostics.push(error(
                        "relaymark.comparison.values_coverage",
                        format!("relay.comparison.values.{criterion} must include '{subject}' with a value or explicit null."),
                    ));
                }
            }
        }
    }
}

fn collect_evidence_targets(document: &Value) -> HashSet<String> {
    let mut targets = HashSet::new();
    let mut add = |value: Option<&Value>| {
        if let Some(text) = value.filter(|v| nonempty(v)).and_then(Value::as_str) {
            targets.insert(text.to_owned());
        }
    };
    for resource in resources_of(document) {
        add(resource.get("id"));
    }
    visit_blocks(blocks_of(document), &mut |block| {
        add(block.get("id"));
        match type_of(block) {
            Some("relay.source_bundle" | "relay.evidence_ref" | "relay.file_ref") => add(props(block, "id")),
            Some("relay.transcript_segment") => add(props(block, "source")),
            Some("relay.note_ref") => {
                add(props(block, "document"));
                add(props(block, "block"));
            }
            _ => {}
        }
    });
    targets
}

fn validate_identities(document: &Value, diagnostics: &mut Vec<Value>) {
    let mut namespaces: HashMap<&str, HashMap<String, String>> = HashMap::new();
    visit_blocks(blocks_of(document), &mut |block| {
        if let Some(id) = block.get("id").filter(|i| nonempty(i)).and_then(Value::as_str) {
            namespaces.entry("evidence").or_default().entry(id.to_owned()).or_insert_with(|| format!("AST block '{id}'"));
        }
    });
    let mut register = |namespace: &'static str, value: Option<&Value>, origin: String, diagnostics: &mut Vec<Value>| {
        let Some(value) = value.filter(|v| nonempty(v)).and_then(Value::as_str) else { return };
        let registry = namespaces.entry(namespace).or_default();
        match registry.get(value) {
            Some(prior) => diagnostics
                .push(error(format!("relaymark.identity.duplicate_{namespace}"), format!("Identity '{value}' is ambiguous between {prior} and {origin}."))),
            None => {
                registry.insert(value.to_owned(), origin);
            }
        }
    };
    for resource in resources_of(document) {
        register("evidence", resource.get("id"), format!("resource '{}'", text_or_undefined(resource.get("id"))), diagnostics);
    }
    let mut blocks_in_order = Vec::new();
    visit_blocks(blocks_of(document), &mut |block| blocks_in_order.push(block));
    for block in blocks_in_order {
        let kind = type_of(block).unwrap_or_default();
        let block_id = text_or_undefined(block.get("id"));
        if (kind == "relay.source_bundle" || kind == "relay.evidence_ref") && props(block, "id") != block.get("id") {
            register("evidence", props(block, "id"), format!("{kind}.props.id on block '{block_id}'"), diagnostics);
        }
        if kind != "relay.action_row" {
            continue;
        }
        for (field, namespace) in [
            ("proposal_id", "proposal"),
            ("proposal_record_id", "proposal_record"),
            ("decision_id", "decision"),
            ("execution_id", "execution"),
            ("undo_id", "undo"),
        ] {
            register(namespace, props(block, field), format!("relay.action_row.{field} on block '{block_id}'"), diagnostics);
        }
    }
}

/// Template-literal spelling of an optional value.
fn text_or_undefined(value: Option<&Value>) -> String {
    match value {
        None => "undefined".into(),
        Some(Value::String(text)) => text.clone(),
        Some(other) => json::stringify(other),
    }
}

fn validate_attribute(kind: &str, name: &str, value: &Value, attribute: &Value, diagnostics: &mut Vec<Value>) {
    if value.is_null() && attribute.get("nullable").and_then(Value::as_bool) == Some(true) {
        return;
    }
    let field = format!("{kind}.{name}");
    match attribute.get("type").and_then(Value::as_str) {
        Some("enum") => {
            let values = attribute.get("values").and_then(Value::as_array);
            if !values.is_some_and(|v| v.contains(value) && !value.is_object() && !value.is_array()) {
                let listed = values.into_iter().flatten().map(|v| text(Some(v))).collect::<Vec<_>>().join(", ");
                diagnostics.push(error("relaymark.attribute.enum", format!("{field} must be one of {listed}.")));
            }
        }
        Some("array") => match value.as_array() {
            None => diagnostics.push(error("relaymark.attribute.array", format!("{field} must be an array."))),
            Some(items) if attribute.get("items").and_then(Value::as_str) == Some("string") && items.iter().any(|i| !i.is_string()) => {
                diagnostics.push(error("relaymark.attribute.array_items", format!("{field} must contain only strings.")));
            }
            Some(_) => {}
        },
        Some("integer") if !json::is_integer(value) => diagnostics.push(error("relaymark.attribute.integer", format!("{field} must be an integer."))),
        Some("number") if !value.is_number() => diagnostics.push(error("relaymark.attribute.number", format!("{field} must be a number."))),
        Some("boolean") if !value.is_boolean() => diagnostics.push(error("relaymark.attribute.boolean", format!("{field} must be a boolean."))),
        Some("object") if !value.is_object() => diagnostics.push(error("relaymark.attribute.object", format!("{field} must be an object."))),
        Some("string") if !value.is_string() => diagnostics.push(error("relaymark.attribute.string", format!("{field} must be a string."))),
        _ => {}
    }
}
