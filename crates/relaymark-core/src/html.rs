//! Safe, static authored HTML. Hosts hydrate and authorize widgets; nothing
//! here executes, fetches or navigates.

use std::collections::HashMap;

use serde_json::Value;

use crate::adapter::to_prosemirror;
use crate::controls::paper_destinations;
use crate::error::{Result, bail};
use crate::json::{self, Map};
use crate::links::rendered_link_attributes;
use crate::registry::directive_node_for_name;

pub fn escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            other => out.push(other),
        }
    }
    out
}

/// `String(value ?? '')`.
fn display(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        Value::String(text) => text.clone(),
        Value::Array(items) => items.iter().map(display).collect::<Vec<_>>().join(","),
        Value::Object(_) => "[object Object]".into(),
        other => json::stringify(other),
    }
}

fn attributes(pairs: &[(&str, Value)]) -> String {
    pairs.iter().filter(|(_, value)| !value.is_null()).map(|(key, value)| format!(" {key}=\"{}\"", escape(&display(value)))).collect()
}

fn tag(name: &str, pairs: &[(&str, Value)], body: &str) -> String {
    format!("<{name}{}>{body}</{name}>", attributes(pairs))
}

/// Document AST to static HTML.
pub fn render_document(document: &Value) -> Result<String> {
    let prosemirror = to_prosemirror(document)?;
    let headings: HashMap<String, String> = paper_destinations(&prosemirror)
        .into_iter()
        .filter(|entry| entry["kind"] == "heading")
        .map(|entry| {
            let path = entry["source_path"].as_array().into_iter().flatten().map(display).collect::<Vec<_>>().join(".");
            (path, entry["name"].as_str().unwrap_or_default().to_owned())
        })
        .collect();
    let content = prosemirror["content"].as_array().map(Vec::as_slice).unwrap_or(&[]);
    let mut html = String::new();
    for (index, node) in content.iter().enumerate() {
        html.push_str(&render(node, &[index], &headings)?);
    }
    Ok(html)
}

fn render(node: &Value, path: &[usize], headings: &HashMap<String, String>) -> Result<String> {
    let empty = Map::new();
    let attrs = node.get("attrs").and_then(Value::as_object).unwrap_or(&empty);
    let a = |key: &str| attrs.get(key).cloned().unwrap_or(Value::Null);
    let kind = node["type"].as_str().unwrap_or_default();
    if kind == "text" {
        let mut text = escape(node["text"].as_str().unwrap_or_default());
        for mark in node.get("marks").and_then(Value::as_array).into_iter().flatten().rev() {
            text = match mark["type"].as_str().unwrap_or_default() {
                "link" => {
                    let link = rendered_link_attributes(&mark["attrs"])?;
                    let pairs: Vec<(&str, Value)> = link.iter().map(|(k, v)| (k.as_str(), v.clone())).collect();
                    tag("a", &pairs, &text)
                }
                "ai_authored" => tag("span", &[("data-ai-authored", Value::String(String::new())), ("data-run-id", mark["attrs"]["run_id"].clone())], &text),
                name => {
                    let element = match name {
                        "bold" => "strong",
                        "code" => "code",
                        "italic" => "em",
                        "strike" => "s",
                        "underline" => "u",
                        "highlight" => "mark",
                        "superscript" => "sup",
                        "subscript" => "sub",
                        _ => "undefined",
                    };
                    tag(element, &[], &text)
                }
            };
        }
        return Ok(text);
    }
    let mut body = String::new();
    for (index, child) in node.get("content").and_then(Value::as_array).into_iter().flatten().enumerate() {
        let mut child_path = path.to_vec();
        child_path.push(index);
        body.push_str(&render(child, &child_path, headings)?);
    }
    let authored: Map = attrs.iter().filter(|(k, _)| *k != "relaymarkId").map(|(k, v)| (k.clone(), v.clone())).collect();
    let hydration = ("data-authored", Value::String(json::stringify(&Value::Object(authored))));
    if let Some(generic) = directive_node_for_name(kind) {
        return Ok(tag("section", &[("data-relay-directive", Value::String(generic.ast_type.to_owned())), hydration], &body));
    }
    let label = |key: &str| escape(&display(&a(key)));
    Ok(match kind {
        "hardBreak" => "<br>".into(),
        "horizontalRule" => "<hr>".into(),
        "heading" => {
            let key = path.iter().map(usize::to_string).collect::<Vec<_>>().join(".");
            let name = headings.get(&key).map_or(Value::Null, |n| Value::String(n.clone()));
            tag(&format!("h{}", display(&a("level"))), &[("id", name.clone()), ("data-relay-heading-id", name), hydration], &body)
        }
        "codeBlock" => tag("pre", &[], &tag("code", &[("data-language", a("language"))], &body)),
        "image" => {
            format!("<img{}>", attributes(&[("src", a("src")), ("alt", a("alt")), ("title", a("title")), ("width", a("width")), ("height", a("height"))]))
        }
        "table" => {
            // First-row spans define the columns; zero or null widths stay unspecified.
            let mut columns = String::new();
            let first_row = node["content"][0]["content"].as_array().map(Vec::as_slice).unwrap_or(&[]);
            for cell in first_row {
                let span = cell["attrs"]["colspan"].as_u64().unwrap_or(1);
                for index in 0..span {
                    let width = cell["attrs"]["colwidth"].get(index as usize).filter(|w| json::truthy(Some(w)));
                    let style = width.map_or(Value::Null, |w| Value::String(format!("width: {}px", display(w))));
                    columns.push_str(&format!("<col{}>", attributes(&[("style", style)])));
                }
            }
            tag("table", &[], &(tag("colgroup", &[], &columns) + &body))
        }
        "callout" => tag("aside", &[("data-relay-callout", a("tone")), ("data-emphasis", a("emphasis")), hydration], &body),
        "questionBlock" => tag("fieldset", &[("data-relay-question", a("id")), ("data-question-type", a("type")), ("data-required", a("required"))], &body),
        "questionOption" => tag("div", &[("data-relay-option", a("id"))], &body),
        "relayReference" => tag("span", &[("data-relay-reference", a("entityId")), ("data-source", a("source")), hydration], &label("label")),
        "relayTag" => tag("span", &[("data-relay-tag", a("id")), ("data-source", a("source")), hydration], &label("name")),
        "relayEntityReference" => tag(
            "div",
            &[("data-relay-reference", a("entityRef")), ("data-projection", a("projection")), ("data-source", a("source")), hydration],
            &label("label"),
        ),
        "videoEmbed" => tag("div", &[("data-relay-video", a("videoId")), hydration], ""),
        "agentSuggestion" => tag("aside", &[("data-relay-suggestion", a("review")), ("data-kind", a("kind"))], &label("content")),
        "relayDataView" => {
            let title = if json::truthy(attrs.get("title")) { a("title") } else { a("source") };
            tag("div", &[("data-relay-data-view", a("source")), hydration], &escape(&display(&title)))
        }
        "relayButton" => tag(
            "button",
            &[
                ("type", Value::String("button".into())),
                ("disabled", Value::Bool(true)),
                ("data-relay-kind", a("kind")),
                ("data-relay-target", a("target")),
                hydration,
            ],
            &label("label"),
        ),
        "relayAnchor" => tag("span", &[("data-relay-anchor", a("name")), hydration], ""),
        "relayConnection" => tag("div", &[("data-relay-connection", a("provider")), hydration], &label("provider")),
        _ => {
            let element = match kind {
                "paragraph" => "p",
                "blockquote" => "blockquote",
                "bulletList" | "taskList" => "ul",
                "orderedList" => "ol",
                "listItem" | "taskItem" => "li",
                "table" => "table",
                "tableRow" => "tr",
                "tableCell" => "td",
                "tableHeader" => "th",
                "calloutTitle" => "div",
                "questionLabel" => "legend",
                _ => bail!("Unsupported authored renderer"),
            };
            let extra: Vec<(&str, Value)> = match kind {
                "calloutTitle" => vec![("data-callout-title", Value::Bool(true))],
                "orderedList" => vec![("start", a("start"))],
                "taskList" => vec![("data-relay-task-list", Value::Bool(true))],
                "taskItem" => vec![("data-checked", a("checked")), ("data-relay-task-item", a("entityId")), hydration],
                "tableCell" | "tableHeader" => {
                    let align = a("align");
                    let style = align.as_str().filter(|s| !s.is_empty()).map_or(Value::Null, |s| Value::String(format!("text-align: {s}")));
                    vec![("colspan", a("colspan")), ("rowspan", a("rowspan")), ("colwidth", a("colwidth")), ("data-align", align), ("style", style)]
                }
                _ => Vec::new(),
            };
            tag(element, &extra, &body)
        }
    })
}
