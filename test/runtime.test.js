import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { compileRelayMark, isBlockNode, isInlineNode, projectManifest } from "../src/index.js";
import { runConformanceSuite } from "../src/conformance.js";
import { validateJSONSchema } from "../src/json-schema.js";
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

  it("projects stable evidence and lifecycle-aware action proposals", () => {
    const source = readFileSync(resolve("spec/relaymark/examples/agent-paper-review.relaymark"), "utf8");
    const expectedDocument = JSON.parse(
      readFileSync(resolve("spec/relaymark/examples/agent-paper-review.ast.json"), "utf8")
    );
    const expectedManifest = JSON.parse(
      readFileSync(resolve("spec/relaymark/examples/agent-paper-review.manifest.json"), "utf8")
    );
    const result = compileRelayMark(source);

    assert.deepEqual(result.document, expectedDocument);
    assert.deepEqual(result.manifest, expectedManifest);
    assert.deepEqual(result.diagnostics, []);
    assert.equal(result.document.blocks[2].id, "b3");
    assert.equal(result.document.blocks[2].props.id, "source-review-1");
    assert.equal(result.document.blocks[2].content[0].id, "b4");
    assert.equal(result.document.blocks[2].content[0].props.id, "70000000-0000-4000-8000-000000000001");
    assert.equal(result.document.blocks[5].id, "b9");
    assert.equal(result.document.blocks[5].props.proposal_id, "practice-task");
    assert.equal(
      result.document.blocks[5].props.proposal_record_id,
      "10000000-0000-4000-8000-000000000001"
    );
    assert.deepEqual(result.manifest.actions.map(({ action }) => action), [
      "task_create",
      "log_touchpoint",
      "journey_advance",
      "link_create",
      "follow_up_create"
    ]);
    assert.deepEqual(result.manifest.actions.map(({ review }) => review), [
      "ready",
      "accepted",
      "rejected",
      "undone",
      "ready"
    ]);
    assert.equal(result.manifest.actions.every(({ proposal_revision }) => proposal_revision >= 1), true);
    assert.equal(result.manifest.actions[0].args.name, "Practice interview answers twice");
    assert.equal(result.manifest.actions[0].args.title, "Create Jordan's edited practice task.");
    assert.deepEqual(
      Object.fromEntries(
        result.manifest.actions.map(({ action, args }) => [action, args])
      ),
      {
        task_create: {
          name: "Practice interview answers twice",
          description: "Rehearse the two priority answers.",
          due_at: "2026-07-24T17:00:00Z",
          assignee_entity_id: "63000000-0000-4000-8000-000000000001",
          title: "Create Jordan's edited practice task."
        },
        log_touchpoint: {
          entity_id: "63000000-0000-4000-8000-000000000001",
          type: "meeting",
          occurred_at: "2026-07-22T17:00:00Z",
          notes: "Interview confidence practice plan",
          title: "Log the reviewed coaching touchpoint."
        },
        journey_advance: {
          entity_id: "63000000-0000-4000-8000-000000000001",
          pathway_slug: "interview-readiness",
          title: "Advance Jordan's readiness journey before the next check-in."
        },
        link_create: {
          url: "https://example.com/interview-practice",
          name: "Interview practice guide",
          description: "A short practice worksheet.",
          title: "Share the interview practice guide before Thursday."
        },
        follow_up_create: {
          name: "Check in after interview practice",
          description: "Ask what felt more confident after practice.",
          due_at: "2026-07-25T17:00:00Z",
          assignee_entity_id: "63000000-0000-4000-8000-000000000001",
          title: "Follow up with Jordan after the practice session."
        }
      }
    );
    assert.match(result.manifest.actions[0].destination, /^[0-9a-f-]{36}$/);
    assert.equal(result.manifest.actions[1].destination, undefined);
    assert.equal(result.manifest.actions[2].destination, undefined);
    assert.equal(result.manifest.actions[3].decision_id, "20000000-0000-4000-8000-000000000004");
    assert.equal(result.manifest.actions[3].undo_id, "40000000-0000-4000-8000-000000000004");
    assert.notEqual(result.manifest.actions[3].decision_id, result.manifest.actions[3].undo_id);
    assert.deepEqual(result.manifest.sources.map(({ kind }) => kind), [
      "source_bundle",
      "evidence_ref",
      "evidence_ref",
      "evidence_ref"
    ]);
    assert.deepEqual(result.manifest.sources[1].selector, { start_ms: 724000, end_ms: 768000 });
    assert.deepEqual(result.manifest.sources[2].selector, { start_offset: 0, end_offset: 48 });
    assert.deepEqual(result.manifest.sources[3].selector, {
      fields: ["name", "description", "starts_at", "ends_at"]
    });
  });

  it("resolves third-party AST evidence through the host evidence id, not the AST block id", () => {
    const hostEvidenceID = "70000000-0000-4000-8000-000000000099";
    const document = {
      type: "relaymark.document",
      version: 1,
      blocks: [
        {
          id: "b1",
          type: "relay.evidence_ref",
          props: {
            id: hostEvidenceID,
            source: "note:61000000-0000-4000-8000-000000000099",
            source_type: "note",
            source_revision: "revision-1",
            selector: {},
            scope: "private"
          },
          content: []
        },
        {
          id: "b2",
          type: "relay.action_row",
          props: {
            proposal_id: "follow-up-task",
            proposal_record_id: "10000000-0000-4000-8000-000000000099",
            proposal_revision: 1,
            action: "task_create",
            review: "ready",
            evidence: [hostEvidenceID],
            args: { name: "Follow up" }
          },
          evidence_refs: [hostEvidenceID],
          content: [{ type: "text", text: "Create a follow-up task." }]
        }
      ]
    };

    assert.deepEqual(validateDocument(document), []);
    assert.equal(projectManifest(document).sources[0].block_id, "b1");
    assert.equal(projectManifest(document).sources[0].evidence_id, hostEvidenceID);
  });

  it("rejects ambiguous document evidence and action lifecycle identities", () => {
    const evidence = (blockID, source) => ({
      id: blockID,
      type: "relay.evidence_ref",
      props: { id: "shared-evidence", source, selector: {} },
      content: []
    });
    const action = (blockID) => ({
      id: blockID,
      type: "relay.action_row",
      props: {
        proposal_id: "shared-proposal",
        proposal_record_id: "shared-record",
        proposal_revision: 1,
        action: "task_create",
        review: "undone",
        decision_id: "shared-decision",
        execution_id: "shared-execution",
        undo_id: "shared-undo",
        args: { name: "Follow up" }
      },
      content: []
    });
    const document = {
      type: "relaymark.document",
      version: 1,
      blocks: [evidence("b1", "note:one"), evidence("b2", "note:two"), action("b3"), action("b4")]
    };

    assert.deepEqual(
      validateDocument(document).map(({ code }) => code),
      [
        "relaymark.identity.duplicate_evidence",
        "relaymark.identity.duplicate_proposal",
        "relaymark.identity.duplicate_proposal_record",
        "relaymark.identity.duplicate_decision",
        "relaymark.identity.duplicate_execution",
        "relaymark.identity.duplicate_undo"
      ]
    );
  });

  it("requires actionable proposal records and never rebinds missing host evidence ids to AST ids", () => {
    const missingRecord = compileRelayMark(`@ActionRow(
  proposal_id: "generator-proposal",
  proposal_revision: 1,
  action: "task_create",
  review: "ready",
  args: {"name": "Follow up"}
) {
  Create the follow-up.
}`);

    assert.deepEqual(missingRecord.diagnostics.map(({ code }) => code), [
      "relaymark.action.proposal_record_id"
    ]);

    const reboundRecord = compileRelayMark(`@ActionRow(
  proposal_id: "same-identity",
  proposal_record_id: "same-identity",
  proposal_revision: 1,
  action: "task_create",
  review: "ready",
  args: {"name": "Follow up"}
) {
  Create the follow-up.
}`);

    assert.deepEqual(reboundRecord.diagnostics.map(({ code }) => code), [
      "relaymark.action.proposal_identity"
    ]);

    const invalidEvidenceDocument = {
      type: "relaymark.document",
      version: 1,
      blocks: [
        { id: "b1", type: "relay.source_bundle", props: { id: "" }, content: [] },
        { id: "b2", type: "relay.evidence_ref", props: { id: "", source: "" }, content: [] }
      ]
    };
    const projectedSources = projectManifest(invalidEvidenceDocument).sources;

    assert.deepEqual(validateDocument(invalidEvidenceDocument).map(({ code }) => code), [
      "relaymark.source_bundle.identity",
      "relaymark.evidence.identity"
    ]);
    assert.equal(projectedSources[0].source_id, "");
    assert.equal(projectedSources[1].evidence_id, "");
    assert.notEqual(projectedSources[0].source_id, "b1");
    assert.notEqual(projectedSources[1].evidence_id, "b2");
  });

  it("preserves manifest v1 action-title precedence while retaining canonical payload names", () => {
    const result = compileRelayMark(`@ActionRow(
  action: "task_create",
  review: "draft",
  args: {"name": "Canonical task name", "title": "Legacy payload title"}
) {
  Visible action row label
}`);

    assert.deepEqual(result.diagnostics, []);
    assert.equal(result.manifest.version, 1);
    assert.equal(result.manifest.actions[0].args.name, "Canonical task name");
    assert.equal(result.manifest.actions[0].args.title, "Visible action row label");
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

  it("rejects unresolved proposal evidence, zero revisions, and inconsistent action lifecycle ids", () => {
    const result = compileRelayMark(`@ActionRow(
  proposal_id: "proposal-ready",
  proposal_record_id: "record-ready",
  proposal_revision: 0,
  action: "task_create",
  review: "ready",
  decision_id: "decision-too-early",
  evidence: ["missing-evidence"]
) {
  This proposal has not been reviewed.
}

@ActionRow(
  proposal_id: "proposal-accepted",
  proposal_record_id: "record-accepted",
  proposal_revision: 1,
  action: "log_touchpoint",
  review: "accepted",
  decision_id: "decision-accepted"
) {
  This accepted proposal has no execution id.
}

@ActionRow(
  proposal_id: "proposal-undone",
  proposal_record_id: "record-undone",
  proposal_revision: 1,
  action: "link_create",
  review: "undone",
  decision_id: "decision-undone",
  execution_id: "execution-undone"
) {
  This undone proposal has no undo id.
}`);

    assert.deepEqual(
      result.diagnostics.map(({ code }) => code),
      [
        "relaymark.evidence.unresolved_reference",
        "relaymark.action.proposal_revision",
        "relaymark.action.lifecycle_state",
        "relaymark.action.lifecycle_state",
        "relaymark.action.lifecycle_state"
      ]
    );
  });

  it("requires an undone proposal to preserve the accept decision and use a distinct undo id", () => {
    const result = compileRelayMark(`@ActionRow(
  proposal_id: "proposal-undone",
  proposal_record_id: "record-undone",
  proposal_revision: 1,
  action: "link_create",
  review: "undone",
  decision_id: "same-id",
  execution_id: "execution-id",
  undo_id: "same-id"
) {
  Undo the accepted resource.
}`);

    assert.deepEqual(result.diagnostics.map(({ code }) => code), ["relaymark.action.lifecycle_state"]);

    const missingLifecycle = compileRelayMark(`@ActionRow(action: "link_create", review: "undone") {
  Undo without a durable accepted proposal.
}`);

    assert.deepEqual(missingLifecycle.diagnostics.map(({ code }) => code), ["relaymark.action.proposal_id"]);
  });

  it("enforces action lifecycle invariants in the manifest JSON Schema", () => {
    const schemaPath = resolve("spec/relaymark/schemas/relaymark-manifest.schema.json");
    const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
    const manifestFor = (action) => ({ type: "relaymark.manifest", version: 1, actions: [action] });
    const base = { block_id: "b1", action: "task_create", review: "ready" };
    const errorsFor = (action) => validateJSONSchema(manifestFor(action), schema, schemaPath);

    assert.deepEqual(errorsFor(base), []);
    assert.deepEqual(
      errorsFor({
        ...base,
        proposal_id: "proposal-1",
        proposal_record_id: "record-1",
        proposal_revision: 1
      }),
      []
    );
    assert.deepEqual(
      errorsFor({
        ...base,
        review: "undone",
        proposal_id: "proposal-1",
        proposal_record_id: "record-1",
        proposal_revision: 2,
        decision_id: "accept-decision",
        execution_id: "execution-1",
        undo_id: "undo-1"
      }),
      []
    );

    for (const invalid of [
      { ...base, proposal_id: "proposal-1", proposal_revision: 1 },
      { ...base, proposal_id: "proposal-1", proposal_record_id: "record-1", proposal_revision: 0 },
      {
        ...base,
        proposal_id: "proposal-1",
        proposal_record_id: "record-1",
        proposal_revision: 1,
        decision_id: "too-early"
      },
      {
        ...base,
        review: "accepted",
        proposal_id: "proposal-1",
        proposal_record_id: "record-1",
        proposal_revision: 1,
        decision_id: "accept-decision"
      },
      {
        ...base,
        review: "rejected",
        proposal_id: "proposal-1",
        proposal_record_id: "record-1",
        proposal_revision: 1,
        decision_id: "reject-decision",
        execution_id: "not-allowed"
      },
      {
        ...base,
        review: "undone",
        proposal_id: "proposal-1",
        proposal_record_id: "record-1",
        proposal_revision: 1,
        decision_id: "accept-decision",
        execution_id: "execution-1"
      },
      { ...base, review: "undone" }
    ]) {
      assert.notDeepEqual(errorsFor(invalid), []);
    }
  });

  it("enforces source-bundle and evidence identities in document and manifest JSON Schemas", () => {
    const documentSchemaPath = resolve("spec/relaymark/schemas/relaymark-document.schema.json");
    const documentSchema = JSON.parse(readFileSync(documentSchemaPath, "utf8"));
    const manifestSchemaPath = resolve("spec/relaymark/schemas/relaymark-manifest.schema.json");
    const manifestSchema = JSON.parse(readFileSync(manifestSchemaPath, "utf8"));
    const documentFor = (block) => ({ type: "relaymark.document", version: 1, blocks: [block] });
    const manifestFor = (source) => ({ type: "relaymark.manifest", version: 1, sources: [source] });

    assert.deepEqual(
      validateJSONSchema(
        documentFor({
          id: "b1",
          type: "relay.evidence_ref",
          props: { id: "evidence-1", source: "note:1" }
        }),
        documentSchema,
        documentSchemaPath
      ),
      []
    );
    assert.deepEqual(
      validateJSONSchema(
        manifestFor({
          block_id: "b1",
          kind: "evidence_ref",
          evidence_id: "evidence-1",
          source_id: "note:1"
        }),
        manifestSchema,
        manifestSchemaPath
      ),
      []
    );

    for (const invalidDocument of [
      documentFor({ id: "b1", type: "relay.source_bundle", props: { id: "" } }),
      documentFor({ id: "b1", type: "relay.evidence_ref", props: { id: "evidence-1" } })
    ]) {
      assert.notDeepEqual(validateJSONSchema(invalidDocument, documentSchema, documentSchemaPath), []);
    }

    for (const invalidManifest of [
      manifestFor({ block_id: "b1", kind: "source_bundle" }),
      manifestFor({ block_id: "b1", kind: "source_bundle", source_id: "" }),
      manifestFor({ block_id: "b1", kind: "evidence_ref" }),
      manifestFor({ block_id: "b1", kind: "evidence_ref", evidence_id: "evidence-1" })
    ]) {
      assert.notDeepEqual(validateJSONSchema(invalidManifest, manifestSchema, manifestSchemaPath), []);
    }
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
