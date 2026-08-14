# RelayMark

> **Historical design record.** This document captures the initial standalone
> RelayMark proposal and several open questions that have since been decided.
> Current normative direction lives in the
> [RelayMark specification](../../spec/relaymark/README.md) and
> [ADR 0001](../adr/0001-safe-agent-paper-composition-profile.md): RelayMark is
> the safe portable composition language for malleable Agent Papers, host
> bindings never contain resolved private values, and paper layers compose
> already-authorized contributions linearly.

RelayMark is Relay's Markdown-compatible authoring format for notes,
transcripts, forms, long reading, and agent-generated document structure.

It sits below Agent Paper. Agent Paper is the product interaction model: the
note is a command surface. RelayMark is the portable document grammar that lets
humans, agents, LiveView, Swift, MCP, email, and future standalone tools share
the same typed content model.

## Recommendation

Start fresh with a small Relay-owned spec and reference implementation. Do not
fork Markdoc.

Markdoc is the right inspiration: Markdown prose, declarative tags, validation,
AST transforms, and multiple renderers. Swift-DocC is the right second
inspiration: directives, diagnostics, resource catalogs, a compiler boundary,
and generated render JSON. RelayMark should borrow those ideas without inheriting
a documentation-site runtime, React assumptions, or Swift-symbol semantics.

Use Markdoc as a research dependency or prototype parser if it saves time, but
keep RelayMark's schema, AST, validators, action semantics, and renderer
contracts owned by Relay. The eventual standalone repo should be able to ship
reference runtimes for Elixir, TypeScript, and Swift from the same versioned
spec.

Starting fresh does not mean hand-writing every parser primitive. RelayMark
should still use mature CommonMark/tokenizer libraries where they fit. The
important decision is that Relay owns the document contract, directives,
diagnostics, projection rules, and action semantics.

## Why Not Fork Markdoc

Markdoc is MIT-licensed and well aligned philosophically, but a fork would start
RelayMark from the wrong center of gravity:

- Markdoc is optimized for documentation and publishing sites; RelayMark is for
  live relational notes, forms, transcripts, evidence, and reviewed actions.
- Markdoc's strongest renderer path is React; Relay needs LiveView, Swift, MCP,
  email, plain text, and future local clients as first-class targets.
- Markdoc custom tags can express interactive content, but Relay needs
  permission-aware action proposals tied to `Relay.Action.Registry`.
- Forking inherits upstream parser/runtime maintenance without guaranteeing the
  schema, diagnostics, or AST shape Relay needs.
- A fresh spec lets TypeScript, Swift, and Elixir implementations share fixtures
  and JSON Schema without treating one runtime as the source of truth.

The best use of Markdoc is as a comparison point and possible implementation
ingredient, not as the canonical project boundary.

## Design Goals

- Preserve CommonMark prose as the default authoring experience.
- Add a small set of typed declarative directives for Relay Kit primitives.
- Make every agent-created block validate against host-owned schemas.
- Keep arbitrary JavaScript, JSX, CSS, and hidden runtime behavior out of
  user-authored relational notes.
- Compile source text into a stable, versioned AST that renderers and agents can
  inspect.
- Support browser editing, native editing, MCP output, email export, HTML
  publishing, plain-text search, and long-form reading from the same model.
- Attach suggestions, comments, source references, and private annotations to
  stable block anchors instead of rewriting the whole document.
- Materialize tasks, mentions, form fields, source evidence, and action
  proposals through normal Relay primitives and `Relay.Action.Registry`.

## Non-Goals

- RelayMark is not MDX and must not host arbitrary JSX.
- RelayMark is not a general web component runtime.
- RelayMark is not a chat protocol.
- RelayMark is not the whole Agent Paper product surface.
- RelayMark is not a replacement for HTML, EPUB, XML, or A2UI-style UI payloads;
  it is the canonical authoring and document interchange layer from which those
  projections can be produced.

## Relationship To Existing Concepts

| Concept | Role |
| --- | --- |
| Agent Paper | Product interaction model for notes, capture, and inline reviewed action |
| RelayMark | Markdown-compatible source format and canonical document AST |
| Relay Kit | Renderer catalog for semantic blocks such as Action Row and Source Bundle |
| A2UI-style payloads | Declarative UI messages for agent-generated surfaces outside documents |
| Markdoc | Inspiration for declarative Markdown, validation, transforms, and renderers |
| Swift-DocC | Inspiration for directives, resource catalogs, diagnostics, and render JSON |
| Tiptap/ProseMirror | Possible rich editor adapter, not the source of truth |
| HTML | Render/export target |
| XML/EPUB | Long-form or archival export targets |

## Syntax Direction

RelayMark source should stay readable as Markdown. The extension surface should
be a directive grammar with named blocks and JSON-like attributes.

Prefer DocC-style directives for Relay-owned blocks:

```relaymark
# Mentoring session

Marcus sounded nervous about Thursday's interview.

@ActionRow(
  action: "relay.task.create",
  target: "entity:marcus",
  visibility: "private",
  review: "draft"
) {
  Send interview prep resources before Thursday.
}

@SourceBundle(id: "src-interview-anxiety") {
  @TranscriptRange(start: "00:12:04", end: "00:12:48")
  @NoteRef(block: "paragraph-2")
}
```

This is intentionally close to DocC for humans, while the processing pipeline is
closer to Markdoc:

```text
RelayMark source
  -> parse
  -> validate
  -> normalize
  -> compile to RelayMark AST
  -> render or project
```

Unknown directives should fail validation in trusted document contexts. They may
be preserved as inert source text in import tools or draft recovery flows.

## Core Document Model

The canonical model is a versioned AST, not Markdown or HTML.

```json
{
  "type": "relaymark.document",
  "version": 1,
  "frontmatter": {
    "title": "Marcus interview prep",
    "scope": "private"
  },
  "blocks": [
    {
      "id": "b1",
      "type": "paragraph",
      "content": [
        {"type": "text", "text": "Marcus sounded nervous about Thursday's interview."}
      ]
    },
    {
      "id": "b2",
      "type": "relay.action_row",
      "props": {
        "action": "relay.task.create",
        "target": "entity:marcus",
        "visibility": "private",
        "review": "draft"
      },
      "content": [
        {"type": "text", "text": "Send interview prep resources before Thursday."}
      ],
      "evidence_refs": ["b1"]
    }
  ],
  "annotations": [],
  "resources": []
}
```

Required model properties:

- Every block has a stable `id`.
- Every semantic Relay block has a namespaced `type`.
- Inline content is represented as spans and inline atoms, not HTML strings.
- Annotations live beside content and attach through anchors.
- Source references are first-class records with scope and provenance.
- Accepted actions materialize through Relay actions, not by mutating hidden
  document JSON.

## Block Families

### Common Prose Blocks

- `paragraph`
- `heading`
- `list`
- `quote`
- `code`
- `table`
- `image`
- `horizontal_rule`

These should remain close to CommonMark.

### Relay Kit Blocks

- `relay.entity_chip`
- `relay.action_row`
- `relay.agent_suggestion`
- `relay.source_bundle`
- `relay.evidence_trail`
- `relay.scoped_share`
- `relay.match_suggestion`
- `relay.form_question`
- `relay.form_response_summary`
- `relay.transcript_segment`
- `relay.moment_row`
- `relay.situation_header`
- `relay.action_review`

Agents may create only approved Relay Kit blocks. Each block must have an
explicit schema, validation rules, renderer mapping, and privacy behavior.

`relay.agent_suggestion` may appear as a visible review block when the suggestion
belongs in the reading flow. Anchored suggestions that should behave like
comments can use the same schema as sidecar annotations instead.

### Sandboxed Widget Blocks

Use sandboxed widgets only when Relay Kit declarations are not enough:

```relaymark
@Widget(kind: "chart", sandbox: true, source: "query:weekly-care-actions") {
  Weekly care actions by leader.
}
```

Widget blocks must point to host-owned data or a validated payload. They must not
carry arbitrary executable code.

## Inline References

Inline references should prefer normal Markdown syntax where possible:

```relaymark
[Marcus](relay:entity/ent_123) needs help before [Thursday](relay:event/evt_456).
```

Editors can render these as chips. Exporters can degrade them to plain links or
text. The AST should normalize them into inline atoms:

```json
{"type": "relay.entity_ref", "id": "ent_123", "label": "Marcus"}
```

## Annotations And Anchors

Annotations are separate from the document body:

- comment
- private mentor note
- highlight
- agent suggestion
- redaction
- source grounding
- review decision

Anchors should include a stable block id plus a text range when needed:

```json
{
  "id": "ann_1",
  "type": "agent_suggestion",
  "anchor": {
    "block_id": "b1",
    "start": 0,
    "end": 64,
    "quote": "Marcus sounded nervous about Thursday's interview."
  },
  "props": {
    "confidence": 0.82,
    "review": "draft"
  }
}
```

The quote fallback helps recover anchors after edits.

## Validation

Validation should happen before rendering and before any mutation proposal is
eligible for review.

Validation layers:

1. Syntax: balanced directives, valid attributes, supported literals.
2. Schema: allowed blocks, required props, allowed children.
3. Relay semantics: action IDs exist, entity references resolve or become draft
   resolution tasks, visibility is allowed, evidence refs point to known blocks.
4. Policy: sensitive blocks require source evidence, scoped shares require
   explicit audience, mutations require review state.
5. Renderer support: target surface can render or degrade each block.

Diagnostics should be structured, DocC-style records:

```json
{
  "level": "error",
  "code": "relaymark.action.unknown",
  "message": "Unknown Relay action 'relay.task.creat'.",
  "location": {"line": 8, "column": 11},
  "suggestion": "Did you mean 'relay.task.create'?"
}
```

## Render And Projection Targets

RelayMark should produce multiple outputs from one AST.

| Target | Purpose |
| --- | --- |
| Relay Kit render spec | LiveView, Swift, MCP, and command output |
| HTML | Read-only web, publishing, email-like export |
| Markdown | Human-readable export and fallback editing |
| Plain text | Search, embedding, summaries, notifications |
| Action manifest | Reviewable mutations through `Relay.Action.Registry` |
| Mention manifest | Entity refs, unresolved refs, backlinks |
| Form manifest | Questions, validations, response shape |
| Source manifest | Transcript ranges, files, URLs, citations, permissions |
| XML/EPUB | Long-form reading and archival export |

Renderers must be deterministic and side-effect free. Actions are proposed as
data, reviewed by users, and then executed by Relay actions.

## Package Boundary

RelayMark now lives in a standalone repo. The repository owns the portable spec,
reference runtime, and conformance suite:

```text
spec/relaymark/
  README.md
  schemas/
    relaymark-document.schema.json
    relaymark-conformance-suite.schema.json
    relaymark-diagnostic.schema.json
    relaymark-directive.schema.json
    relaymark-manifest.schema.json
  directives/
    relay.action_row.json
    relay.agent_suggestion.json
    relay.file_ref.json
    relay.form_question.json
    relay.note_ref.json
    relay.source_bundle.json
    relay.transcript_segment.json
    relay.url_ref.json
  examples/
    mentor-meeting.relaymark
    mentor-meeting.ast.json
    mentor-meeting.manifest.json
  conformance/
    suite.json
```

The portable package lives in `spec/relaymark/`. Its role is to make the spec
executable before any client integration is built: directive registry entries
define what agents may create, JSON Schemas define the AST/diagnostic/manifest
shape, and conformance fixtures define what independent runtimes must produce.

The reference runtime lives under `src/` with a CLI wrapper in `bin/`. Relay,
Swift, and TypeScript clients should consume the spec and runtime outputs rather
than redefining the document contract in app code.

## Relay Integration

The current document system stores Markdown source, cached HTML, frontmatter,
task counts, and Yjs state in `document_contents`. RelayMark should evolve this
without breaking existing notes.

Recommended migration path:

1. Keep `document_contents.body` as the editable source string.
2. Add a format/version concept before relying on RelayMark-only syntax.
3. Cache a normalized RelayMark AST once parsing is stable.
4. Materialize queryable projections into existing Relay primitives:
   mentions, tasks, form questions, source evidence, and action proposals.
5. Keep `body_html` as a derived projection, not canonical content.
6. Let Yjs carry the editing state, but periodically compile source to AST for
   validation, search, rendering, and action review.

First-class integrations:

- `Relay.Action.Registry` validates action IDs and arguments for Action Rows.
- `Relay Kit` maps block types to renderers on LiveView, Swift, MCP, and email.
- `Relay.Documents` owns persistence and migration from Markdown documents.
- `Relay.Forms` reads `relay.form_question` and form response summaries.
- `Relay.Sync.DocumentCRDT` continues handling collaborative source editing.
- Entity resolution and mention extraction run as projections from the AST.

## Agent Rules

Agents may generate RelayMark, but the host stays in control.

Allowed:

- Create draft Relay Kit blocks.
- Attach suggestions to anchors.
- Propose actions with evidence and confidence.
- Produce source bundles from known sources.
- Mark unresolved entities for human review.

Not allowed:

- Execute actions by writing a block.
- Invent new block types in user documents.
- Embed arbitrary JS, CSS, JSX, iframe HTML, or fetch behavior.
- Hide sensitive sharing changes inside prose edits.
- Rewrite large document sections when a local annotation or block proposal is
  enough.

## Example: Mentor Meeting Note

```relaymark
---
title: Marcus interview prep
scope: private
---

# Marcus interview prep

Marcus sounded nervous about Thursday's interview.

@SourceBundle(id: "src-1") {
  @TranscriptRange(start: "00:12:04", end: "00:12:48")
}

@AgentSuggestion(confidence: 0.82, evidence: ["src-1"]) {
  This sounds like a readiness/support moment, not just a scheduling note.
}

@ActionRow(
  action: "relay.task.create",
  target: "entity:marcus",
  destination: "mentor-follow-up",
  visibility: "private",
  review: "draft",
  evidence: ["src-1"]
) {
  Send interview prep resources before Thursday.
}
```

## Open Questions

- Should the source directive grammar use DocC-style `@Directive` syntax, or
  should the first standalone version stay closer to Markdoc's `{% tag %}`
  syntax for ecosystem familiarity?
- Should inline entity references standardize first on `relay:` Markdown links,
  wiki-links, or an inline directive?
- Should comments and agent suggestions live entirely as AST annotations, or
  should source text support visible comment directives for portable exports?
- Which block family should be implemented first: action rows/source bundles, or
  form questions/transcript segments, when UI integration begins?
- Should `body_html` remain a stored cache long term, or move to a render cache
  keyed by document revision and target renderer?

## First Implementation Slice

The first slice should prove the contract without changing the whole document
system:

1. Define the `relay.action_row`, `relay.source_bundle`, `relay.agent_suggestion`,
   `relay.form_question`, and `relay.transcript_segment` directive schemas.
2. Build a parser/validator that accepts CommonMark plus those directives.
3. Compile to RelayMark AST with stable block IDs.
4. Render a safe HTML projection and a Relay Kit render spec projection.
5. Generate action, mention, form, and source manifests from the same AST.
6. Add fixtures that can later become standalone conformance tests.

Success means the same `.relaymark` fixture can be parsed, validated, rendered
to HTML, projected into Relay Kit blocks, and inspected by an agent without
executing code.

## References

- [Markdoc overview](https://markdoc.dev/docs/overview)
- [Markdoc syntax](https://markdoc.dev/docs/syntax)
- [Markdoc validation](https://markdoc.dev/docs/validation)
- [Swift-DocC overview](https://www.swift.org/documentation/docc/)
- [Swift-DocC tutorial syntax](https://www.swift.org/documentation/docc/tutorial-syntax)
- [Swift-DocC Render](https://github.com/swiftlang/swift-docc-render)
