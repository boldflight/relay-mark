//! The two HTML rule sets. Canonical rules (document-html-rules.js) read the
//! HTML Relay itself renders, strictly: every element, attribute and atom
//! display must be accounted for. Foreign rules (document-html-foreign.js) read
//! clipboard HTML other applications write, as the web editor's TipTap
//! extensions read a paste.

use std::sync::OnceLock;

use regex::Regex;
use serde_json::Value;

use crate::error::{Result, bail};
use crate::json::{self, Map};
use crate::links::{link_defaults, safe_image_source, safe_link_href, validate_link_attributes};
use crate::registry::registry;
use crate::source::js_number;

use super::dom::{Dom, Id};
use super::model::{TypeId, schema};
use super::parser::{Attrs, ContentElement, Matcher, Parser, StyleRule, TagRule, Target, Whitespace, style_value};

type Legacy = Box<dyn Fn(&Dom, Id) -> Result<Map> + Send + Sync>;

/// `tag` plus required (`[attr]`), required-value (`[attr="value"]`) and
/// excluded (`:not([attr])`, `:not([attr="value"])`) attribute conditions.
fn selector(tag: &'static str, require: &'static [(&'static str, Option<&'static str>)], exclude: &'static [(&'static str, Option<&'static str>)]) -> Matcher {
    let holds = |dom: &Dom, id: Id, (name, value): &(&str, Option<&str>)| match value {
        Some(value) => dom.attr(id, name) == Some(value),
        None => dom.has_attr(id, name),
    };
    Box::new(move |dom, id| dom.is_html(id) && dom.name(id) == tag && require.iter().all(|c| holds(dom, id, c)) && !exclude.iter().any(|c| holds(dom, id, c)))
}

fn either(a: Matcher, b: Matcher) -> Matcher {
    Box::new(move |dom, id| a(dom, id) || b(dom, id))
}

fn text_attr(dom: &Dom, id: Id, name: &str) -> Value {
    dom.attr(id, name).map_or(Value::Null, |value| Value::String(value.to_owned()))
}

fn map(entries: Vec<(&str, Value)>) -> Map {
    entries.into_iter().map(|(key, value)| (key.to_owned(), value)).collect()
}

/// Canonical `number(element, name, fallback)`.
fn html_integer(dom: &Dom, id: Id, name: &str, fallback: Value) -> Result<Value> {
    let Some(value) = dom.attr(id, name) else { return Ok(fallback) };
    let digits = value.strip_prefix('-').unwrap_or(value);
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        bail!("Invalid HTML integer {name}");
    }
    let number: f64 = value.parse().unwrap_or(f64::NAN);
    if !(number.fract() == 0.0 && number.abs() <= 9_007_199_254_740_991.0) {
        bail!("Invalid HTML integer {name}");
    }
    Ok(js_number(number))
}

fn html_boolean(dom: &Dom, id: Id, name: &str) -> Result<Value> {
    match dom.attr(id, name) {
        None => Ok(Value::Bool(false)),
        Some("true") => Ok(Value::Bool(true)),
        Some("false") => Ok(Value::Bool(false)),
        Some(_) => bail!("Invalid HTML boolean {name}"),
    }
}

fn question_settings(dom: &Dom, id: Id) -> Result<Value> {
    let value = match dom.attr(id, "data-settings") {
        None => Value::Object(Map::new()),
        Some(raw) => json::parse(raw)?,
    };
    if !value.is_object() {
        bail!("Invalid retained question settings");
    }
    Ok(value)
}

fn question_number(dom: &Dom, id: Id, name: &str) -> Result<Value> {
    static NUMBER: OnceLock<Regex> = OnceLock::new();
    let Some(raw) = dom.attr(id, name) else { return Ok(Value::Null) };
    let pattern = NUMBER.get_or_init(|| Regex::new(r"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$").expect("regex"));
    let number: f64 = raw.parse().unwrap_or(f64::NAN);
    if !pattern.is_match(raw) || !number.is_finite() {
        bail!("Invalid retained question number");
    }
    Ok(js_number(number))
}

fn task_type(dom: &Dom, id: Id, expected: &str) -> Result<()> {
    match dom.attr(id, "data-type") {
        Some(found) if found != expected => bail!("Conflicting task HTML type"),
        _ => Ok(()),
    }
}

/// A canonical node rule.
pub struct Def {
    pub name: &'static str,
    matches: Matcher,
    allowed: Vec<&'static str>,
    legacy: Legacy,
    content: fn() -> ContentElement,
    preserve_full: bool,
    presentation_class: Option<&'static str>,
    complete_authored_fields: bool,
    display: Option<fn(&Map) -> Option<Value>>,
    pub tag: &'static str,
}

/// A canonical mark rule.
pub struct MarkDef {
    pub name: &'static str,
    tag: &'static str,
    matches: Matcher,
    allowed: Vec<&'static str>,
    attrs: fn(&Dom, Id) -> Result<Map>,
}

fn itself() -> ContentElement {
    ContentElement::Itself
}

fn code_child() -> ContentElement {
    ContentElement::Descendant("code")
}

/// The maintained TipTap task node view wraps only the authored body in a div;
/// its sibling label is presentation.
fn task_content() -> ContentElement {
    ContentElement::Pick(Box::new(|dom: &Dom, id: Id| {
        let children = dom.element_children(id);
        if dom.attr(id, "data-type") == Some("taskItem") && children.len() == 2 && dom.name(children[0]) == "label" && dom.name(children[1]) == "div" {
            children[1]
        } else {
            id
        }
    }))
}

struct Builder {
    defs: Vec<Def>,
}

impl Builder {
    fn node(&mut self, name: &'static str, tag: &'static str, matches: Matcher, allowed: &[&'static str], legacy: Legacy) -> &mut Def {
        let mut all = vec!["data-authored", "data-relaymark-id"];
        all.extend_from_slice(allowed);
        self.defs.push(Def {
            name,
            tag,
            matches,
            allowed: all,
            legacy,
            content: itself,
            preserve_full: false,
            presentation_class: None,
            complete_authored_fields: false,
            display: None,
        });
        self.defs.last_mut().expect("def")
    }
}

fn none() -> Legacy {
    Box::new(|_, _| Ok(Map::new()))
}

fn display_field(field: &'static str) -> fn(&Map) -> Option<Value> {
    match field {
        "label" => |attrs| attrs.get("label").cloned(),
        "name" => |attrs| attrs.get("name").cloned(),
        "content" => |attrs| attrs.get("content").cloned(),
        "provider" => |attrs| attrs.get("provider").cloned(),
        _ => |_| Some(Value::String(String::new())),
    }
}

pub fn defs() -> &'static [Def] {
    static DEFS: OnceLock<Vec<Def>> = OnceLock::new();
    DEFS.get_or_init(build_defs)
}

fn build_defs() -> Vec<Def> {
    let mut b = Builder { defs: Vec::new() };
    b.node("paragraph", "p", selector("p", &[], &[("data-callout-title", None)]), &[], none());
    b.node("blockquote", "blockquote", selector("blockquote", &[], &[]), &[], none());
    b.node("listItem", "li", selector("li", &[], &[("data-relay-task-item", None), ("data-checked", None), ("data-type", Some("taskItem"))]), &[], none());
    b.node(
        "taskList",
        "ul",
        either(selector("ul", &[("data-relay-task-list", None)], &[]), selector("ul", &[("data-type", Some("taskList"))], &[])),
        &["data-relay-task-list", "data-type"],
        Box::new(|dom, id| {
            task_type(dom, id, "taskList")?;
            Ok(Map::new())
        }),
    );
    b.node("bulletList", "ul", selector("ul", &[], &[("data-relay-task-list", None), ("data-type", Some("taskList"))]), &[], none());
    b.node(
        "orderedList",
        "ol",
        selector("ol", &[], &[]),
        &["start"],
        Box::new(|dom, id| Ok(map(vec![("start", html_integer(dom, id, "start", js_number(1.0))?)]))),
    );
    b.node(
        "taskItem",
        "li",
        either(selector("li", &[("data-checked", None)], &[]), selector("li", &[("data-type", Some("taskItem"))], &[])),
        &["data-checked", "data-relay-task-item", "data-entity-id", "data-type"],
        Box::new(|dom, id| {
            task_type(dom, id, "taskItem")?;
            let canonical = dom.attr(id, "data-relay-task-item");
            let native = dom.attr(id, "data-entity-id");
            if let (Some(a), Some(b)) = (canonical, native)
                && a != b
            {
                bail!("Conflicting task HTML entity identity");
            }
            let checked = if dom.attr(id, "data-checked") == Some("") && dom.attr(id, "data-type") == Some("taskItem") {
                Value::Bool(true)
            } else {
                html_boolean(dom, id, "data-checked")?
            };
            let entity = canonical.or(native).map_or(Value::Null, |value| Value::String(value.to_owned()));
            Ok(map(vec![("checked", checked), ("entityId", entity)]))
        }),
    )
    .content = task_content;
    for (level, tag) in ["h1", "h2", "h3", "h4", "h5", "h6"].into_iter().enumerate() {
        b.node(
            "heading",
            tag,
            selector(tag, &[], &[]),
            &["id", "data-relay-heading-id"],
            Box::new(move |dom, id| {
                let heading_id = dom.attr(id, "data-relay-heading-id").filter(|v| !v.is_empty()).or_else(|| dom.attr(id, "id"));
                Ok(map(vec![("level", js_number((level + 1) as f64)), ("headingId", heading_id.map_or(Value::Null, |v| Value::String(v.to_owned())))]))
            }),
        );
    }
    b.node("hardBreak", "br", selector("br", &[], &[]), &[], none());
    b.node("horizontalRule", "hr", selector("hr", &[], &[]), &[], none());
    let code = b.node(
        "codeBlock",
        "pre",
        selector("pre", &[], &[]),
        &[],
        Box::new(|dom, id| {
            let Some(&first) = dom.element_children(id).first() else { bail!("Cannot read properties of null (reading 'getAttribute')") };
            Ok(map(vec![("language", text_attr(dom, first, "data-language"))]))
        }),
    );
    code.preserve_full = true;
    code.content = code_child;
    b.node(
        "image",
        "img",
        selector("img", &[], &[]),
        &["src", "alt", "title", "width", "height"],
        Box::new(|dom, id| {
            Ok(map(vec![
                ("src", text_attr(dom, id, "src")),
                ("alt", text_attr(dom, id, "alt")),
                ("title", text_attr(dom, id, "title")),
                ("width", html_integer(dom, id, "width", Value::Null)?),
                ("height", html_integer(dom, id, "height", Value::Null)?),
            ]))
        }),
    );
    b.node("table", "table", selector("table", &[], &[]), &["style"], none());
    b.node("tableRow", "tr", selector("tr", &[], &[]), &[], none());
    for (name, tag) in [("tableCell", "td"), ("tableHeader", "th")] {
        b.node(name, tag, selector(tag, &[], &[]), &["colspan", "rowspan", "colwidth", "data-align", "style"], Box::new(cell_attributes));
    }
    b.node(
        "callout",
        "aside",
        selector("aside", &[("data-relay-callout", None)], &[]),
        &["data-relay-callout", "data-emphasis"],
        Box::new(|dom, id| {
            let emphasis = dom.attr(id, "data-emphasis").filter(|v| !v.is_empty()).unwrap_or("soft");
            Ok(map(vec![("tone", text_attr(dom, id, "data-relay-callout")), ("emphasis", Value::String(emphasis.to_owned()))]))
        }),
    );
    b.node("calloutTitle", "div", selector("div", &[("data-callout-title", None)], &[]), &["data-callout-title"], none());
    b.node(
        "callout",
        "section",
        selector("section", &[("data-relay-callout", None)], &[]),
        &["data-relay-callout", "data-tone", "data-emphasis", "class"],
        Box::new(|dom, id| {
            if dom.attr(id, "data-relay-callout") != Some("") {
                bail!("Conflicting callout HTML representation");
            }
            let tone = dom.attr(id, "data-tone").filter(|v| !v.is_empty()).unwrap_or("neutral");
            let emphasis = dom.attr(id, "data-emphasis").filter(|v| !v.is_empty()).unwrap_or("soft");
            Ok(map(vec![("tone", Value::String(tone.to_owned())), ("emphasis", Value::String(emphasis.to_owned()))]))
        }),
    )
    .presentation_class = Some("relay-callout");
    b.node("calloutTitle", "p", selector("p", &[("data-callout-title", None)], &[]), &["data-callout-title", "class"], none()).presentation_class =
        Some("relay-callout-title");
    b.node(
        "questionBlock",
        "fieldset",
        selector("fieldset", &[("data-relay-question", None)], &[]),
        &["data-relay-question", "data-question-type", "data-required"],
        Box::new(|dom, id| {
            Ok(map(vec![
                ("id", text_attr(dom, id, "data-relay-question")),
                ("type", text_attr(dom, id, "data-question-type")),
                ("required", html_boolean(dom, id, "data-required")?),
            ]))
        }),
    );
    b.node("questionLabel", "legend", selector("legend", &[], &[]), &[], none());
    b.node(
        "questionOption",
        "div",
        selector("div", &[("data-relay-option", None)], &[]),
        &["data-relay-option"],
        Box::new(|dom, id| Ok(map(vec![("id", text_attr(dom, id, "data-relay-option"))]))),
    );
    let question = b.node(
        "questionBlock",
        "div",
        selector("div", &[("data-question-block", None)], &[]),
        &["data-question-block", "class", "data-id", "data-type", "data-required", "data-points", "data-min", "data-max", "data-settings"],
        Box::new(|dom, id| {
            let kind = dom.attr(id, "data-type").filter(|v| !v.is_empty()).unwrap_or("short_text");
            Ok(map(vec![
                ("id", text_attr(dom, id, "data-id")),
                ("type", Value::String(kind.to_owned())),
                ("required", html_boolean(dom, id, "data-required")?),
                ("points", question_number(dom, id, "data-points")?),
                ("min", question_number(dom, id, "data-min")?),
                ("max", question_number(dom, id, "data-max")?),
                ("settings", question_settings(dom, id)?),
            ]))
        }),
    );
    question.presentation_class = Some("question-block-paper");
    question.complete_authored_fields = true;
    b.node("questionLabel", "div", selector("div", &[("data-question-label", None)], &[]), &["data-question-label", "class"], none()).presentation_class =
        Some("question-block-content");
    b.node(
        "questionOption",
        "div",
        selector("div", &[("data-question-option", None)], &[]),
        &["data-question-option", "data-id", "data-correct", "data-points", "data-settings"],
        Box::new(|dom, id| {
            Ok(map(vec![
                ("id", text_attr(dom, id, "data-id")),
                ("correct", html_boolean(dom, id, "data-correct")?),
                ("points", question_number(dom, id, "data-points")?),
                ("settings", question_settings(dom, id)?),
            ]))
        }),
    )
    .complete_authored_fields = true;
    b.node(
        "relayReference",
        "span",
        selector("span", &[("data-relay-reference", None)], &[]),
        &["data-relay-reference", "data-source"],
        Box::new(|dom, id| {
            Ok(map(vec![
                ("entityId", text_attr(dom, id, "data-relay-reference")),
                ("source", text_attr(dom, id, "data-source")),
                ("label", Value::String(dom.text_content(id))),
            ]))
        }),
    )
    .display = Some(display_field("label"));
    b.node(
        "relayEntityReference",
        "div",
        selector("div", &[("data-relay-reference", None)], &[]),
        &["data-relay-reference", "data-projection", "data-source"],
        Box::new(|dom, id| {
            Ok(map(vec![
                ("entityRef", text_attr(dom, id, "data-relay-reference")),
                ("projection", text_attr(dom, id, "data-projection")),
                ("source", text_attr(dom, id, "data-source")),
                ("label", Value::String(dom.text_content(id))),
            ]))
        }),
    )
    .display = Some(display_field("label"));
    b.node(
        "relayTag",
        "span",
        selector("span", &[("data-relay-tag", None)], &[]),
        &["data-relay-tag", "data-source"],
        Box::new(|dom, id| {
            Ok(map(vec![
                ("id", text_attr(dom, id, "data-relay-tag")),
                ("source", text_attr(dom, id, "data-source")),
                ("name", Value::String(dom.text_content(id))),
            ]))
        }),
    )
    .display = Some(display_field("name"));
    b.node(
        "videoEmbed",
        "div",
        selector("div", &[("data-relay-video", None)], &[]),
        &["data-relay-video"],
        Box::new(|dom, id| Ok(map(vec![("videoId", text_attr(dom, id, "data-relay-video"))]))),
    )
    .display = Some(display_field(""));
    b.node(
        "agentSuggestion",
        "aside",
        selector("aside", &[("data-relay-suggestion", None)], &[]),
        &["data-relay-suggestion", "data-kind"],
        Box::new(|dom, id| {
            Ok(map(vec![
                ("review", text_attr(dom, id, "data-relay-suggestion")),
                ("kind", text_attr(dom, id, "data-kind")),
                ("content", Value::String(dom.text_content(id))),
            ]))
        }),
    )
    .display = Some(display_field("content"));
    b.node(
        "relayDataView",
        "div",
        selector("div", &[("data-relay-data-view", None)], &[]),
        &["data-relay-data-view"],
        Box::new(|dom, id| Ok(map(vec![("source", text_attr(dom, id, "data-relay-data-view"))]))),
    )
    .display = Some(|attrs: &Map| match attrs.get("title") {
        Some(title) if json::truthy(Some(title)) => Some(title.clone()),
        _ => attrs.get("source").cloned(),
    });
    b.node(
        "relayButton",
        "button",
        selector("button", &[("data-relay-kind", None)], &[]),
        &["type", "disabled", "data-relay-kind", "data-relay-target"],
        Box::new(|dom, id| {
            Ok(map(vec![
                ("kind", text_attr(dom, id, "data-relay-kind")),
                ("target", text_attr(dom, id, "data-relay-target")),
                ("label", Value::String(dom.text_content(id))),
            ]))
        }),
    )
    .display = Some(display_field("label"));
    b.node(
        "relayAnchor",
        "span",
        selector("span", &[("data-relay-anchor", None)], &[]),
        &["data-relay-anchor"],
        Box::new(|dom, id| Ok(map(vec![("name", text_attr(dom, id, "data-relay-anchor"))]))),
    )
    .display = Some(display_field(""));
    b.node(
        "relayConnection",
        "div",
        selector("div", &[("data-relay-connection", None)], &[]),
        &["data-relay-connection"],
        Box::new(|dom, id| Ok(map(vec![("provider", text_attr(dom, id, "data-relay-connection"))]))),
    )
    .display = Some(display_field("provider"));
    for shape in &registry().nodes {
        let ast_type = shape.ast_type;
        b.node(
            shape.name,
            "section",
            Box::new(move |dom: &Dom, id: Id| dom.is_html(id) && dom.name(id) == "section" && dom.attr(id, "data-relay-directive") == Some(ast_type)),
            &["data-relay-directive"],
            Box::new(|_, _| bail!("Missing authored directive HTML attributes")),
        );
    }
    b.defs
}

fn cell_attributes(dom: &Dom, id: Id) -> Result<Map> {
    let colwidth = match dom.attr(id, "colwidth") {
        None => Value::Null,
        Some(raw) => {
            let mut widths = Vec::new();
            for value in raw.split(',') {
                if value.is_empty() || !value.bytes().all(|b| b.is_ascii_digit()) {
                    bail!("Invalid HTML column width");
                }
                widths.push(js_number(value.parse().unwrap_or(f64::NAN)));
            }
            Value::Array(widths)
        }
    };
    Ok(map(vec![
        ("colspan", html_integer(dom, id, "colspan", js_number(1.0))?),
        ("rowspan", html_integer(dom, id, "rowspan", js_number(1.0))?),
        ("colwidth", colwidth),
        ("align", text_attr(dom, id, "data-align")),
    ]))
}

impl Def {
    pub fn matches(&self, dom: &Dom, id: Id) -> bool {
        (self.matches)(dom, id)
    }

    /// Canonical `attributes(name, element, legacy)`.
    pub fn attributes(&self, dom: &Dom, id: Id) -> Result<Map> {
        let schema = schema();
        let ty = schema.node_type(self.name).expect("canonical node type");
        let encoded = dom.attr(id, "data-authored");
        let value = match encoded {
            None => Value::Object((self.legacy)(dom, id)?),
            Some(text) => json::parse(text)?,
        };
        let Some(value) =
            value.as_object().filter(|v| v.keys().all(|key| schema.node_attrs(ty, None).is_ok_and(|a| a.contains_key(key)) && key != "relaymarkId"))
        else {
            bail!("Invalid authored HTML attributes {}", self.name)
        };
        let mut value = value.clone();
        let directive = registry().nodes.iter().any(|shape| shape.name == self.name);
        if encoded.is_some() && !directive {
            for (key, actual) in (self.legacy)(dom, id)? {
                if self.name == "heading" && key == "headingId" {
                    continue;
                }
                if let Some(given) = value.get(&key)
                    && json::stringify(given) != json::stringify(&actual)
                {
                    bail!("Conflicting authored HTML attribute {key}");
                }
            }
        }
        if let Some(identity) = dom.attr(id, "data-relaymark-id") {
            value.insert("relaymarkId".into(), Value::String(identity.to_owned()));
        }
        Ok(value)
    }
}

pub fn mark_defs() -> &'static [MarkDef] {
    static MARKS: OnceLock<Vec<MarkDef>> = OnceLock::new();
    MARKS.get_or_init(|| {
        let mut marks: Vec<MarkDef> = [
            ("bold", "strong"),
            ("italic", "em"),
            ("strike", "s"),
            ("underline", "u"),
            ("highlight", "mark"),
            ("superscript", "sup"),
            ("subscript", "sub"),
            ("code", "code"),
        ]
        .into_iter()
        .map(|(name, tag)| MarkDef { name, tag, matches: selector(tag, &[], &[]), allowed: Vec::new(), attrs: |_, _| Ok(Map::new()) })
        .collect();
        marks.push(MarkDef {
            name: "ai_authored",
            tag: "span",
            matches: selector("span", &[("data-ai-authored", None)], &[]),
            allowed: vec!["data-ai-authored", "data-run-id"],
            attrs: |dom, id| Ok(map(vec![("run_id", text_attr(dom, id, "data-run-id"))])),
        });
        marks.push(MarkDef {
            name: "link",
            tag: "a",
            matches: selector("a", &[], &[]),
            allowed: vec!["href", "target", "rel", "class", "title"],
            attrs: |dom, id| {
                let mut result: Map = link_defaults().iter().cloned().collect();
                result.insert("href".into(), text_attr(dom, id, "href"));
                for name in ["target", "rel", "class", "title"] {
                    if let Some(value) = dom.attr(id, name) {
                        result.insert(name.into(), Value::String(value.to_owned()));
                    }
                }
                let result = Value::Object(result);
                validate_link_attributes(&result)?;
                Ok(result.as_object().cloned().unwrap_or_default())
            },
        });
        marks
    })
}

/// The canonical parser: rules of every mark then every node, in schema order.
pub fn canonical_parser() -> &'static Parser {
    static PARSER: OnceLock<Parser> = OnceLock::new();
    PARSER.get_or_init(|| {
        let schema = schema();
        let mark_tags = schema
            .marks
            .iter()
            .flat_map(|mark| mark_defs().iter().filter(move |def| def.name == mark.name))
            .map(|def| TagRule {
                tag: def.tag,
                matches: Box::new(move |dom, id| (def.matches)(dom, id)),
                target: Target::Mark(schema.mark_type(def.name).expect("mark")),
                attrs: Some(Box::new(move |dom, id| Ok(Attrs::Given((def.attrs)(dom, id)?)))),
                content: ContentElement::Itself,
                preserve_whitespace: None,
                priority: 60,
                consuming: true,
            })
            .collect();
        let node_tags = schema
            .nodes
            .iter()
            .flat_map(|node| defs().iter().filter(move |def| def.name == node.name))
            .map(|def| TagRule {
                tag: def.tag,
                matches: Box::new(move |dom, id| def.matches(dom, id)),
                target: Target::Node(schema.node_type(def.name).expect("node")),
                attrs: Some(Box::new(move |dom, id| Ok(Attrs::Given(def.attributes(dom, id)?)))),
                content: (def.content)(),
                preserve_whitespace: def.preserve_full.then_some(Whitespace::Full),
                priority: 60,
                consuming: true,
            })
            .collect();
        Parser::new(schema, mark_tags, node_tags, Vec::new())
    })
}

/// One source node the canonical inventory accounted for.
pub struct SourceNode {
    pub name: &'static str,
    pub attributes: Map,
    pub allows_implicit_paragraph: bool,
}

pub struct SourceMark {
    pub name: &'static str,
    pub attributes: Map,
    pub text: String,
}

pub struct Inventory {
    pub nodes: Vec<SourceNode>,
    pub marks: Vec<SourceMark>,
    pub text: String,
    pub normalizations: Vec<Value>,
}

/// `inspectCanonicalHTML`: strict finite-source coverage before parsing.
pub fn inspect(dom: &Dom, root: Id) -> Result<Inventory> {
    let mut inventory = Inventory { nodes: Vec::new(), marks: Vec::new(), text: String::new(), normalizations: Vec::new() };
    visit(dom, root, 0, &mut inventory)?;
    Ok(inventory)
}

fn check_attributes(dom: &Dom, id: Id, allowed: &[&str]) -> Result<()> {
    for (name, _) in dom.attrs(id) {
        if !allowed.contains(&name.as_str()) {
            bail!("Unsupported retained HTML attribute {name}");
        }
    }
    Ok(())
}

fn visit(dom: &Dom, element: Id, depth: usize, inventory: &mut Inventory) -> Result<()> {
    let schema = schema();
    if depth > crate::adapter::MAX_DOCUMENT_DEPTH + schema.marks.len() + 2 {
        bail!("Oversized retained HTML");
    }
    for &child in dom.children(element) {
        if let Some(text) = dom.text(child) {
            inventory.text.push_str(text);
            continue;
        }
        if !dom.is_element(child) {
            bail!("Unsupported retained HTML node");
        }
        let parent = dom.name(element);
        let name = dom.name(child);
        if (name == "tbody" && parent == "table") || (name == "colgroup" && parent == "table") || (name == "col" && parent == "colgroup") {
            check_attributes(dom, child, if name == "col" { &["style"] } else { &[] })?;
            if name == "col" && dom.has_attr(child, "style") && table_size_style(dom.attr(child, "style")).is_none() {
                bail!("Invalid retained table width");
            }
            if name == "col" && !dom.children(child).is_empty() {
                bail!("Invalid retained table column");
            }
            visit(dom, child, depth + 1, inventory)?;
            continue;
        }
        if name == "code" && parent == "pre" {
            check_attributes(dom, child, &["data-language"])?;
            if dom.children(child).iter().any(|&node| dom.text(node).is_none()) {
                bail!("Invalid retained code content");
            }
            inventory.text.push_str(&dom.text_content(child));
            continue;
        }
        let definition = defs().iter().find(|def| def.matches(dom, child));
        let mark = if definition.is_none() { mark_defs().iter().find(|def| (def.matches)(dom, child)) } else { None };
        let (allowed, presentation_class) = match (definition, mark) {
            (Some(def), _) => (&def.allowed, def.presentation_class),
            (None, Some(mark)) => (&mark.allowed, None),
            (None, None) => bail!("Unsupported retained HTML element {name}"),
        };
        check_attributes(dom, child, allowed)?;
        if let Some(class) = presentation_class
            && dom.attr(child, "class").is_some_and(|found| found != class)
        {
            bail!("Invalid retained presentation class");
        }
        if let Some(def) = definition {
            let attrs = def.attributes(dom, child)?;
            let implicit = dom.children(child).iter().any(|&node| match dom.text(node) {
                Some(text) => !json::js_trim(text).is_empty(),
                None => dom.is_element(node) && mark_defs().iter().any(|mark| (mark.matches)(dom, node)),
            });
            let omitted: Option<&[&str]> = match def.name {
                "questionBlock" => Some(&["points", "min", "max", "settings"]),
                "questionOption" => Some(&["correct", "points", "settings"]),
                "agentSuggestion" => Some(&["confidence", "evidence"]),
                _ => None,
            };
            if let Some(omitted) = omitted
                && !def.complete_authored_fields
                && !dom.has_attr(child, "data-authored")
            {
                let mut entry = Map::new();
                entry.insert("operation".into(), "historical_html_absent_fields".into());
                entry.insert("node".into(), def.name.into());
                entry.insert("source_node_index".into(), inventory.nodes.len().into());
                entry.insert("attributes".into(), Value::Array(omitted.iter().map(|&a| a.into()).collect()));
                entry.insert("source".into(), "retained_rendered_projection".into());
                inventory.normalizations.push(Value::Object(entry));
            }
            if def.name == "table" {
                verify_table_columns(dom, child)?;
            }
            let display = def.display.map(|display| display(&attrs));
            let cell = matches!(def.name, "tableCell" | "tableHeader");
            let align = attrs.get("align").cloned();
            inventory.nodes.push(SourceNode { name: def.name, attributes: attrs, allows_implicit_paragraph: implicit });
            if let Some(display) = display {
                let text_only = dom.children(child).iter().all(|&node| dom.text(node).is_some());
                if !text_only || display.as_ref().and_then(Value::as_str) != Some(dom.text_content(child).as_str()) {
                    bail!("Invalid retained atom display");
                }
                continue;
            }
            if cell && let Some(style) = dom.attr(child, "style") {
                let expected = format!(
                    "text-align: {}",
                    align.as_ref().map_or_else(|| "null".to_owned(), |a| a.as_str().map_or_else(|| json::stringify(a), str::to_owned))
                );
                if style != expected {
                    bail!("Invalid retained cell style");
                }
            }
        } else if let Some(mark) = mark {
            inventory.marks.push(SourceMark { name: mark.name, attributes: (mark.attrs)(dom, child)?, text: dom.text_content(child) });
        }
        visit(dom, child, depth + 1, inventory)?;
    }
    Ok(())
}

/// `width: Npx` or `min-width: Npx`, one declaration.
fn table_size_style(value: Option<&str>) -> Option<(&'static str, u64)> {
    static STYLE: OnceLock<Regex> = OnceLock::new();
    let pattern = STYLE.get_or_init(|| Regex::new(r"^(width|min-width): ([1-9][0-9]*)px;?$").expect("regex"));
    let captures = pattern.captures(value.unwrap_or(""))?;
    let size: f64 = captures[2].parse().ok()?;
    if size > 9_007_199_254_740_991.0 {
        return None;
    }
    Some((if &captures[1] == "width" { "width" } else { "min-width" }, size as u64))
}

fn verify_table_columns(dom: &Dom, table: Id) -> Result<()> {
    let groups: Vec<Id> = dom.element_children(table).into_iter().filter(|&e| dom.name(e) == "colgroup").collect();
    if groups.len() > 1 {
        bail!("Duplicate retained table columns");
    }
    let Some(&group) = groups.first() else {
        if dom.has_attr(table, "style") {
            bail!("Missing retained table sizing evidence");
        }
        return Ok(());
    };
    let Some(row) = dom.find_descendant(table, "tr") else { bail!("Missing retained table row") };
    let mut expected: Vec<Option<u64>> = Vec::new();
    for cell in dom.element_children(row) {
        let name = dom.name(cell);
        if !matches!(name, "td" | "th") {
            bail!("Invalid retained table row");
        }
        let def = defs().iter().find(|def| def.name == if name == "td" { "tableCell" } else { "tableHeader" }).expect("cell rule");
        let attrs = def.attributes(dom, cell)?;
        let colspan = attrs.get("colspan").and_then(Value::as_f64).unwrap_or(f64::NAN);
        let widths = attrs.get("colwidth").and_then(Value::as_array);
        // `Array.from({length: colspan})`: a non-integer or negative span is a RangeError.
        if !(colspan.fract() == 0.0 && (0.0..=4_294_967_295.0).contains(&colspan)) {
            bail!("Invalid array length");
        }
        for index in 0..colspan as usize {
            let width = widths.and_then(|w| w.get(index)).and_then(Value::as_f64).filter(|w| *w != 0.0);
            expected.push(width.map(|w| w as u64));
        }
    }
    let columns = dom.element_children(group);
    if columns.len() != expected.len() {
        bail!("Retained table width evidence was not preserved");
    }
    let maintained = dom.has_attr(table, "style");
    let mut total = 0u64;
    let mut fixed = true;
    for (index, &column) in columns.iter().enumerate() {
        let style = dom.attr(column, "style");
        let size = table_size_style(style);
        let preserved = dom.name(column) == "col"
            && match expected[index] {
                Some(width) => size.is_some_and(|(kind, size)| kind == "width" && size == if maintained { width.max(25) } else { width }),
                None => style.is_none() || (maintained && size.is_some_and(|(kind, size)| kind == "min-width" && size == 25)),
            };
        if !preserved {
            bail!("Retained table width evidence was not preserved");
        }
        if expected[index].is_none() {
            fixed = false;
        }
        total += if maintained { expected[index].unwrap_or(25) } else { size.map_or(0, |(_, size)| size) };
    }
    if maintained {
        let style = table_size_style(dom.attr(table, "style"));
        let kind = if fixed { "width" } else { "min-width" };
        if style.is_none_or(|(found, size)| found != kind || size != total) || columns.iter().any(|&c| table_size_style(dom.attr(c, "style")).is_none()) {
            bail!("Retained table aggregate width evidence was not preserved");
        }
    }
    Ok(())
}

// Foreign clipboard HTML: the web editor's TipTap paste rules.

/// `parseInt(value, 10)` as a positive safe integer, or the fallback.
fn positive_integer(value: Option<&str>, fallback: f64) -> f64 {
    let text = json::js_trim(value.unwrap_or("")).trim_start_matches(json::is_js_space);
    let (negative, digits) = match text.as_bytes().first() {
        Some(b'-') => (true, &text[1..]),
        Some(b'+') => (false, &text[1..]),
        _ => (false, text),
    };
    let digits: String = digits.chars().take_while(char::is_ascii_digit).collect();
    if digits.is_empty() {
        return fallback;
    }
    let number: f64 = digits.parse().unwrap_or(f64::NAN);
    let number = if negative { -number } else { number };
    if number.fract() == 0.0 && number > 0.0 && number <= 9_007_199_254_740_991.0 { number } else { fallback }
}

fn foreign_cell(dom: &Dom, id: Id) -> Result<Attrs> {
    let colwidth = match dom.attr(id, "colwidth").filter(|v| !v.is_empty()) {
        None => Value::Null,
        Some(raw) => {
            let widths: Vec<f64> = raw.split(',').map(|w| positive_integer(Some(w), f64::NAN)).collect();
            if widths.iter().all(|w| !w.is_nan()) { Value::Array(widths.into_iter().map(js_number).collect()) } else { Value::Null }
        }
    };
    Ok(Attrs::Given(map(vec![
        ("colspan", js_number(positive_integer(dom.attr(id, "colspan"), 1.0))),
        ("rowspan", js_number(positive_integer(dom.attr(id, "rowspan"), 1.0))),
        ("colwidth", colwidth),
    ])))
}

fn foreign_rule(tag: &'static str, matches: Matcher, ty: TypeId, attrs: Option<super::parser::TagAttrs>) -> TagRule {
    TagRule { tag, matches, target: Target::Node(ty), attrs, content: ContentElement::Itself, preserve_whitespace: None, priority: 50, consuming: true }
}

fn foreign_node_rules(name: &str, ty: TypeId) -> Vec<TagRule> {
    let simple = |tag: &'static str| vec![foreign_rule(tag, selector(tag, &[], &[]), ty, None)];
    match name {
        "paragraph" => simple("p"),
        "blockquote" => simple("blockquote"),
        "heading" => ["h1", "h2", "h3", "h4", "h5", "h6"]
            .into_iter()
            .enumerate()
            .map(|(level, tag)| {
                let attrs: super::parser::TagAttrs = Box::new(move |_, _| Ok(Attrs::Given(map(vec![("level", js_number((level + 1) as f64))]))));
                foreign_rule(tag, selector(tag, &[], &[]), ty, Some(attrs))
            })
            .collect(),
        "bulletList" => simple("ul"),
        "orderedList" => vec![foreign_rule(
            "ol",
            selector("ol", &[], &[]),
            ty,
            Some(Box::new(|dom, id| {
                let start = if dom.has_attr(id, "start") { positive_integer(dom.attr(id, "start"), 1.0) } else { 1.0 };
                let kind = dom.attr(id, "type").filter(|t| ["1", "a", "A", "i", "I"].contains(t)).map_or(Value::Null, |t| Value::String(t.to_owned()));
                Ok(Attrs::Given(map(vec![("start", js_number(start)), ("type", kind)])))
            })),
        )],
        "listItem" => simple("li"),
        "taskList" => {
            let mut rule = foreign_rule("ul", selector("ul", &[("data-type", Some("taskList"))], &[]), ty, None);
            rule.priority = 51;
            vec![rule]
        }
        "taskItem" => {
            let mut rule = foreign_rule(
                "li",
                selector("li", &[("data-type", Some("taskItem"))], &[]),
                ty,
                Some(Box::new(|dom, id| {
                    let checked = matches!(dom.attr(id, "data-checked"), Some("" | "true"));
                    Ok(Attrs::Given(map(vec![("checked", Value::Bool(checked))])))
                })),
            );
            rule.priority = 51;
            vec![rule]
        }
        "codeBlock" => {
            let mut rule = foreign_rule(
                "pre",
                selector("pre", &[], &[]),
                ty,
                Some(Box::new(|dom, id| {
                    let language = dom.element_children(id).first().and_then(|&first| {
                        dom.attr(first, "class")
                            .and_then(|classes| classes.split(json::is_js_space).find_map(|name| name.strip_prefix("language-")).map(str::to_owned))
                    });
                    Ok(Attrs::Given(map(vec![("language", language.map_or(Value::Null, Value::String))])))
                })),
            );
            rule.preserve_whitespace = Some(Whitespace::Full);
            vec![rule]
        }
        "hardBreak" => simple("br"),
        "horizontalRule" => simple("hr"),
        "image" => vec![foreign_rule(
            "img",
            Box::new(|dom, id| dom.is_html(id) && dom.name(id) == "img" && dom.attr(id, "src").is_some_and(|src| !src.starts_with("data:"))),
            ty,
            Some(Box::new(|dom, id| {
                let src = dom.attr(id, "src").unwrap_or_default();
                if !safe_image_source(src) {
                    return Ok(Attrs::Skip);
                }
                Ok(Attrs::Given(map(vec![("src", src.into()), ("alt", text_attr(dom, id, "alt")), ("title", text_attr(dom, id, "title"))])))
            })),
        )],
        "table" => simple("table"),
        "tableRow" => simple("tr"),
        "tableCell" => vec![foreign_rule("td", selector("td", &[], &[]), ty, Some(Box::new(foreign_cell)))],
        "tableHeader" => vec![foreign_rule("th", selector("th", &[], &[]), ty, Some(Box::new(foreign_cell)))],
        _ => Vec::new(),
    }
}

fn foreign_mark_rule(tag: &'static str, matches: Matcher, ty: usize, attrs: Option<super::parser::TagAttrs>) -> TagRule {
    TagRule { tag, matches, target: Target::Mark(ty), attrs, content: ContentElement::Itself, preserve_whitespace: None, priority: 50, consuming: true }
}

fn style_rule(style: &'static str, target: Option<usize>, clear: Option<usize>, attrs: Option<super::parser::StyleAttrs>, consuming: bool) -> StyleRule {
    StyleRule { style, target, clear, attrs, priority: 50, consuming }
}

/// TipTap's bold `font-weight` rule: bold, bolder or 500 and up.
fn bold_weight(value: &str) -> Attrs {
    static BOLD: OnceLock<Regex> = OnceLock::new();
    let pattern = BOLD.get_or_init(|| Regex::new(r"^(bold(er)?|[5-9][0-9]{2,})$").expect("regex"));
    if pattern.is_match(value) { Attrs::Default } else { Attrs::Skip }
}

/// The foreign clipboard parser.
pub fn foreign_parser() -> &'static Parser {
    static PARSER: OnceLock<Parser> = OnceLock::new();
    PARSER.get_or_init(|| {
        let schema = schema();
        let mut mark_tags = Vec::new();
        let mut styles = Vec::new();
        for (ty, mark) in schema.marks.iter().enumerate() {
            let simple = |tag: &'static str| foreign_mark_rule(tag, selector(tag, &[], &[]), ty, None);
            match mark.name.as_str() {
                "bold" => {
                    mark_tags.push(simple("strong"));
                    mark_tags.push(foreign_mark_rule(
                        "b",
                        selector("b", &[], &[]),
                        ty,
                        Some(Box::new(|dom, id| {
                            Ok(if style_value(dom, id, "font-weight").as_deref() == Some("normal") { Attrs::Skip } else { Attrs::Default })
                        })),
                    ));
                    styles.push(style_rule("font-weight=400", None, Some(ty), None, true));
                    styles.push(style_rule("font-weight", Some(ty), None, Some(Box::new(bold_weight)), true));
                }
                "italic" => {
                    mark_tags.push(simple("em"));
                    mark_tags.push(foreign_mark_rule(
                        "i",
                        selector("i", &[], &[]),
                        ty,
                        Some(Box::new(|dom, id| {
                            Ok(if style_value(dom, id, "font-style").as_deref() == Some("normal") { Attrs::Skip } else { Attrs::Default })
                        })),
                    ));
                    styles.push(style_rule("font-style=normal", None, Some(ty), None, true));
                    styles.push(style_rule("font-style=italic", Some(ty), None, None, true));
                }
                "strike" => {
                    for tag in ["s", "del", "strike"] {
                        mark_tags.push(simple(tag));
                    }
                    styles.push(style_rule(
                        "text-decoration",
                        Some(ty),
                        None,
                        Some(Box::new(|value| if value.contains("line-through") { Attrs::Given(Map::new()) } else { Attrs::Skip })),
                        false,
                    ));
                }
                "underline" => {
                    mark_tags.push(simple("u"));
                    styles.push(style_rule(
                        "text-decoration",
                        Some(ty),
                        None,
                        Some(Box::new(|value| if value.contains("underline") { Attrs::Given(Map::new()) } else { Attrs::Skip })),
                        false,
                    ));
                }
                "code" => mark_tags.push(simple("code")),
                "highlight" => mark_tags.push(simple("mark")),
                "superscript" => {
                    mark_tags.push(simple("sup"));
                    styles.push(style_rule(
                        "vertical-align",
                        Some(ty),
                        None,
                        Some(Box::new(|value| if value == "super" { Attrs::Default } else { Attrs::Skip })),
                        true,
                    ));
                }
                "subscript" => {
                    mark_tags.push(simple("sub"));
                    styles.push(style_rule(
                        "vertical-align",
                        Some(ty),
                        None,
                        Some(Box::new(|value| if value == "sub" { Attrs::Default } else { Attrs::Skip })),
                        true,
                    ));
                }
                "link" => mark_tags.push(foreign_mark_rule(
                    "a",
                    selector("a", &[("href", None)], &[]),
                    ty,
                    Some(Box::new(|dom, id| {
                        let href = dom.attr(id, "href").unwrap_or_default();
                        if !safe_link_href(href) {
                            return Ok(Attrs::Skip);
                        }
                        let mut attrs: Map = link_defaults().iter().cloned().collect();
                        attrs.insert("href".into(), href.into());
                        Ok(Attrs::Given(attrs))
                    })),
                )),
                _ => {}
            }
        }
        let node_tags = schema.nodes.iter().enumerate().flat_map(|(ty, node)| foreign_node_rules(&node.name, ty)).collect();
        Parser::new(schema, mark_tags, node_tags, styles)
    })
}
