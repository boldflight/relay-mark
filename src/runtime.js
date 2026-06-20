import { compileParsedDocument } from "./compiler.js";
import { parseRelayMark } from "./parser.js";
import { projectManifest } from "./projections.js";
import { validateDocument } from "./validator.js";

export function compileRelayMark(source) {
  const parsed = parseRelayMark(source);
  const compiled = compileParsedDocument(parsed);
  const validationDiagnostics = validateDocument(compiled.document);
  const diagnostics = [...compiled.diagnostics, ...validationDiagnostics];

  return {
    document: compiled.document,
    manifest: projectManifest(compiled.document, diagnostics),
    diagnostics
  };
}
