import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
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

    if (fixture.expected_ast) {
      const expectedAst = JSON.parse(readFileSync(resolve(suiteDir, fixture.expected_ast), "utf8"));

      if (!deepEqual(actual.document, expectedAst)) {
        errors.push("compiled AST did not match expected_ast");
      }
    }

    if (fixture.expected_manifest) {
      const expectedManifest = JSON.parse(readFileSync(resolve(suiteDir, fixture.expected_manifest), "utf8"));

      if (!deepEqual(actual.manifest, expectedManifest)) {
        errors.push("projected manifest did not match expected_manifest");
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
