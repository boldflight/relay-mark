import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { equalCanonicalJSON } from "./canonical-json.js";
import { validateJSONSchema } from "./json-schema.js";
import { projectManifest } from "./projections.js";
import { validateDocument } from "./validator.js";

const agentAnswerProfile = "relaymark.agent_answer.v1";
const documentSchemaPath = fileURLToPath(
  new URL("../spec/relaymark/schemas/relaymark-document.schema.json", import.meta.url)
);
const documentSchema = JSON.parse(readFileSync(documentSchemaPath, "utf8"));
const strictUTF8Decoder = new TextDecoder("utf-8", { fatal: true });

export function validateTransportedAgentAnswerPair(
  documentJSON,
  manifestJSON,
  validationContext = {}
) {
  const documentBytes = exactBytes(documentJSON, "documentJSON");
  const manifestBytes = exactBytes(manifestJSON, "manifestJSON");
  const document = decodeExactJSON(documentBytes);
  const manifest = decodeExactJSON(manifestBytes);
  const diagnostics = [];

  if (
    validateJSONSchema(document, documentSchema, documentSchemaPath).length > 0
  ) {
    diagnostics.push(
      error(
        "relaymark.schema.invalid",
        "Document does not conform to the RelayMark document schema."
      )
    );
  } else if (document.frontmatter?.profile !== agentAnswerProfile) {
    diagnostics.push(
      error(
        "relaymark.agent_answer.profile",
        "Transported Agent Answer document must declare frontmatter.profile relaymark.agent_answer.v1."
      )
    );
  } else {
    diagnostics.push(...validateDocument(document, validationContext));
  }

  if (
    diagnostics.length === 0 &&
    !equalCanonicalJSON(projectManifest(document, []), manifest)
  ) {
    diagnostics.push(
      error(
        "relaymark.agent_answer.manifest_mismatch",
        "Transported relaymark.agent_answer.v1 manifest must exactly match the canonical projection of its document."
      )
    );
  }

  return {
    document,
    manifest,
    document_digest: sha256Digest(documentBytes),
    manifest_digest: sha256Digest(manifestBytes),
    diagnostics
  };
}

export function sha256Digest(value) {
  const bytes = exactBytes(value, "value");
  return `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
}

function exactBytes(value, label) {
  if (typeof value === "string") {
    return Buffer.from(value, "utf8");
  }

  if (value instanceof Uint8Array) {
    return Buffer.from(value.buffer, value.byteOffset, value.byteLength);
  }

  throw new TypeError(`${label} must be a UTF-8 string or Uint8Array.`);
}

function decodeExactJSON(bytes) {
  const value = JSON.parse(strictUTF8Decoder.decode(bytes));
  assertUnicodeScalarJSON(value);
  return value;
}

function assertUnicodeScalarJSON(value) {
  if (typeof value === "string") {
    if (/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?:^|[^\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(value)) {
      throw new SyntaxError("Transported JSON strings must contain valid Unicode scalar values.");
    }

    return;
  }

  if (Array.isArray(value)) {
    for (const item of value) assertUnicodeScalarJSON(item);
    return;
  }

  if (value !== null && typeof value === "object") {
    for (const [key, item] of Object.entries(value)) {
      assertUnicodeScalarJSON(key);
      assertUnicodeScalarJSON(item);
    }
  }
}

function error(code, message) {
  return { level: "error", code, message };
}
