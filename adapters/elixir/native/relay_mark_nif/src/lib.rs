//! The RelayMark engine as one Erlang NIF: a job name, its input bytes and its
//! options as JSON, answered with `{:ok, binary}` or `{:error, reason}`.
//! `run` stays on a normal scheduler for small inputs; `run_dirty` takes the
//! same call on a dirty CPU scheduler, which the Elixir side picks by size.

use relaymark_core as rm;
use relaymark_core::Value;
use rustler::{Atom, Binary, Encoder, Env, OwnedBinary, Term};

mod atoms {
    rustler::atoms! { ok, error }
}

#[rustler::nif]
fn run<'a>(env: Env<'a>, job: &str, input: Binary, options: Binary) -> Term<'a> {
    answer(env, job, input.as_slice(), options.as_slice())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn run_dirty<'a>(env: Env<'a>, job: &str, input: Binary, options: Binary) -> Term<'a> {
    answer(env, job, input.as_slice(), options.as_slice())
}

fn answer<'a>(env: Env<'a>, job: &str, input: &[u8], options: &[u8]) -> Term<'a> {
    let outcome = std::panic::catch_unwind(|| dispatch(job, input, options))
        .unwrap_or_else(|_| Err(format!("relaymark-core panicked in {job}")));
    let (tag, bytes): (Atom, Vec<u8>) = match outcome {
        Ok(bytes) => (atoms::ok(), bytes),
        Err(reason) => (atoms::error(), reason.into_bytes()),
    };
    let mut binary = OwnedBinary::new(bytes.len()).expect("allocate result binary");
    binary.as_mut_slice().copy_from_slice(&bytes);
    (tag, binary.release(env)).encode(env)
}

type Answer = Result<Vec<u8>, String>;

fn text(input: &[u8]) -> Result<&str, String> {
    std::str::from_utf8(input).map_err(|_| "Input is not UTF-8".to_owned())
}

fn json(input: &[u8]) -> Result<Value, String> {
    serde_json::from_slice(input).map_err(|e| format!("Invalid JSON input: {e}"))
}

/// Elixir maps carry no key order; give a document envelope the order the
/// reference runtime builds it in, so stored source matches the web's bytes.
fn document(input: &[u8]) -> Result<Value, String> {
    let mut value = json(input)?;
    if let Value::Object(map) = &mut value {
        const ORDER: [&str; 7] = [
            "type",
            "version",
            "frontmatter",
            "blocks",
            "annotations",
            "resources",
            "meta",
        ];
        let mut ordered = rm::Value::Object(Default::default());
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

fn dispatch(job: &str, input: &[u8], options: &[u8]) -> Answer {
    let options = if options.is_empty() {
        Value::Null
    } else {
        json(options)?
    };
    match job {
        "parse" => engine(
            rm::parse_document(text(input)?, option(&options, "namespace")),
            value_out,
        ),
        "import_source" => engine(
            rm::import::source(text(input)?, required(&options, "namespace")?),
            value_out,
        ),
        "serialize" => engine(
            rm::serialize_document(&document(input)?),
            String::into_bytes,
        ),
        "markdown" => engine(rm::project_markdown(&document(input)?), String::into_bytes),
        "html" => engine(rm::render_html(&document(input)?), String::into_bytes),
        "project" => {
            let document = document(input)?;
            let body = rm::project_markdown(&document).map_err(|e| e.message().to_owned())?;
            let html = rm::render_html(&document).map_err(|e| e.message().to_owned())?;
            Ok(value_out(
                serde_json::json!({"body": body, "body_html": html}),
            ))
        }
        "normalize" => engine(rm::normalize_document(&document(input)?), value_out),
        "to_snapshot" => engine(rm::document_to_snapshot(&document(input)?), value_out),
        "from_snapshot" => engine(rm::snapshot_to_document(&json(input)?), value_out),
        "import_document" => engine(
            rm::import::document(&document(input)?, required(&options, "namespace")?),
            value_out,
        ),
        "import_snapshot" => engine(
            rm::import::snapshot(&json(input)?, required(&options, "namespace")?),
            value_out,
        ),
        "aggregate_settings" => engine(
            rm::import::aggregate_settings_snapshot(&json(input)?),
            value_out,
        ),
        "form_publication" => {
            let namespace = required(&options, "namespace")?;
            engine(
                rm::import::form_publication(&json(input)?, namespace, option(&options, "source")),
                value_out,
            )
        }
        "validate_document" => {
            let document = json(input)?;
            let schema = rm::validate_schema(&document, "relaymark-document.schema.json");
            if !schema.is_empty() {
                return Ok(value_out(serde_json::json!({ "schema": schema })));
            }
            let context = options.get("context").cloned().unwrap_or(Value::Null);
            Ok(value_out(
                serde_json::json!({ "diagnostics": rm::validate(&document, &context) }),
            ))
        }
        "schema" => Ok(value_out(Value::Array(rm::validate_schema(
            &json(input)?,
            required(&options, "schema")?,
        )))),
        "manifest" => {
            let diagnostics = options
                .get("diagnostics")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            Ok(value_out(rm::project_manifest(&json(input)?, &diagnostics)))
        }
        "transported_pair" => {
            let manifest = required(&options, "manifest")?;
            let context = options.get("context").cloned().unwrap_or(Value::Null);
            engine(
                rm::validate_transported_agent_answer_pair(input, manifest.as_bytes(), &context),
                value_out,
            )
        }
        "compose" => Ok(value_out(rm::compose_layers(&json(input)?))),
        "text_attributes" => engine(rm::validate_text_attributes(&json(input)?), |()| {
            b"true".to_vec()
        }),
        "entity_reference_source" => engine(
            rm::entity_reference_source(
                required(&options, "type")?,
                required(&options, "id")?,
                required(&options, "label")?,
            ),
            String::into_bytes,
        ),
        "paper_control_source" => {
            engine(rm::paper_control_source(&json(input)?), String::into_bytes)
        }
        "parse_entity_reference" => Ok(value_out(
            rm::parse_entity_reference(text(input)?).unwrap_or(Value::Null),
        )),
        "contract" => Ok(value_out(rm::contract())),
        other => Err(format!("Unknown RelayMark job {other}")),
    }
}

rustler::init!("Elixir.RelayMark.Native");
