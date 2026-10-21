//! Transported Agent Answer pairs: exact document and manifest bytes,
//! validated together under explicit host context, digested as received.

use serde_json::{Value, json};

use crate::error::Result;
use crate::json;
use crate::manifest::project_manifest;
use crate::validate::validate_document;

fn error(code: &str, message: &str) -> Value {
    json!({"level": "error", "code": code, "message": message})
}

/// `sha256:` followed by the lowercase hex digest of the exact bytes.
pub fn sha256_digest(bytes: &[u8]) -> String {
    format!("sha256:{}", json::sha256_hex(bytes))
}

/// Validate exact UTF-8 JSON bytes for a document and its manifest.
/// Returns `{document, manifest, document_digest, manifest_digest, diagnostics}`.
pub fn validate_transported_agent_answer_pair(document_bytes: &[u8], manifest_bytes: &[u8], context: &Value) -> Result<Value> {
    let decode = |bytes: &[u8]| -> Result<Value> {
        let text = std::str::from_utf8(bytes).map_err(|_| crate::Error::new("Transported JSON must be UTF-8."))?;
        json::parse(text)
    };
    let document = decode(document_bytes)?;
    let manifest = decode(manifest_bytes)?;
    let mut diagnostics = Vec::new();
    if !crate::json_schema::validate(&document, "relaymark-document.schema.json").is_empty() {
        diagnostics.push(error("relaymark.schema.invalid", "Document does not conform to the RelayMark document schema."));
    } else if document.get("frontmatter").and_then(|f| f.get("profile")).and_then(Value::as_str) != Some("relaymark.agent_answer") {
        diagnostics.push(error("relaymark.agent_answer.profile", "Transported Agent Answer document must declare frontmatter.profile relaymark.agent_answer."));
    } else {
        diagnostics.extend(validate_document(&document, context));
    }
    if diagnostics.is_empty() && !json::deep_equal(&project_manifest(&document, &[]), &manifest) {
        diagnostics.push(error(
            "relaymark.agent_answer.manifest_mismatch",
            "Transported relaymark.agent_answer manifest must exactly match the canonical projection of its document.",
        ));
    }
    Ok(json!({
        "document": document,
        "manifest": manifest,
        "document_digest": sha256_digest(document_bytes),
        "manifest_digest": sha256_digest(manifest_bytes),
        "diagnostics": diagnostics,
    }))
}
