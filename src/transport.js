import { createHash } from "node:crypto";
import { equalCanonicalJSON } from "./canonical-json.js";
import { projectManifest } from "./projections.js";
import { validateDocument } from "./validator.js";

const agentAnswerProfile = "relaymark.agent_answer.v1";

export function validateTransportedAgentAnswerPair(
  documentJSON,
  manifestJSON,
  validationContext = {}
) {
  const documentBytes = exactBytes(documentJSON, "documentJSON");
  const manifestBytes = exactBytes(manifestJSON, "manifestJSON");
  const document = JSON.parse(documentBytes.toString("utf8"));
  const manifest = JSON.parse(manifestBytes.toString("utf8"));
  const diagnostics = [];

  if (document.frontmatter?.profile !== agentAnswerProfile) {
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

function error(code, message) {
  return { level: "error", code, message };
}
