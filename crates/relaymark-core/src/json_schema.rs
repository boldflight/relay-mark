//! The bounded JSON Schema subset the RelayMark schemas use, validated
//! against the packaged schema files. Unsupported keywords are a defect in the
//! packaged schema, never silently ignored.

use std::collections::{HashMap, HashSet};
use std::sync::OnceLock;

use regex::Regex;
use serde_json::{Value, json};

use crate::json;

pub const DOCUMENT_SCHEMA: &str = include_str!("../../../spec/relaymark/schemas/relaymark-document.schema.json");
pub const MANIFEST_SCHEMA: &str = include_str!("../../../spec/relaymark/schemas/relaymark-manifest.schema.json");
pub const DIAGNOSTIC_SCHEMA: &str = include_str!("../../../spec/relaymark/schemas/relaymark-diagnostic.schema.json");
pub const COMPOSITION_SCHEMA: &str = include_str!("../../../spec/relaymark/schemas/relaymark-layer-composition.schema.json");
pub const DIRECTIVE_SCHEMA: &str = include_str!("../../../spec/relaymark/schemas/relaymark-directive.schema.json");
pub const SUITE_SCHEMA: &str = include_str!("../../../spec/relaymark/schemas/relaymark-conformance-suite.schema.json");

const SCHEMAS: [(&str, &str); 6] = [
    ("relaymark-document.schema.json", DOCUMENT_SCHEMA),
    ("relaymark-manifest.schema.json", MANIFEST_SCHEMA),
    ("relaymark-diagnostic.schema.json", DIAGNOSTIC_SCHEMA),
    ("relaymark-layer-composition.schema.json", COMPOSITION_SCHEMA),
    ("relaymark-directive.schema.json", DIRECTIVE_SCHEMA),
    ("relaymark-conformance-suite.schema.json", SUITE_SCHEMA),
];

const KEYWORDS: [&str; 24] = [
    "$defs",
    "$id",
    "$ref",
    "$schema",
    "additionalProperties",
    "anyOf",
    "const",
    "default",
    "description",
    "enum",
    "items",
    "maximum",
    "maxLength",
    "minimum",
    "minItems",
    "minLength",
    "not",
    "oneOf",
    "pattern",
    "properties",
    "required",
    "title",
    "type",
    "uniqueItems",
];

/// The packaged schemas, parsed once.
fn packaged(name: &str) -> Option<&'static Value> {
    static PARSED: OnceLock<HashMap<&'static str, Value>> = OnceLock::new();
    PARSED.get_or_init(|| SCHEMAS.iter().map(|(file, text)| (*file, serde_json::from_str(text).expect("packaged JSON Schema"))).collect()).get(name)
}

/// Every `pattern` in the packaged schemas, compiled once.
fn pattern(source: &str) -> Option<&'static Regex> {
    static COMPILED: OnceLock<HashMap<String, Option<Regex>>> = OnceLock::new();
    fn collect(value: &Value, out: &mut HashMap<String, Option<Regex>>) {
        match value {
            Value::Object(map) => {
                if let Some(Value::String(source)) = map.get("pattern") {
                    out.entry(source.clone()).or_insert_with(|| Regex::new(&crate::jsre::translate(source)).ok());
                }
                map.values().for_each(|item| collect(item, out));
            }
            Value::Array(items) => items.iter().for_each(|item| collect(item, out)),
            _ => {}
        }
    }
    COMPILED
        .get_or_init(|| {
            let mut out = HashMap::new();
            for (file, _) in SCHEMAS {
                collect(packaged(file).expect("packaged JSON Schema"), &mut out);
            }
            out
        })
        .get(source)
        .and_then(Option::as_ref)
}

struct Context<'a> {
    document_name: &'a str,
    document: &'a Value,
    instance: String,
    schema_path: String,
}

/// Validation errors (`{instance_path, schema_path, message}`) of `value`
/// against the packaged schema file `name`.
pub fn validate(value: &Value, name: &str) -> Vec<Value> {
    let Some(schema) = packaged(name) else { return vec![json!({"instance_path": "/", "schema_path": "#", "message": format!("unknown schema {name}")})] };
    let context = Context { document_name: name, document: schema, instance: String::new(), schema_path: "#".into() };
    validate_value(value, schema, &context)
}

fn failure(context: &Context, message: String) -> Value {
    let instance = if context.instance.is_empty() { "/".to_owned() } else { context.instance.clone() };
    json!({"instance_path": instance, "schema_path": context.schema_path, "message": message})
}

fn escape_pointer(value: &str) -> String {
    value.replace('~', "~0").replace('/', "~1")
}

fn with<'a>(context: &Context<'a>, instance: Option<String>, schema_path: String) -> Context<'a> {
    Context { document_name: context.document_name, document: context.document, instance: instance.unwrap_or_else(|| context.instance.clone()), schema_path }
}

fn matches_type(value: &Value, kind: &str) -> bool {
    match kind {
        "null" => value.is_null(),
        "array" => value.is_array(),
        "object" => value.is_object(),
        "integer" => json::is_integer(value),
        "number" => json::is_finite_number(value),
        "string" => value.is_string(),
        "boolean" => value.is_boolean(),
        _ => false,
    }
}

fn validate_value(value: &Value, schema: &Value, context: &Context) -> Vec<Value> {
    match schema {
        Value::Bool(true) => return Vec::new(),
        Value::Bool(false) => return vec![failure(context, "is not allowed by this schema".into())],
        Value::Object(_) => {}
        _ => panic!("Invalid JSON Schema at {}.", context.schema_path),
    }
    for keyword in schema.as_object().into_iter().flatten().map(|(k, _)| k) {
        assert!(KEYWORDS.contains(&keyword.as_str()), "Unsupported JSON Schema keyword '{keyword}' at {}.", context.schema_path);
    }
    let mut errors = Vec::new();
    if let Some(reference) = schema.get("$ref").and_then(Value::as_str) {
        let (file, pointer) = reference.split_once('#').unwrap_or((reference, ""));
        let (document_name, document) = if file.is_empty() {
            (context.document_name, context.document)
        } else {
            (file, packaged(file).unwrap_or_else(|| panic!("JSON Schema reference '{reference}' could not be resolved")))
        };
        let target = if pointer.is_empty() { Some(document) } else { document.pointer(pointer) };
        let target = target.unwrap_or_else(|| panic!("JSON Schema reference '{reference}' could not be resolved"));
        let next = Context {
            document_name,
            document,
            instance: context.instance.clone(),
            schema_path: if pointer.is_empty() { "#".into() } else { format!("#{pointer}") },
        };
        errors.extend(validate_value(value, target, &next));
    }
    if let Some(constant) = schema.get("const")
        && !json::deep_equal(value, constant)
    {
        errors.push(failure(context, format!("must equal {}", json::stringify(constant))));
    }
    if let Some(options) = schema.get("enum").and_then(Value::as_array)
        && !options.iter().any(|candidate| json::deep_equal(value, candidate))
    {
        let listed = options.iter().map(json::stringify).collect::<Vec<_>>().join(", ");
        errors.push(failure(context, format!("must be one of {listed}")));
    }
    if let Some(kind) = schema.get("type").and_then(Value::as_str)
        && !matches_type(value, kind)
    {
        errors.push(failure(context, format!("must be of type {kind}")));
        return errors;
    }
    if let Some(options) = schema.get("anyOf").and_then(Value::as_array) {
        let any = options
            .iter()
            .enumerate()
            .any(|(i, candidate)| validate_value(value, candidate, &with(context, None, format!("{}/anyOf/{i}", context.schema_path))).is_empty());
        if !any {
            errors.push(failure(context, "must match at least one schema in anyOf".into()));
        }
    }
    if let Some(options) = schema.get("oneOf").and_then(Value::as_array) {
        let count = options
            .iter()
            .enumerate()
            .filter(|(i, candidate)| validate_value(value, candidate, &with(context, None, format!("{}/oneOf/{i}", context.schema_path))).is_empty())
            .count();
        if count != 1 {
            errors.push(failure(context, "must match exactly one schema in oneOf".into()));
        }
    }
    if let Some(negated) = schema.get("not")
        && validate_value(value, negated, &with(context, None, format!("{}/not", context.schema_path))).is_empty()
    {
        errors.push(failure(context, "must not match the schema in not".into()));
    }
    if let Some(number) = value.as_f64() {
        if let Some(minimum) = schema.get("minimum").and_then(Value::as_f64).filter(|m| number < *m) {
            errors.push(failure(context, format!("must be greater than or equal to {}", json::float_string(minimum))));
        }
        if let Some(maximum) = schema.get("maximum").and_then(Value::as_f64).filter(|m| number > *m) {
            errors.push(failure(context, format!("must be less than or equal to {}", json::float_string(maximum))));
        }
    }
    if let Some(text) = value.as_str() {
        if let Some(minimum) = schema.get("minLength").filter(|m| json::is_integer(m)).and_then(Value::as_f64)
            && (text.chars().count() as f64) < minimum
        {
            errors.push(failure(context, format!("must contain at least {} characters", json::float_string(minimum))));
        }
        if let Some(maximum) = schema.get("maxLength").filter(|m| json::is_integer(m)).and_then(Value::as_f64)
            && (text.chars().count() as f64) > maximum
        {
            errors.push(failure(context, format!("must contain at most {} characters", json::float_string(maximum))));
        }
        if let Some(pattern) = schema.get("pattern").and_then(Value::as_str)
            && !self::pattern(pattern).is_some_and(|re| re.is_match(text))
        {
            errors.push(failure(context, format!("must match pattern {pattern}")));
        }
    }
    if let Some(items) = value.as_array() {
        if let Some(minimum) = schema.get("minItems").filter(|m| json::is_integer(m)).and_then(Value::as_f64)
            && (items.len() as f64) < minimum
        {
            errors.push(failure(context, format!("must contain at least {} items", json::float_string(minimum))));
        }
        if schema.get("uniqueItems").and_then(Value::as_bool) == Some(true)
            && items.iter().map(json::stable_stringify).collect::<HashSet<_>>().len() != items.len()
        {
            errors.push(failure(context, "must contain unique items".into()));
        }
        if let Some(item_schema) = schema.get("items") {
            for (index, item) in items.iter().enumerate() {
                let next = with(context, Some(format!("{}/{index}", context.instance)), format!("{}/items", context.schema_path));
                errors.extend(validate_value(item, item_schema, &next));
            }
        }
    }
    if let Some(object) = value.as_object() {
        let empty = serde_json::Map::new();
        let properties = schema.get("properties").and_then(Value::as_object).unwrap_or(&empty);
        for required in schema.get("required").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str) {
            if !object.contains_key(required) {
                errors.push(failure(context, format!("must contain required property '{required}'")));
            }
        }
        for (name, property) in properties {
            if let Some(item) = object.get(name) {
                let next = with(
                    context,
                    Some(format!("{}/{}", context.instance, escape_pointer(name))),
                    format!("{}/properties/{}", context.schema_path, escape_pointer(name)),
                );
                errors.extend(validate_value(item, property, &next));
            }
        }
        let extra: Vec<&String> = object.keys().filter(|name| !properties.contains_key(*name)).collect();
        match schema.get("additionalProperties") {
            Some(Value::Bool(false)) => {
                for name in extra {
                    errors.push(failure(context, format!("must not contain additional property '{name}'")));
                }
            }
            Some(additional @ (Value::Bool(true) | Value::Object(_))) => {
                for name in extra {
                    let next =
                        with(context, Some(format!("{}/{}", context.instance, escape_pointer(name))), format!("{}/additionalProperties", context.schema_path));
                    errors.extend(validate_value(&object[name], additional, &next));
                }
            }
            _ => {}
        }
    }
    errors
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every keyword a packaged schema uses, reached the way `validate_value`
    /// reaches subschemas: an unsupported one would panic at the first
    /// document that visits it rather than in the build.
    fn unsupported(schema: &Value, path: &str, out: &mut Vec<String>) {
        let Some(object) = schema.as_object() else { return };
        for (keyword, value) in object {
            if !KEYWORDS.contains(&keyword.as_str()) {
                out.push(format!("{path}/{keyword}"));
            }
            let nested: Vec<(String, &Value)> = match (keyword.as_str(), value) {
                ("$defs" | "properties", Value::Object(map)) => map.iter().map(|(k, v)| (format!("{keyword}/{k}"), v)).collect(),
                ("anyOf" | "oneOf", Value::Array(items)) => items.iter().enumerate().map(|(i, v)| (format!("{keyword}/{i}"), v)).collect(),
                ("items" | "not" | "additionalProperties", _) => vec![(keyword.clone(), value)],
                _ => Vec::new(),
            };
            for (step, child) in nested {
                unsupported(child, &format!("{path}/{step}"), out);
            }
        }
    }

    #[test]
    fn packaged_schemas_use_only_supported_keywords() {
        let mut found = Vec::new();
        for (name, text) in SCHEMAS {
            unsupported(&serde_json::from_str(text).unwrap(), name, &mut found);
        }
        assert!(found.is_empty(), "unsupported keywords: {found:?}");
    }

    #[test]
    fn an_ai_authored_run_id_is_at_most_64_characters() {
        let document = |run_id: &str| {
            json!({"type": "relaymark.document", "blocks": [{"id": "b1", "type": "paragraph", "content": [
                {"type": "ai_authored", "run_id": run_id, "content": [{"type": "text", "text": "x"}]}]}]})
        };
        assert!(validate(&document(&"r".repeat(64)), "relaymark-document.schema.json").is_empty());
        assert!(!validate(&document(&"r".repeat(65)), "relaymark-document.schema.json").is_empty());
    }
}
