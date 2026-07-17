import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { compileRelayMark, isBlockNode, isInlineNode, projectManifest } from "../src/index.js";
import { runConformanceSuite } from "../src/conformance.js";
import { validateDocument } from "../src/validator.js";

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

  it("projects product research references, evidence, claims, comparisons, and review outcomes", () => {
    const source = readFileSync(resolve("spec/relaymark/examples/product-research.relaymark"), "utf8");
    const expectedDocument = JSON.parse(
      readFileSync(resolve("spec/relaymark/examples/product-research.ast.json"), "utf8")
    );
    const expectedManifest = JSON.parse(
      readFileSync(resolve("spec/relaymark/examples/product-research.manifest.json"), "utf8")
    );
    const result = compileRelayMark(source);

    assert.deepEqual(result.document, expectedDocument);
    assert.deepEqual(result.manifest, expectedManifest);
    assert.deepEqual(result.diagnostics, []);
    assert.deepEqual(result.manifest.actions.map(({ review }) => review), ["accepted", "rejected"]);
    assert.deepEqual(result.manifest.claims.map(({ status }) => status), ["disputed", "disputed"]);
    assert.equal(result.manifest.comparisons[0].layout, "table");
    assert.deepEqual(result.manifest.sources.map(({ kind }) => kind), [
      "source_bundle",
      "url_ref",
      "url_ref",
      "source_bundle",
      "file_ref",
      "url_ref"
    ]);
  });

  it("runs the conformance suite", () => {
    const result = runConformanceSuite("spec/relaymark/conformance/suite.json");

    assert.equal(result.ok, true);
  });

  it("does not validate inline entity references as Relay blocks", () => {
    assert.equal(isInlineNode({ type: "relay.entity_ref", id: "product-1" }), true);
    assert.equal(isBlockNode({ type: "relay.url_ref", id: "b2" }), true);

    const diagnostics = validateDocument({
      type: "relaymark.document",
      version: 1,
      blocks: [
        {
          id: "b1",
          type: "paragraph",
          content: [{ type: "relay.entity_ref", id: "product-1", label: "Mac mini" }]
        }
      ]
    });

    assert.deepEqual(diagnostics, []);
  });

  it("validates malformed nested blocks and evidence-required research blocks", () => {
    assert.equal(isBlockNode({ type: "relay.url_ref" }), true);

    const malformedDiagnostics = validateDocument({
      type: "relaymark.document",
      version: 1,
      blocks: [
        {
          id: "b1",
          type: "relay.source_bundle",
          props: { id: "src-1" },
          content: [{ type: "relay.url_ref", props: { url: "https://example.com" } }]
        }
      ]
    });

    assert.deepEqual(
      malformedDiagnostics.map(({ code }) => code),
      ["relaymark.block.id"]
    );

    const research = compileRelayMark(`@Claim(key: "unsupported") {
  This claim has no evidence.
}

@Comparison(
  subjects: ["entity:first", "entity:second"],
  criteria: ["price"],
  values: {"price": {"entity:first": 1, "entity:second": 2}}
) {
  This comparison has no evidence.
}`);

    assert.deepEqual(
      research.diagnostics.map(({ code }) => code),
      ["relaymark.policy.evidence_required", "relaymark.policy.evidence_required"]
    );

    const normalizedClaim = {
      type: "relaymark.document",
      version: 1,
      blocks: [
        {
          id: "source-1",
          type: "relay.source_bundle",
          props: { id: "source-1" },
          content: [
            {
              id: "source-url",
              type: "relay.url_ref",
              props: { url: "https://example.com/evidence" },
              content: []
            }
          ]
        },
        {
          id: "claim-1",
          type: "relay.claim",
          props: { key: "supported", status: "supported", evidence: ["source-1"] },
          evidence_refs: [],
          content: [{ type: "text", text: "A supported claim." }]
        }
      ]
    };

    assert.deepEqual(validateDocument(normalizedClaim), []);
    assert.deepEqual(projectManifest(normalizedClaim).claims[0].evidence_refs, ["source-1"]);
  });

  it("rejects invalid research semantics and unresolved evidence", () => {
    const result = compileRelayMark(`@Claim(key: "bad-confidence", confidence: 1.2, evidence: ["missing-source"]) {
  This claim overstates its confidence.
}

@Comparison(
  subjects: ["entity:first", "entity:first"],
  criteria: ["score", "score"],
  values: {"score": {"entity:first": 1}},
  evidence: ["missing-source"]
) {
  This comparison repeats its dimensions.
}

@Comparison(
  subjects: ["entity:first", "entity:second"],
  criteria: ["score"],
  values: {"score": {"entity:first": 1}},
  preferred: "entity:third",
  evidence: ["missing-source"]
) {
  This comparison omits an explicit value.
}`);

    assert.deepEqual(
      result.diagnostics.map(({ code }) => code),
      [
        "relaymark.evidence.unresolved_reference",
        "relaymark.claim.confidence_range",
        "relaymark.evidence.unresolved_reference",
        "relaymark.comparison.subjects",
        "relaymark.comparison.criteria",
        "relaymark.evidence.unresolved_reference",
        "relaymark.comparison.preferred",
        "relaymark.comparison.values_coverage"
      ]
    );
  });

  it("fails conformance when a fixture does not satisfy a declared schema", () => {
    const directory = mkdtempSync(join(tmpdir(), "relaymark-conformance-"));

    try {
      const source = "# Schema validation fixture\n";
      const compiled = compileRelayMark(source);
      writeFileSync(join(directory, "fixture.relaymark"), source);
      writeFileSync(join(directory, "fixture.ast.json"), JSON.stringify(compiled.document));
      writeFileSync(
        join(directory, "reject-document.schema.json"),
        JSON.stringify({
          type: "object",
          required: ["schema_proof"],
          properties: {
            type: { const: "relaymark.document" },
            schema_proof: { const: true }
          }
        })
      );
      writeFileSync(
        join(directory, "suite.json"),
        JSON.stringify({
          type: "relaymark.conformance_suite",
          version: "test",
          fixtures: [
            {
              id: "declared-schema",
              source: "fixture.relaymark",
              expected_ast: "fixture.ast.json",
              schemas: ["reject-document.schema.json"]
            }
          ]
        })
      );

      const result = runConformanceSuite(join(directory, "suite.json"));

      assert.equal(result.ok, false);
      assert.equal(result.fixtures[0].ok, false);
      assert.deepEqual(result.fixtures[0].errors, [
        "compiled AST failed reject-document.schema.json at /: must contain required property 'schema_proof'",
        "expected AST failed reject-document.schema.json at /: must contain required property 'schema_proof'"
      ]);

      writeFileSync(
        join(directory, "reject-document.schema.json"),
        JSON.stringify({
          type: "object",
          properties: { type: { const: "relaymark.document" } },
          allOf: []
        })
      );

      const unsupported = runConformanceSuite(join(directory, "suite.json"));

      assert.equal(unsupported.ok, false);
      assert.deepEqual(unsupported.fixtures[0].errors, [
        "could not apply schema reject-document.schema.json: Unsupported JSON Schema keyword 'allOf' at #."
      ]);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  it("accepts Relay's canonical organization and unlisted visibility values", () => {
    const result = compileRelayMark(`@SourceBundle(id: "source-1", scope: "unlisted") {
  @UrlRef(url: "https://example.com", scope: "org") {
  }
}

@ActionRow(action: "product_feedback", visibility: "org", review: "draft") {
  Propose a source-backed correction.
}`);

    assert.deepEqual(result.diagnostics, []);
    assert.equal(result.document.blocks[0].props.scope, "unlisted");
    assert.equal(result.document.blocks[1].props.visibility, "org");
  });
});
