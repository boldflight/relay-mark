//! Every engine call by name, with JSON in and out: the one call surface the
//! native bindings (the Elixir NIF, the Swift package) share. A job takes its
//! input bytes (source text or JSON) and its options as a JSON object (empty
//! for none), and answers result bytes or the refusal's message.

use serde_json::Value;

use crate as rm;

/// A job's result bytes, or the refusal's message.
pub type Answer = Result<Vec<u8>, String>;

fn text(input: &[u8]) -> Result<&str, String> {
    std::str::from_utf8(input).map_err(|_| "Input is not UTF-8".to_owned())
}

fn json(input: &[u8]) -> Result<Value, String> {
    serde_json::from_slice(input).map_err(|e| format!("Invalid JSON input: {e}"))
}

/// Host maps (Elixir, Foundation) carry no key order; give a document envelope the order the
/// reference runtime builds it in, so stored source matches the web's bytes.
fn document(input: &[u8]) -> Result<Value, String> {
    let mut value = json(input)?;
    if let Value::Object(map) = &mut value {
        const ORDER: [&str; 7] = ["type", "version", "frontmatter", "blocks", "annotations", "resources", "meta"];
        let mut ordered = Value::Object(Default::default());
        let target = ordered.as_object_mut().expect("object");
        for key in ORDER {
            if let Some(item) = map.shift_remove(key) {
                target.insert(key.to_owned(), item);
            }
        }
        target.extend(std::mem::take(map));
        value = ordered;
    }
    Ok(value)
}

/// A JSON array of exactly `count` arguments (missing trailing ones null).
fn arguments(input: &[u8], count: usize) -> Result<Vec<Value>, String> {
    match json(input)? {
        Value::Array(mut items) if items.len() <= count => {
            items.resize(count, Value::Null);
            Ok(items)
        }
        _ => Err(format!("Expected {count} JSON arguments")),
    }
}

fn engine<T>(result: rm::Result<T>, output: impl FnOnce(T) -> Vec<u8>) -> Answer {
    result.map(output).map_err(|e| e.message().to_owned())
}

fn value_out(value: Value) -> Vec<u8> {
    rm::to_json(&value).into_bytes()
}

fn option<'v>(options: &'v Value, key: &str) -> Option<&'v str> {
    options.get(key).and_then(Value::as_str)
}

fn required<'v>(options: &'v Value, key: &str) -> Result<&'v str, String> {
    option(options, key).ok_or_else(|| format!("Missing option {key}"))
}

/// Runs the named job.
pub fn run(job: &str, input: &[u8], options: &[u8]) -> Answer {
    std::panic::catch_unwind(|| dispatch(job, input, options)).unwrap_or_else(|_| Err(format!("relaymark-core panicked in {job}")))
}

fn dispatch(job: &str, input: &[u8], options: &[u8]) -> Answer {
    let options = if options.is_empty() { Value::Null } else { json(options)? };
    match job {
        "parse" => engine(rm::parse_document(text(input)?, option(&options, "namespace")), value_out),
        "import_source" => engine(rm::import::source(text(input)?, required(&options, "namespace")?), value_out),
        "serialize" => engine(rm::serialize_document(&document(input)?), String::into_bytes),
        "markdown" => engine(rm::project_markdown(&document(input)?), String::into_bytes),
        "html" => engine(rm::render_html(&document(input)?), String::into_bytes),
        "project" => {
            let document = document(input)?;
            let body = rm::project_markdown(&document).map_err(|e| e.message().to_owned())?;
            let html = rm::render_html(&document).map_err(|e| e.message().to_owned())?;
            Ok(value_out(serde_json::json!({"body": body, "body_html": html})))
        }
        "normalize" => engine(rm::normalize_document(&document(input)?), value_out),
        "to_snapshot" => engine(rm::document_to_snapshot(&document(input)?), value_out),
        "from_snapshot" => engine(rm::snapshot_to_document(&json(input)?), value_out),
        "import_document" => engine(rm::import::document(&document(input)?, required(&options, "namespace")?), value_out),
        "import_snapshot" => engine(rm::import::snapshot(&json(input)?, required(&options, "namespace")?), value_out),
        "aggregate_settings" => engine(rm::import::aggregate_settings_snapshot(&json(input)?), value_out),
        "form_publication" => {
            let namespace = required(&options, "namespace")?;
            engine(rm::import::form_publication(&json(input)?, namespace, option(&options, "source")), value_out)
        }
        "validate_document" => {
            let document = json(input)?;
            let schema = rm::validate_schema(&document, "relaymark-document.schema.json");
            if !schema.is_empty() {
                return Ok(value_out(serde_json::json!({ "schema": schema })));
            }
            let context = options.get("context").cloned().unwrap_or(Value::Null);
            Ok(value_out(serde_json::json!({ "diagnostics": rm::validate(&document, &context) })))
        }
        "schema" => Ok(value_out(Value::Array(rm::validate_schema(&json(input)?, required(&options, "schema")?)))),
        "manifest" => {
            let diagnostics = options.get("diagnostics").and_then(Value::as_array).cloned().unwrap_or_default();
            Ok(value_out(rm::project_manifest(&json(input)?, &diagnostics)))
        }
        "transported_pair" => {
            let manifest = required(&options, "manifest")?;
            let context = options.get("context").cloned().unwrap_or(Value::Null);
            engine(rm::validate_transported_agent_answer_pair(input, manifest.as_bytes(), &context), value_out)
        }
        "compose" => Ok(value_out(rm::compose_layers(&json(input)?))),
        "text_attributes" => engine(rm::validate_text_attributes(&json(input)?), |()| b"true".to_vec()),
        "entity_reference_source" => {
            engine(rm::entity_reference_source(required(&options, "type")?, required(&options, "id")?, required(&options, "label")?), String::into_bytes)
        }
        "paper_control_source" => engine(rm::paper_control_source(&json(input)?), String::into_bytes),
        "parse_entity_reference" => Ok(value_out(rm::parse_entity_reference(text(input)?).unwrap_or(Value::Null))),
        "import_html" => engine(
            rm::import::html((!input.is_empty() || option(&options, "absent").is_none()).then(|| text(input)).transpose()?, required(&options, "namespace")?),
            value_out,
        ),
        "import_clipboard_html" => engine(rm::import::clipboard_html(text(input)?, required(&options, "namespace")?), value_out),
        "encode_attributes" => engine(rm::encode_attributes(required(&options, "name")?, &json(input)?), value_out),
        "decode_attributes" => engine(rm::decode_attributes(required(&options, "name")?, &json(input)?), value_out),
        "paper_destinations" => engine(rm::paper_destinations(&document(input)?), |v| value_out(Value::Array(v))),
        "safe_image_source" => Ok(value_out(Value::Bool(rm::safe_image_source(text(input)?)))),
        "directive_definitions" => Ok(value_out(rm::directive_definitions())),
        // Editing jobs take their arguments as one JSON array.
        "edit_command" => {
            let a = arguments(input, 2)?;
            engine(rm::edit::command(&a[0], &a[1]), value_out)
        }
        "edit_prepare_write" => {
            let a = arguments(input, 3)?;
            engine(rm::edit::prepare_write(&a[0], &a[1], &a[2]), value_out)
        }
        "edit_plan_text_write" => {
            let a = arguments(input, 6)?;
            let span = (!a[5].is_null()).then_some(&a[5]);
            engine(rm::edit::plan_text_write(&a[0], &a[1], &a[2], &a[3], &a[4], span), value_out)
        }
        "edit_input_rule" => {
            let a = arguments(input, 2)?;
            engine(rm::edit::input_rule(&a[0], &a[1]), value_out)
        }
        "input_rule_triggers" => Ok(rm::edit::input_rule_triggers().as_bytes().to_vec()),
        "input_rule_matches" => {
            let request = json(input)?;
            let (Some(before), Some(text)) = (request.get("before").and_then(Value::as_str), request.get("text").and_then(Value::as_str)) else {
                return Err("Invalid input rule match".to_owned());
            };
            Ok(value_out(Value::Bool(rm::edit::input_rule_matches(before, text))))
        }
        "task_drafts" => engine(rm::edit::task_drafts(&json(input)?, &options), value_out),
        "task_draft_arm" => engine(rm::edit::task_draft_arm(&json(input)?, &options), value_out),
        "task_draft_boundary" => engine(rm::edit::task_draft_boundary(&json(input)?, &options), value_out),
        "clipboard_anchors" => engine(rm::edit::plan_clipboard_anchors(&json(input)?), value_out),
        "clipboard_headings" => engine(rm::edit::plan_clipboard_headings(&json(input)?), value_out),
        "contract" => Ok(value_out(rm::contract())),
        other => Err(format!("Unknown RelayMark job {other}")),
    }
}
