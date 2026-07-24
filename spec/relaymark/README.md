# RelayMark Specification

RelayMark is Relay's Markdown-compatible document format for human prose plus
validated, declarative Relay Kit blocks.

This directory is the portable spec package. It is designed to move into a
standalone repository later without depending on the Phoenix application.

## Status

- Spec version: `0.4.0-draft`
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
    relay.evidence_ref.json
    relay.file_ref.json
    relay.form_question.json
    relay.note_ref.json
    relay.source_bundle.json
    relay.transcript_segment.json
    relay.url_ref.json
  examples/
    agent-paper-review.relaymark
    agent-paper-review.ast.json
    agent-paper-review.manifest.json
    invalid-identity-collisions.relaymark
    invalid-identity-collisions.ast.json
    invalid-identity-collisions.diagnostics.json
    mentor-meeting.relaymark
    mentor-meeting.ast.json
    mentor-meeting.manifest.json
    product-research.relaymark
    product-research.ast.json
    product-research.manifest.json
    scripture-ask-answered.ast.json
    scripture-ask-answered.manifest.json
    scripture-ask-refused.ast.json
    scripture-ask-refused.manifest.json
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

### Evidence identity

`relay.source_bundle` groups the exact evidence used for one generated or human
claim. Its `id` MUST remain stable for the logical bundle. When bundle
membership, source revisions, or selectors change, hosts SHOULD increment
`revision`; hosts MAY also stamp `source_hash` with a digest of that exact input
set.

`relay.evidence_ref` is the portable citation target for evidence from any
host-readable source. Its `id` MUST be stable across regeneration. `source`
identifies the host source, `source_revision` pins an immutable revision when
available, and `selector` locates the relevant time range, text range, field,
page region, or other source-specific span. `source_type` and `selector` remain
open and host-validated so the contract does not hard-code one product or media
kind. Source-bundle and evidence ids live in directive properties and manifest
source fields; they MUST NOT replace the schema-safe RelayMark AST `block.id`.

`evidence_refs` MUST contain an AST block id, resource id, source-bundle
property id, or evidence-ref property id from the same resolved document
context. Durable citations to `relay.evidence_ref` use its host `props.id`, not
its AST `block.id`. A runtime MUST report non-empty unresolved references
rather than silently dropping or rebinding them. If evidence is deleted or
becomes unreadable, hosts MUST degrade the citation or invalidate the
derivative instead of pointing the existing id at different content.
AST block ids, resource ids, source-bundle property ids, and evidence-ref
property ids share one document evidence namespace and MUST NOT collide across
different targets. A runtime MAY preserve a legacy v1 source node whose host id
equals that same node's AST block id, but conforming compilers MUST allocate the
two identities separately.

#### Scripture evidence profile

A resource with `type: "scripture"` and
`props.profile: "relaymark.scripture_release.v1"` identifies one immutable,
publishable Scripture release. Its properties MUST include canonical
translation lineage, concrete edition, corpus release, versification, source
digest, license, attribution, and provenance digests for both the coordinate
inventory and normalized index input. Development hashes and app-local
collection ids are not portable corpus identities.

A `relay.evidence_ref` with `source_type: "scripture"` MUST resolve `source` to
exactly one Scripture resource in the document. Its `source_revision` MUST equal
that resource's `corpus_release_id`, and its scope MUST NOT be broader than the
resource scope. The evidence excerpt MUST contain the exact selected source
text; `selector.content_digest` binds that text to the immutable release.

The selector profile is `relaymark.scripture_span.v1`. Both `start` and `end`
are required, including for a singleton. Each coordinate has a canonical
`book_id`, a non-empty string `verse_label`, and exactly one location shape:

- `coordinate_kind: "chapter"` with a positive integer `chapter`; or
- `coordinate_kind: "section"` with a stable non-empty `section_id`.

Version 1 spans remain within one book and one coordinate kind. Runtimes MUST
preserve suffixed and named verse labels losslessly and MUST NOT infer ordering
by comparing label strings. A host validates ordering against the release's
authoritative coordinate inventory. `display_label` is optional presentation
text and never contributes to evidence identity.

### Agent answer profile

`frontmatter.profile: "relaymark.agent_answer.v1"` identifies a bounded,
evidence-backed answer paper rather than a chat transcript. The profile uses
existing headings, paragraphs, `relay.claim`, `relay.source_bundle`, and
`relay.evidence_ref` nodes; it does not define a new directive or manifest
version.

The frontmatter MUST contain:

- `title` and a canonical Relay `scope`;
- `question`, preserving the exact reader-submitted text;
- `question_id`, equal to `sha256:` followed by the lowercase SHA-256 hex
  digest of the exact `question` UTF-8 bytes, without trimming, Unicode
  normalization, case folding, or whitespace rewriting; and
- `outcome`, with exactly one of `answered` or `refused`.

`question_id` is content identity. It MUST NOT contain or substitute for a
request id, session id, organization id, credential, or authorization proof.

An `answered` paper MUST contain, in order:

1. one level-one answer heading;
2. one or more non-empty `relay.claim` blocks with `status: "supported"`;
3. one level-two heading whose plain text is `Evidence`; and
4. one or more `relay.source_bundle` blocks containing the concrete
   `relay.evidence_ref` blocks used by the claims.

Every answered claim MUST have a non-empty stable `key` and one or more unique
evidence references. Each reference MUST resolve exactly once to the `props.id`
of a concrete `relay.evidence_ref` in the paper. The host owns source
projection and MUST construct evidence blocks from the retrieved immutable
sources; a model MAY select only evidence ids from that retrieved set. An
optional claim confidence MUST be finite and between `0.0` and `1.0`.

For a Scripture Ask surface, every evidence ref used by an answer claim MUST
satisfy the Scripture release and span profiles above. A successful answer
MUST NOT contain `relay.agent_suggestion`, `relay.action_row`, or manifest
actions. Read-only answers do not imply proposed or authorized mutations.

A `refused` paper MUST additionally contain
`refusal_reason: "insufficient_evidence"` and MUST contain, in order, one
level-one heading with plain text `Answer unavailable` and one non-empty
reader-facing explanation paragraph. Version 1 refusals contain no claims,
source bundles, evidence refs, resources, agent suggestions, action rows, or
manifest actions. Refusal prose MUST NOT be interpreted as an answer claim.

The outcome profile remains in the canonical AST frontmatter. Manifest version
1 intentionally continues to project normalized claims and sources without
duplicating the profile or outcome. Hosts MUST validate the AST and manifest
together, reject any mismatch, and bind the exact transported document and
manifest JSON bytes with separate host-envelope digests. Those digests and
transport request ids are not RelayMark document fields.

### Action proposal identity

`relay.action_row.action` is an open, server-owned action id. The host validates
`args` against the action catalog before execution; RelayMark does not maintain
a closed list of task, touchpoint, journey, resource, follow-up, or future
action types.

Durable review flows SHOULD provide `proposal_id`, `proposal_record_id`, and
`proposal_revision`. `proposal_id` is the stable generator/client identity.
`proposal_record_id` is the distinct host record address supplied to authorized
review and undo actions; possessing it grants no authority by itself. Editing
keeps both ids stable and increments the positive, one-indexed
`proposal_revision`, allowing hosts to reject stale review commands. These host
identifiers are stored in directive properties and manifest fields; they MUST
NOT replace the schema-safe RelayMark AST `block.id`. Legacy action rows without
these fields remain valid but do not provide a durable cross-revision proposal
identity or an actionable review address.

Relay Phase 3 adapters map the generation read model's database `id` to
`proposal_record_id` and its generator/client `proposal_id` to RelayMark
`proposal_id`. The native review action currently names its record-address
argument `proposal_id`; callers pass `proposal_record_id` there and the server
still performs current-session authorization on every mutation.

Host-produced lifecycle snapshots use these optional identifiers:

- `decision_id` identifies the durable accept or reject decision.
- `execution_id` identifies the accepted action execution.
- `undo_id` identifies the durable undo operation.

Each proposal, proposal-record, decision, execution, and undo id MUST be unique
within its corresponding document namespace.

An accepted lifecycle-aware proposal requires `decision_id` and `execution_id`.
A rejected proposal requires `decision_id` and has no execution or undo id. An
undone proposal retains the original acceptance `decision_id` and
`execution_id`, and adds a distinct `undo_id`. RelayMark MUST NOT contain
bearer credentials, executable closures, or opaque authorization/undo tokens;
clients resolve executable undo metadata through the authorized host action
contract.

Manifest version 1 preserves its original action-title projection: the action
row's plain-text content is written to `args.title` after directive `args` are
copied, so it wins if both provide `title`. Hosts should use their canonical
payload field (for example Relay Phase 3 uses `name` for task, follow-up, and
resource proposals) instead of relying on `args.title` to override the row
label. Changing this precedence requires a future manifest version.

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
3. `semantic`: action ids, proposal ids, entity refs, and evidence/source refs
   resolve or become draft review issues.
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
