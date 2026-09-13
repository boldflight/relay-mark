# RelayMark Elixir adapter release notes

## Unreleased

## 0.6.2

- Adds `RelayMark.CollaborativeProse.to_markdown/1`, a conservative projection
  from the version-one collaborative XML tree to Markdown. Unsupported nodes,
  marks and attributes return an error rather than silently losing content.
- Keeps collaboration transport, CRDT execution and host authorization outside
  this generic codec; no native Yjs dependency is required by the Hex package.
- Preserves existing adapter APIs and the portable `0.6.0-draft` conformance
  contract. The package includes the codec and canonical bundled schemas.

## 0.6.1

- Exposes `RelayMark.project_manifest/2` as the canonical public manifest
  projection API so Relay hosts do not maintain drifting local projectors.
- Keeps active first-party Relay Elixir consumers on the latest published Hex
  release. Until the deliberate 1.0 boundary, compatible releases advance only
  the patch component on the `0.6.x` line.
- Implements the portable `0.6.0-draft` conformance contract.

## 0.6.0

- Updates JSV to 0.22 and removes the arbitrary major-version ceiling. The
  adapter lockfile records the tested release while deliberate updates may
  select any newer stable JSV version.
- Implements the portable `0.6.0-draft` contract while preserving valid
  pre-1.0 document meaning and public Elixir adapter source compatibility.
- Implements portable `0.6.0-draft` Agent Paper binding-manifest and semantic
  layer-composition values, validation, and shared fixture coverage.

- Documents independent `elixir-X.Y.Z` source tags and compatible pre-1.0
  consumer ranges. The Hex version no longer needs to match a Git/Swift release
  number; portable compatibility is identified by the conformance-suite
  version.

## 0.5.3

- Publishes the unchanged portable RelayMark 0.5 contract alongside the Swift
  package's Apple OS 26.5 compatibility release.

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
