import { readFileSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import { validateJSONSchema } from "./json-schema.js";
import { compileRelayMark } from "./runtime.js";

export function runConformanceSuite(path) {
  const suitePath = resolve(path);
  const suiteDir = dirname(suitePath);
  const suite = JSON.parse(readFileSync(suitePath, "utf8"));
  const fixtures = [];

  for (const fixture of suite.fixtures || []) {
    const source = readFileSync(resolve(suiteDir, fixture.source), "utf8");
    const actual = compileRelayMark(source);
    const errors = [];
    let expectedDocument;
    let expectedManifest;

    if (fixture.expected_ast) {
      expectedDocument = JSON.parse(readFileSync(resolve(suiteDir, fixture.expected_ast), "utf8"));

      if (!deepEqual(actual.document, expectedDocument)) {
        errors.push("compiled AST did not match expected_ast");
      }
    }

    if (fixture.expected_manifest) {
      expectedManifest = JSON.parse(readFileSync(resolve(suiteDir, fixture.expected_manifest), "utf8"));

      if (!deepEqual(actual.manifest, expectedManifest)) {
        errors.push("projected manifest did not match expected_manifest");
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

  return [];
}

function compactTargets(targets) {
  return targets.filter(({ value }) => value !== undefined);
}

function deepEqual(left, right) {
  return stableStringify(left) === stableStringify(right);
}

function stableStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }

  if (value && typeof value === "object") {
    const entries = Object.entries(value)
      .filter(([, item]) => item !== undefined)
      .sort(([a], [b]) => a.localeCompare(b));
    return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${stableStringify(item)}`).join(",")}}`;
  }

  return JSON.stringify(value);
}
