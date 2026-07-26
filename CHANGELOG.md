# RelayMark release notes

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
- Makes the Swift Agent Answer gate reject invalid document envelopes and
  duplicate block ids, and validate complete Scripture release/resource/span
  semantics before canonical manifest projection.

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
