import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { compileRelayMark } from "../src/index.js";
import { runConformanceSuite } from "../src/conformance.js";

describe("RelayMark reference runtime", () => {
  it("compiles the mentor meeting fixture to the expected AST", () => {
    const source = readFileSync(resolve("spec/relaymark/examples/mentor-meeting.relaymark"), "utf8");
    const expected = JSON.parse(readFileSync(resolve("spec/relaymark/examples/mentor-meeting.ast.json"), "utf8"));
    const result = compileRelayMark(source);

    assert.deepEqual(result.document, expected);
    assert.deepEqual(result.diagnostics, []);
  });

  it("projects the mentor meeting fixture manifest", () => {
    const source = readFileSync(resolve("spec/relaymark/examples/mentor-meeting.relaymark"), "utf8");
    const expected = JSON.parse(readFileSync(resolve("spec/relaymark/examples/mentor-meeting.manifest.json"), "utf8"));
    const result = compileRelayMark(source);

    assert.deepEqual(result.manifest, expected);
  });

  it("runs the conformance suite", () => {
    const result = runConformanceSuite("spec/relaymark/conformance/suite.json");

    assert.equal(result.ok, true);
  });
});
