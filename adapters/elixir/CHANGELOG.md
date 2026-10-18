# RelayMark Elixir adapter release notes

## Unreleased

## 0.7.0

- Raises the document bound from 4,096 to 131,072 identified blocks, counted
  at every nesting level, as the specification now states. It is a sanity
  bound; a host's state budget is reached first. Documents between the two
  bounds that 0.6 refused as `:block_limit` now decode.
- Ships `priv/collaboration/editor.js`, a 1.4 KB ESM module with the canonical
  editor schema factory and covered table-row normalizer for TipTap hosts
  that bind stock y-prosemirror, without the content-edit proof bundle.
- Keeps canonical contract 1 and the physical schema unchanged.

## 0.6.6

- Restores canonical marked-paper history after the server codec sorts mark
  attribute keys. Reconstructs the schema-defined producer encoding on a
  detached cut and requires the original stored byte hash to match exactly.
- Preserves original archives, peer prose, CRDT identities and selective
  Undo/Redo. Unknown, incomplete or nested custom attribute shapes remain
  retained and refused; corrupt values, hashes and identities still fail.
- Keeps canonical contract 1 and the physical schema unchanged.

## 0.6.5

- Imports empty Callout source as a canonical callout with one deterministic
  empty paragraph, preserving its attributes and optional title. This covers
  retained insertion-time editorial revisions without discarding their source.
- Keeps canonical contract 1 and strict document/XML admission unchanged.

## 0.6.4

- Loads directive definitions from installed application resources, so source
  imports work when the release no longer contains its compilation checkout.
- Preserves empty and nonparagraph-first CommonMark list items by adding a
  deterministic leading paragraph without changing existing child identities.
- Preserves marked ordinary wiki text and text on either side of a hard break;
  reference atoms retain identity while surrounding text keeps its marks.
- Applies registered defaults to directives with no explicit attribute list.
- Keeps canonical contract 1 unchanged and adds shared source-import fixtures
  plus an isolated runtime-resource regression.

## 0.6.3

- Restores the canonical fieldwise settings codec and finite
  `RelayMark.DocumentXML.import_aggregate_settings_snapshot/1` entry point that
  were omitted from the 0.6.2 Elixir adapter integration. The existing packaged
  policy remains authoritative across JavaScript, Swift and Elixir.
- Current XML projections emit and require canonical physical settings. Detached
  legacy previews return a validated conversion plan; canonical previews remain
  unchanged, and mixed or malformed inputs return no partial result. Hosts retain
  authority over original bytes, physical history cuts and live installation.

## 0.6.2

- Ships the approved canonical contract 1 document adapter and bundled collaboration
  resources. Hosts must convert retained prerelease documents before admitting them;
  the package version does not choose the stored document contract.
- Adds canonical HTML import and Data View projection through the shared document
  model, preserving document meaning and host-owned authorization boundaries.
- Includes the current rich content-edit and SourceBundle serialization fixes.

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

- Adds the normative `relaymark.agent_answer` profile for bounded answered
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

- Adds the portable `relaymark.scripture_release` resource profile.
- Adds lossless `relaymark.scripture_span` evidence selectors with
  chapter-or-section coordinates and string verse labels.
- Projects immutable Scripture release identity and provenance through existing
  `relay.evidence_ref` manifest sources.
- Adds matching Swift and Elixir typed adapters plus one shared AST/manifest
  conformance fixture.

Existing AST and manifest documents remain version 1. Existing generic resources
and evidence references retain their 0.3 behavior.
