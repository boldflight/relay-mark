//! `relaymark-core`: the one RelayMark engine.
//!
//! Every conversion the reference runtime (JavaScript) and the Elixir adapter
//! each implement today, in one crate that runs natively on the server, on
//! Apple platforms and, through WebAssembly, in browsers:
//!
//! | Job | Functions |
//! |---|---|
//! | Markdown to document | [`parse_document`] |
//! | Document to stored source | [`serialize_document`] (the exact `relaymark-ast` interchange) |
//! | Document to Markdown | [`project_markdown`] |
//! | Document to HTML | [`render_html`] |
//! | Validation | [`normalize_document`], [`validate`], [`project_manifest`], [`compile`] |
//! | Snapshot / editor import | [`document_to_snapshot`], [`snapshot_to_document`], [`document_to_prosemirror`], [`prosemirror_to_document`], [`import`] |
//!
//! Values are JSON ([`serde_json::Value`]) with object key order preserved, so
//! [`to_json`] reproduces the reference runtime's bytes. The specification in
//! `spec/relaymark/` (editor schema, directive registry, JSON Schemas) is
//! compiled in; there is no other copy of it here.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

mod adapter;
mod compile;
mod compose;
mod controls;
mod error;
mod html;
mod inline;
mod json;
mod json_schema;
mod jsre;
mod links;
mod manifest;
mod mdurl;
mod migrate;
mod node_kind;
mod registry;
mod schema;
mod snapshot;
mod source;
mod transport;
mod validate;

pub use error::{Error, Result};
pub use serde_json::Value;

/// Source text to the canonical document AST. An exact `relaymark-ast` fence
/// is decoded as-is; anything else is CommonMark plus RelayMark directives,
/// with block identities derived from `namespace` (the source text when `None`)
/// and each block's position, so re-importing the same source is stable.
pub fn parse_document(source: &str, namespace: Option<&str>) -> Result<Value> {
    source::parse_document(source, namespace)
}

/// The stored source form: one `relaymark-ast` fence holding the normalized
/// document JSON. Refuses documents that are not canonical-admissible.
pub fn serialize_document(document: &Value) -> Result<String> {
    source::serialize_document(document)
}

/// Readable Markdown for search, export and review. Derived, never stored.
pub fn project_markdown(document: &Value) -> Result<String> {
    source::project_markdown(document)
}

/// Safe static HTML. Links are hardened; hosts hydrate widgets.
pub fn render_html(document: &Value) -> Result<String> {
    html::render_document(document)
}

/// Canonical semantic normalization (adjacent equal text runs join); refuses
/// any document the editor schema or the AST contract would not admit.
pub fn normalize_document(document: &Value) -> Result<Value> {
    snapshot::normalize_document(document)
}

/// Document to the portable XML snapshot of the collaborative fragment.
pub fn document_to_snapshot(document: &Value) -> Result<Value> {
    snapshot::document_to_snapshot(document)
}

/// Portable XML snapshot (for example from Yjs/Yrs) to the document.
pub fn snapshot_to_document(snapshot: &Value) -> Result<Value> {
    snapshot::snapshot_to_document(snapshot)
}

/// Document to editor (ProseMirror/TipTap) JSON in the canonical schema.
pub fn document_to_prosemirror(document: &Value) -> Result<Value> {
    adapter::to_prosemirror(document)
}

/// Editor (ProseMirror/TipTap) JSON to the document. Strict and lossless.
pub fn prosemirror_to_document(prosemirror: &Value) -> Result<Value> {
    adapter::to_relaymark(prosemirror)
}

/// Authored destinations (explicit anchors, then headings) of a document.
pub fn paper_destinations(document: &Value) -> Result<Vec<Value>> {
    let normalized = normalize_document(document)?;
    Ok(controls::paper_destinations(&adapter::to_prosemirror(&normalized)?))
}

/// Validate editor typing attributes (marks and link properties).
pub fn validate_text_attributes(attributes: &Value) -> Result<()> {
    inline::validate_text_attributes(attributes)
}

/// Semantic diagnostics for a conformance AST. `context` carries host-only
/// facts (`{"surface": "scripture_ask"}`) and may be `Value::Null`.
pub fn validate(document: &Value, context: &Value) -> Vec<Value> {
    validate::validate_document(document, context)
}

/// Diagnostics for a single directive block, without evidence resolution.
pub fn validate_directive(block: &Value) -> Vec<Value> {
    validate::validate_directive_node(block)
}

/// The manifest projection of a document with the given diagnostics.
pub fn project_manifest(document: &Value, diagnostics: &[Value]) -> Value {
    manifest::project_manifest(document, diagnostics)
}

/// Plain text of any AST node or node list; references contribute labels.
pub fn plain_text(node: &Value) -> String {
    manifest::to_plain_text(node)
}

/// Compile plain RelayMark composition source to `{document, manifest, diagnostics}`.
pub fn compile(source: &str) -> Value {
    compile::compile(source)
}

/// Serialize the human-authored subset of a conformance AST to deterministic
/// RelayMark composition source.
pub fn serialize_source(document: &Value) -> Result<String> {
    compile::serialize(document)
}

/// Deterministic linear composition of already-authorized layer contributions.
pub fn compose_layers(layers: &Value) -> Value {
    compose::compose_layers(layers)
}

/// Capability resolutions for a renderer supporting `supported` capability ids.
pub fn negotiate_capabilities(document: &Value, supported: &[&str]) -> Vec<Value> {
    compose::negotiate_capabilities(document, supported)
}

/// Validate an exact transported Agent Answer document and manifest pair.
pub fn validate_transported_agent_answer_pair(document_json: &[u8], manifest_json: &[u8], context: &Value) -> Result<Value> {
    transport::validate_transported_agent_answer_pair(document_json, manifest_json, context)
}

/// JSON Schema errors of `value` against a packaged schema file name such as
/// `relaymark-document.schema.json`.
pub fn validate_schema(value: &Value, schema_file: &str) -> Vec<Value> {
    json_schema::validate(value, schema_file)
}

/// `JSON.stringify` of a value: the reference runtime's exact bytes.
pub fn to_json(value: &Value) -> String {
    json::stringify(value)
}

/// The canonical compatibility contract with its physical schema hash.
pub fn contract() -> Value {
    let mut contract: Value = serde_json::from_str(schema::CONTRACT_JSON).unwrap_or(Value::Null);
    let encoding: Value = serde_json::from_str(schema::ATTRIBUTE_ENCODING_JSON).unwrap_or(Value::Null);
    let hash = json::canonical_sha256(&serde_json::json!({"editor_schema": schema::editor_schema().source, "xml_attribute_encoding": encoding}));
    contract["schema_hash"] = Value::String(hash);
    contract
}

/// The canonical editor schema (`spec/relaymark/editor-schema.json`).
pub fn editor_schema() -> &'static Value {
    &schema::editor_schema().source
}

/// Finite historical conversions, each run once at a recorded boundary with a
/// retained namespace. Ordinary editing never calls these.
pub mod import {
    use super::{Result, Value};

    /// Prerelease AST to the canonical document: `{document, identity_mapping}`.
    pub fn document(original: &Value, namespace: &str) -> Result<Value> {
        crate::migrate::import_document(original, namespace)
    }

    /// Historical source (exact or Markdown): `{document, identity_mapping}`.
    pub fn source(source: &str, namespace: &str) -> Result<Value> {
        crate::migrate::import_document_source(source, namespace)
    }

    /// Historical XML snapshot: `{snapshot, document, identity_mapping,
    /// normalizations, requires_reconstruction}`; the normalizations are edits
    /// for the host's existing CRDT transaction.
    pub fn snapshot(original: &Value, namespace: &str) -> Result<Value> {
        crate::migrate::import_document_snapshot(original, namespace)
    }

    /// Detached preview of an aggregate-settings archive.
    pub fn aggregate_settings_snapshot(snapshot: &Value) -> Result<Value> {
        crate::migrate::import_aggregate_settings_snapshot(snapshot)
    }

    /// Saved form publication: `{document, identity_mapping, normalizations}`.
    pub fn form_publication(publication: &Value, namespace: &str, retained_source: Option<&str>) -> Result<Value> {
        crate::migrate::import_form_publication(publication, namespace, retained_source)
    }
}
