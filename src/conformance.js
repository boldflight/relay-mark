import { readFileSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import { equalCanonicalJSON } from "./canonical-json.js";
import { validateJSONSchema } from "./json-schema.js";
import { compileRelayMark } from "./runtime.js";
import { projectManifest } from "./projections.js";
import { validateTransportedAgentAnswerPair } from "./transport.js";
import { validateDocument } from "./validator.js";
import { composeLayerContributions } from "./composition.js";

export function runConformanceSuite(path) {
  const suitePath = resolve(path);
  const suiteDir = dirname(suitePath);
  const suite = JSON.parse(readFileSync(suitePath, "utf8"));
  const fixtures = [];

  for (const fixture of suite.fixtures || []) {
    const actual = fixture.input_composition
      ? compileComposition(resolve(suiteDir, fixture.input_composition))
      : fixture.input_manifest
      ? compileTransportedPair(suiteDir, fixture)
      : fixture.input_ast
      ? compileCanonicalAST(
          resolve(suiteDir, fixture.input_ast),
          fixture.validation_context
        )
      : compileRelayMark(readFileSync(resolve(suiteDir, fixture.source), "utf8"));
    const errors = [];
    let expectedDocument;
    let expectedManifest;
    let expectedDiagnostics;

    if (fixture.expected_composition) {
      const expectedComposition = JSON.parse(
        readFileSync(resolve(suiteDir, fixture.expected_composition), "utf8")
      );

      if (!equalCanonicalJSON(actual.composition, expectedComposition)) {
        errors.push("composed layers did not match expected_composition");
      }
    }

    if (fixture.expected_ast) {
      expectedDocument = JSON.parse(readFileSync(resolve(suiteDir, fixture.expected_ast), "utf8"));

      if (!equalCanonicalJSON(actual.document, expectedDocument)) {
        errors.push("compiled AST did not match expected_ast");
      }
    }

    if (fixture.expected_manifest) {
      expectedManifest = JSON.parse(readFileSync(resolve(suiteDir, fixture.expected_manifest), "utf8"));

      if (!equalCanonicalJSON(actual.manifest, expectedManifest)) {
        errors.push("projected manifest did not match expected_manifest");
      }
    }

    if (fixture.expected_diagnostics) {
      expectedDiagnostics = JSON.parse(readFileSync(resolve(suiteDir, fixture.expected_diagnostics), "utf8"));

      if (!equalCanonicalJSON(actual.diagnostics, expectedDiagnostics)) {
        errors.push("compiler diagnostics did not match expected_diagnostics");
      }
    }

    for (const schemaReference of fixture.schemas || []) {
      const schemaPath = resolve(suiteDir, schemaReference);

      try {
        const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
        const outputType = schema.properties?.type?.const;
        const targets = schemaTargets(outputType, actual, expectedDocument, expectedManifest);

        if (targets.length === 0) {
          errors.push(
            `schema ${basename(schemaPath)} does not identify relaymark.document or relaymark.manifest via properties.type.const`
          );
          continue;
        }

        for (const target of targets) {
          for (const validationError of validateJSONSchema(target.value, schema, schemaPath)) {
            errors.push(
              `${target.label} failed ${basename(schemaPath)} at ${validationError.instance_path}: ${validationError.message}`
            );
          }
        }
      } catch (error) {
        errors.push(`could not apply schema ${basename(schemaPath)}: ${error.message}`);
      }
    }

    fixtures.push({
      id: fixture.id,
      ok: errors.length === 0,
      errors
    });
  }

  return {
    ok: fixtures.every((fixture) => fixture.ok),
    fixtures
  };
}

function compileCanonicalAST(path, validationContext = {}) {
  const document = JSON.parse(readFileSync(path, "utf8"));
  const diagnostics = validateDocument(document, validationContext);

  return {
    document,
    diagnostics,
    manifest: projectManifest(document, diagnostics)
  };
}

function compileComposition(path) {
  const layerComposition = JSON.parse(readFileSync(path, "utf8"));
  const composition = composeLayerContributions(layerComposition.layers);

  return {
    layerComposition,
    composition,
    diagnostics: composition.diagnostics
  };
}

function compileTransportedPair(suiteDir, fixture) {
  return validateTransportedAgentAnswerPair(
    readFileSync(resolve(suiteDir, fixture.input_ast)),
    readFileSync(resolve(suiteDir, fixture.input_manifest)),
    fixture.validation_context
  );
}

function schemaTargets(outputType, actual, expectedDocument, expectedManifest) {
  if (outputType === "relaymark.document") {
    return compactTargets([
      { label: "compiled AST", value: actual.document },
      { label: "expected AST", value: expectedDocument }
    ]);
  }

  if (outputType === "relaymark.manifest") {
    return compactTargets([
      { label: "projected manifest", value: actual.manifest },
      { label: "expected manifest", value: expectedManifest }
    ]);
  }

  if (outputType === "relaymark.layer_composition") {
    return compactTargets([
      { label: "layer composition", value: actual.layerComposition }
    ]);
  }

  return [];
}

function compactTargets(targets) {
  return targets.filter(({ value }) => value !== undefined);
}
