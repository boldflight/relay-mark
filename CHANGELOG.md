# RelayMark Git and Swift release notes

## Unreleased

- Removes the Swift collaboration proof machinery under Relay's standard
  collaboration plan: the JavaScriptCore Yjs replica
  (`RelayMarkCollaborationDocument` and `yjs-runtime.js`), the content-edit
  witness, owned-history groups and archives, identity/text-item capture,
  reviewed-recovery import and the source-reference codec calls.
  `RelayMarkLocalTransaction` now carries only its id, update and input intent.
  `RelayMarkNativeDocument` keeps a plain Yrs `UndoManager` for its own origin,
  with `editorCommand(separateUndoItem:)` grouping a typing burst into one undo
  item, and garbage-collects deleted content. `RelayMarkRelativeRange` replaces
  the replica's relative range type.

- Repairs canonical browser history restoration after Yrs sorts mark attribute
  keys, reconstructing the known producer encoding against the unchanged
  original archive hash. The detached repair preserves selective Undo/Redo and
  rejects unsupported legacy shapes and corrupted content or identity.

- Preserves insertion-time empty callout source in retained revisions by creating
  one deterministic empty body paragraph across JavaScript, Elixir and Swift.
  Existing callout appearance/title and strict AST/XML validation remain intact.

- Normalizes valid empty and nonparagraph-first CommonMark list items into the
  existing paragraph-first editor grammar without dropping source blocks or
  changing their IDs; preserves marked text surrounding hard breaks.
- Adds shared JavaScript/Elixir source-compatibility fixtures. Canonical contract
  1 and the Swift document model remain unchanged.

- Clarifies the cross-platform boundary: Agent Paper is the editable RelayMark
  document surface, while entity/page chrome and collection engines belong to
  hosts.
- Defines transient decision and confirmation controls as non-authored runtime
  UI until a portable directive is standardized.

## 0.6.0

- Adds a generic Swift `AttributedString` authoring bridge for readable
  RelayMark prose and canonical `relay:` entity links without moving host UI,
  entity resolution, or authorization into the portable adapter.
- Implements the portable `0.6.0-draft` contract while preserving valid
  pre-1.0 document meaning and public Swift adapter source compatibility.
- Advances the portable contract to `0.6.0-draft` with additive Agent Paper
  entity-reference, property-sheet, bound-data-view, and layout directives.
- Adds registry-owned renderer capability negotiation with deterministic
  fallbacks and canonical source serialization for the supported authoring
  subset.
- Adds portable semantic layer roles, anchors, placement, and missing-anchor
  fallbacks over already-authorized contributions, without ACLs or private
  resolved values.
- Adds shared Task, Person, Collection, and layered Meeting conformance
  fixtures plus matching generic Swift and Elixir value models.

- Makes the portable conformance-suite version the cross-runtime compatibility
  identity while allowing Git/Swift and Hex adapter releases to version and
  ship independently.
- Removes the private npm version and redundant nested Swift manifest so
  distribution versions have one owner per ecosystem.
- Adds a shared contract-version check and cross-runtime CI for the reference
  runtime, Swift adapter, and Elixir adapter.

## 0.5.3

- Lowers both Swift package manifests to iOS, macOS, and visionOS 26.5 so
  Xcode 26.5/Xcode Cloud consumers can import `RelayMarkSwift`.
- Leaves the portable RelayMark contract, schemas, fixtures, and Elixir
  implementation unchanged. The Git/Swift and Hex versions happened to
  coincide for this release; that is not a lockstep versioning requirement.

## 0.5.2

- Bundles the canonical projection-manifest schema alongside the document and
  diagnostic schemas.
- Adds `RelayMark.validate_manifest/1` so host applications can validate
  manifests without reaching into package filesystem internals.

## 0.5.1

- Publishes the generic Elixir adapter as the `relay_mark_elixir` Hex package.
- Bundles the canonical document and diagnostic schemas plus directive registry
  required to compile and validate documents without a repository checkout.
- Verifies packaged schema and directive bytes against the canonical
  `spec/relaymark/` sources before release.
- Adds Hex package metadata, generated documentation, and package-consumer
  verification while leaving the portable `0.5.0-draft` contract unchanged.

## 0.5.0

- Adds the normative `relaymark.agent_answer.v1` profile for bounded answered
  and insufficient-evidence papers with exact question identity.
- Adds canonical answered and refused Scripture Ask AST/manifest fixtures to the
  shared conformance suite.
- Enforces the profile's outcome, structure, evidence, and read-only boundaries
  with portable diagnostics in the reference runtime and both generic adapters.
- Adds reusable transported AST/manifest pair validation that rejects canonical
  projection, action, and answer-content drift.
- Adds a machine-readable SHA-256 receipt asserted by JavaScript, Swift, and
  Elixir against the same exact answered and refused fixture bytes.
- Makes Scripture Ask validation an explicit host action-context policy rather
  than document-inferred state.
- Makes every transported-pair gate run the canonical document shape and full
  directive semantics before projection, including nested Relay blocks.
- Rejects malformed UTF-8, non-scalar strings, and non-portable JSON before
  binding exact-byte digests; valid escaped non-BMP scalars round-trip across
  JavaScript, Swift, and Elixir.

Existing AST and manifest documents remain version 1. The profile uses existing
headings, paragraphs, claims, source bundles, evidence references, resources,
and manifest projections.

## 0.4.1

- Keeps the canonical Elixir JSON Schema 2020-12 validator compatible with
  host applications using Decimal 3.
- Preserves the RelayMark document-validation API and portable diagnostics.

## 0.4.0

- Adds the portable `relaymark.scripture_release.v1` resource profile.
- Adds lossless `relaymark.scripture_span.v1` evidence selectors with
  chapter-or-section coordinates and string verse labels.
- Projects immutable Scripture release identity and provenance through existing
  `relay.evidence_ref` manifest sources.
- Adds matching Swift and Elixir typed adapters plus one shared AST/manifest
  conformance fixture.

Existing AST and manifest documents remain version 1. Existing generic resources
and evidence references retain their 0.3 behavior.
