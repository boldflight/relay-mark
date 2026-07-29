# RelayMark release notes

## 0.5.3

- Lowers both Swift package manifests to iOS, macOS, and visionOS 26.5 so
  Xcode 26.5/Xcode Cloud consumers can import `RelayMarkSwift`.
- Leaves the portable RelayMark contract, schemas, fixtures, and Elixir
  implementation unchanged while publishing a matching adapter version.

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
