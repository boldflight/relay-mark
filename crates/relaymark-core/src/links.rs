//! Portable inert links and durable media sources. Hosts still authorize
//! every destination; these rules only refuse executable or ambiguous syntax.

use std::sync::OnceLock;

use regex::Regex;
use serde_json::Value;

use crate::error::{Result, bail};
use crate::json::{self, Map};
use crate::schema::editor_schema;

fn regex(cell: &'static OnceLock<Regex>, pattern: &str) -> &'static Regex {
    cell.get_or_init(|| Regex::new(pattern).expect("static pattern"))
}

pub fn safe_link_href(value: &str) -> bool {
    if value.is_empty() || value.chars().any(|c| json::is_js_space(c) || (c as u32) < 0x20 || c == '\u{7f}' || matches!(c, '<' | '>' | '\\')) {
        return false;
    }
    if let Some(rest) = value.strip_prefix('#') {
        return !rest.is_empty();
    }
    if value.starts_with('/') {
        return !value.starts_with("//");
    }
    let lower = value.get(..8).unwrap_or(value).to_ascii_lowercase();
    if lower.starts_with("http://") || lower.starts_with("https://") {
        return match url::Url::parse(value) {
            Ok(url) => {
                url.host_str().is_some_and(|host| !host.is_empty())
                    && url.username().is_empty()
                    && url.password().is_none()
                    && matches!(url.scheme(), "http" | "https")
            }
            Err(_) => false,
        };
    }
    static RELAY: OnceLock<Regex> = OnceLock::new();
    if regex(&RELAY, r"^relay:(?:entity|note|file|tag)/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$").is_match(value) {
        return true;
    }
    if value.get(..7).is_some_and(|scheme| scheme.eq_ignore_ascii_case("mailto:")) {
        return !value[7..].split('?').next().unwrap_or("").is_empty();
    }
    if value.get(..4).is_some_and(|scheme| scheme.eq_ignore_ascii_case("tel:")) {
        let rest = &value[4..];
        return !rest.is_empty() && rest.chars().all(|c| c.is_ascii_digit() || matches!(c, '+' | '(' | ')' | '.' | '-'));
    }
    false
}

/// Durable authored media URI: a local path without dot segments, or HTTPS.
pub fn safe_image_source(value: &str) -> bool {
    if json::utf16_len(value) > 2048 || !safe_link_href(value) {
        return false;
    }
    if value.starts_with('/') {
        let path = value.split(['?', '#']).next().unwrap_or("");
        return path.split('/').all(|part| match decode_uri_component(part) {
            Some(decoded) => decoded != "." && decoded != "..",
            None => false,
        });
    }
    let https = value.get(..8).is_some_and(|scheme| scheme.eq_ignore_ascii_case("https://"));
    https && url::Url::parse(value).is_ok_and(|url| url.scheme() == "https")
}

/// `decodeURIComponent`, refusing malformed escapes and invalid UTF-8.
pub fn decode_uri_component(text: &str) -> Option<String> {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' {
            let hex = text.get(index + 1..index + 3)?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            index += 3;
        } else {
            out.push(bytes[index]);
            index += 1;
        }
    }
    String::from_utf8(out).ok()
}

/// Link mark defaults other than `href`, in schema order.
pub fn link_defaults() -> &'static [(String, Value)] {
    static DEFAULTS: OnceLock<Vec<(String, Value)>> = OnceLock::new();
    DEFAULTS.get_or_init(|| editor_schema().mark("link").expect("link mark").attrs.iter().filter(|(name, _)| name != "href").cloned().collect())
}

fn invalid_text(value: &Value) -> bool {
    match value.as_str() {
        Some(text) => text.chars().any(|c| matches!(c, '\u{0}'..='\u{8}' | '\u{b}' | '\u{c}' | '\u{e}'..='\u{1f}' | '\u{7f}')),
        None => true,
    }
}

pub fn validate_link_attributes(attributes: &Value) -> Result<&Map> {
    let defaults = link_defaults();
    let valid_shape = attributes.as_object().filter(|attrs| {
        attrs.keys().all(|key| key == "href" || defaults.iter().any(|(name, _)| name == key))
            && attrs.get("href").and_then(Value::as_str).is_some_and(safe_link_href)
    });
    let Some(attrs) = valid_shape else { bail!("Invalid link href or attributes") };
    for (key, _) in defaults {
        if !attrs.contains_key(key) {
            bail!("Missing link {key}");
        }
    }
    let target = &attrs["target"];
    if !target.is_null() {
        let text = target.as_str().unwrap_or("");
        let reserved = text.starts_with('_') && !["_blank", "_self", "_parent", "_top"].contains(&text.to_lowercase().as_str());
        if invalid_text(target) || text.contains(['\t', '\r', '\n']) || reserved {
            bail!("Invalid link target");
        }
    }
    for key in ["rel", "class", "title"] {
        if !attrs[key].is_null() && invalid_text(&attrs[key]) {
            bail!("Invalid link {key}");
        }
    }
    Ok(attrs)
}

/// Editor link attributes from an AST `href` and optional authored properties.
pub fn link_attributes(href: &str, props: Option<&Value>) -> Result<Value> {
    let empty = Value::Object(Map::new());
    let props = props.unwrap_or(&empty);
    let defaults = link_defaults();
    let Some(props) = props.as_object().filter(|p| p.keys().all(|k| defaults.iter().any(|(name, _)| name == k))) else { bail!("Unsupported link property") };
    let mut attrs = Map::new();
    attrs.insert("href".into(), Value::String(href.to_owned()));
    for (name, default) in defaults {
        attrs.insert(name.clone(), props.get(name).cloned().unwrap_or_else(|| default.clone()));
    }
    let attrs = Value::Object(attrs);
    validate_link_attributes(&attrs)?;
    Ok(attrs)
}

/// Authored properties that differ from the schema defaults.
pub fn link_properties(attributes: &Value) -> Result<Map> {
    let attrs = validate_link_attributes(attributes)?;
    Ok(link_defaults().iter().filter(|(name, default)| attrs.get(name) != Some(default)).map(|(name, _)| (name.clone(), attrs[name].clone())).collect())
}

/// Rendering hardens new browsing contexts without rewriting the declaration.
pub fn rendered_link_attributes(attributes: &Value) -> Result<Map> {
    let mut result = validate_link_attributes(attributes)?.clone();
    let target = result.get("target").and_then(Value::as_str).map(str::to_lowercase);
    if !matches!(target.as_deref(), None | Some("" | "_self" | "_parent" | "_top")) {
        let rel = result.get("rel").and_then(Value::as_str).unwrap_or("").to_owned();
        let mut tokens: Vec<String> = rel.split(json::is_js_space).filter(|t| !t.is_empty()).map(str::to_owned).collect();
        for token in ["noopener", "noreferrer"] {
            if !tokens.iter().any(|t| t.to_lowercase() == token) {
                tokens.push(token.to_owned());
            }
        }
        result.insert("rel".into(), Value::String(tokens.join(" ")));
    }
    Ok(result)
}
