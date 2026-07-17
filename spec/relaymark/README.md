# RelayMark Specification

RelayMark is Relay's Markdown-compatible document format for human prose plus
validated, declarative Relay Kit blocks.

This directory is the portable spec package. It is designed to move into a
standalone repository later without depending on the Phoenix application.

## Status

- Spec version: `0.2.0-draft`
- Stability: draft
- Compatibility target: CommonMark prose plus RelayMark directives
- Canonical interchange model: RelayMark AST JSON

## What Makes The Spec Complete

A prose design document is not enough for independent implementations. A usable
standalone spec needs five artifacts:

1. Normative rules: what source syntax, AST shapes, directives, validation, and
   projections mean.
2. Machine-readable schemas: JSON Schemas for documents, directives,
   diagnostics, and manifests.
3. Directive registry: one definition per approved Relay Kit directive.
4. Fixtures: source examples with expected AST and manifest outputs.
5. Conformance metadata: a fixture index that every runtime can execute.

This directory starts that package. The Elixir, TypeScript, and Swift runtimes
should consume these files instead of redefining the contract in code.

## Processing Model

```text
RelayMark source
  -> parse CommonMark prose and RelayMark directives
  -> validate syntax
  -> validate directive schemas
  -> validate Relay semantics against host registries
  -> compile to RelayMark AST
  -> project manifests and render targets
```

Renderers and projections must be deterministic and side-effect free. Writing an
`@ActionRow` creates a draft action proposal in the AST; it does not execute the
action.

## Directory Layout

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
    relay.claim.json
    relay.comparison.json
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
    product-research.relaymark
    product-research.ast.json
    product-research.manifest.json
  conformance/
    suite.json
```

## Normative Terms

- `MUST` marks required behavior for conforming implementations.
- `SHOULD` marks expected behavior with room for documented exceptions.
- `MAY` marks optional behavior.

## Source Syntax

RelayMark source is CommonMark plus directives. The draft source directive
syntax follows a DocC-like shape:

```relaymark
@DirectiveName(attribute: "value") {
  Markdown content
}
```

Attributes MUST be JSON-serializable scalar, array, or object values. Attribute
names SHOULD use lower snake case. Directive names in source use PascalCase;
compiled AST types use lowercase, namespaced identifiers such as
`relay.action_row`.

Visibility and scope attributes that map to Relay publishing MUST use Relay's
canonical `private`, `org`, `unlisted`, or `public` values. Renderers and host
apps MUST NOT translate these into product-specific sharing states.

Unknown directives MUST fail validation in trusted document contexts. Import and
recovery tools MAY preserve them as inert source text.

## Canonical AST

The canonical interchange format is a versioned JSON AST validated by
`schemas/relaymark-document.schema.json`. Markdown and HTML are not canonical.

Every block MUST have a stable `id`. Every Relay semantic block MUST have a
namespaced `type`. Implementations MAY generate ids during compilation, but a
runtime that round-trips a document SHOULD preserve existing ids when source
contains or maps to them.

Inline Relay references such as `relay.entity_ref` and `relay.product_ref` MAY
also have an `id`. Implementations MUST discriminate block and inline nodes by
their registered `type`, not by the presence of `id`. The portable block
registry reserves `relay.file_ref`, `relay.note_ref`, and `relay.url_ref` as
source directives even though their names end in `_ref`; other
`relay.*_ref` nodes are inline unless a trusted extension registry declares
them as blocks.

## Directive Registry

Each directive in `directives/` defines:

- source directive name
- AST type
- attributes
- allowed children
- validation requirements
- projection targets
- privacy and review behavior

Agents MUST only create directives from this registry unless the host provides a
separate trusted extension registry.

## Validation Levels

1. `syntax`: source parses and directives are balanced.
2. `schema`: AST and directive attributes match JSON Schemas.
3. `semantic`: action ids, entity refs, and source refs resolve or become draft
   review issues.
4. `policy`: sensitive changes require review, evidence, and audience scope.
5. `projection`: the requested target can render or degrade every block.

Diagnostics MUST follow `schemas/relaymark-diagnostic.schema.json`.

## Projections

Conforming runtimes SHOULD support at least these projections:

- `html`: safe read-only HTML.
- `plain_text`: text for search, embeddings, notifications, and summaries.
- `relay_kit`: semantic render spec for Relay clients.
- `manifest`: action, mention, inline reference, form, source, claim, and
  comparison projection data.

Runtimes MAY add `markdown`, `xml`, `epub`, `mcp`, or client-specific render
targets as long as they do not change the AST contract.

## Versioning

RelayMark uses semantic-ish spec versions:

- Patch versions fix wording, examples, diagnostics, or schemas without changing
  valid AST meaning.
- Minor versions add optional fields, directives, projection targets, or
  validation codes.
- Major versions may change directive syntax, AST semantics, or required fields.

Every AST document MUST include `version`. Draft AST version `1` maps to spec
`0.x` until the first stable release.

## Conformance

`conformance/suite.json` lists fixture inputs and expected outputs. A runtime is
conforming for a feature when it can parse every matching fixture, validate the
expected output schemas, and produce equivalent AST and manifest JSON.

Conformance equality should ignore object key order. It should not ignore
missing ids, missing diagnostics, changed action ids, or changed source refs.
