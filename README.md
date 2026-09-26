# RelayMark

RelayMark is the safe, portable document and composition language of Agent
Paper: human-readable Markdown prose plus validated declarative blocks that
deterministic editors and renderers can understand across web and native
clients. On the web, TipTap edits this document; native clients use an
equivalent native RelayMark editor.

RelayMark describes authored content, host binding addresses, renderer-neutral
presentation intent, registered action references, and portable composition
metadata. It is not Relay's database, authorization layer, renderer toolkit,
or an unrestricted application language. It does not describe entity headers,
navigation, modal or sheet containers, publish/info controls, footers,
previews, or collection engines; those belong to the paper or entity host.
Relay domain hosts resolve authorized
data and execute reviewed actions; Relay Kit and other renderers consume the
validated AST without gaining authority.

The reference runtime and generic adapters implement the portable
`0.7.0-draft` contract line. Strict semantic-version repository tags are the
distribution boundary for Swift consumers; independently versioned
`elixir-X.Y.Z` tags and `relay_mark_elixir` Hex releases are the distribution
boundary for Elixir consumers. The two distribution versions may coincide,
but they are not a lockstep release number. An untagged branch does not
establish publication.

This repository owns the portable RelayMark contract:

- `spec/relaymark/` - normative draft spec, JSON Schemas, directive registry,
  examples, and conformance fixtures.
- `src/` - dependency-free reference runtime for parsing, validation, compiling,
  deterministic serialization, capability negotiation, layer composition,
  projections, and conformance.
- `bin/relaymark.mjs` - small CLI wrapper.
- `adapters/swift/` - generic Swift value models, Agent Answer validation, and
  the native attributed-text bridge for Markdown-compatible RelayMark prose,
  exposed as the root Swift package product `RelayMarkSwift`.
- `adapters/elixir/` - generic Elixir value models, document validation, and
  Agent Answer transported-pair validation.

Relay app integrations belong in client repositories. Generic runtime pieces and
portable adapters belong here.

## Adapter Boundary

Keep these in this repo:

- Core parser, validator, compiler, projection, and conformance runner.
- JSON Schema and fixture definitions.
- Generic TypeScript/JavaScript APIs.
- Generic Swift and Elixir value models and portable validation helpers.
- Portable semantic layer roles, stable block anchors, deterministic placement,
  and safe missing-anchor fallbacks over already-authorized contributions.
- A future generic Tiptap/ProseMirror adapter if it only maps RelayMark AST to
  editor nodes and back.

Keep these in client repos:

- Relay Elixir persistence, `Relay.Action.Registry` execution, LiveView hooks,
  toolbar UX, and app authorization.
- Swift app UI, local cache, action queues, and product-specific screens.
- Any adapter code that depends on a specific app's entities, routes,
  permissions, or theme.
- Host binding resolution, field values, read-model records, layer grants,
  audience profiles, retention, revocation, search filtering, and sync.

## Agent Paper composition profile

The additive `0.6.0-draft` profile introduces four orthogonal directives:

- `@EntityRef` references any host entity without copying its fields.
- `@PropertySheet` names an approved schema binding and ordered field keys.
- `@DataView` names an approved read model plus declarative projection intent.
- `@Layout` provides an adaptive grouping hint whose fallback is source-ordered
  one-column content.

`@ActionRow` remains the only portable action-reference primitive. Writing or
rendering it never executes the action. Registry-owned capability IDs and
fallbacks make unsupported blocks visible and deterministic rather than
silently dropping content.

Paper-layer composition is deliberately separate from authored source. A host
authorizes contributions first, then may pass only those contributions through
the portable role/anchor/placement model. Source mode edits one selected
textual layer; the composed result is never serialized as a replacement source
document. RelayMark carries no layer grants or private resolved values.

See [ADR 0001](docs/adr/0001-safe-agent-paper-composition-profile.md) for the
authority and fallback decisions.

## Commands

```sh
npm test
npm run conformance
npm run test:adapters
npm run check
swift test
(cd adapters/elixir && mix test)
node bin/relaymark.mjs compile spec/relaymark/examples/mentor-meeting.relaymark
```

Validate one exact transported Agent Answer pair with the reference runtime:

```js
import { validateTransportedAgentAnswerPair } from "./src/index.js";

const result = validateTransportedAgentAnswerPair(documentBytes, manifestBytes, {
  surface: "scripture_ask"
});

if (result.diagnostics.length > 0) reject(result.diagnostics);
```

## Swift package distribution

`RelayMarkSwift` is distributed from the repository root at
`https://github.com/boldflight/relay-mark.git`. Published releases use semantic
version tags. Through the `0.6.x` pre-1.0 line, public adapter APIs and valid
portable document meaning remain compatible; breaking changes are reserved for
1.0.

Active first-party Swift applications may follow `main` during pre-1.0
development when their build service has repository access:

```swift
.package(
    url: "https://github.com/boldflight/relay-mark.git",
    branch: "main"
)
```

This lets Relay repositories converge without coordinated manifest edits for
every compatible change. Published semantic-version tags remain the stable
distribution boundary for external or intentionally frozen consumers, which
may use a compatible range and commit `Package.resolved`. The repository root
is the only Swift package manifest and remains the focused adapter-development
entry point. It requires Swift tools 6.3 for the Xcode 26.5 production baseline
and is also verified
using the current Swift 6.4 beta toolchain.

SwiftPM does not provide named `PackageDescription` enum cases for every Apple
OS patch release, so both package manifests use the supported string form for
their `26.5` deployment floors. `swift package dump-package` must preserve
`26.5`; local verification uses Xcode 27 beta, while Xcode 26.5/Swift 6.3
remains the production CI compatibility gate.

Routine releases are made directly from `main`. Branches and pull requests are
optional, not release prerequisites. Any verified `main` commit may receive an
annotated semantic-version tag after release metadata and the relevant local
checks are current.

## Elixir package distribution

`RelayMark` is distributed on Hex as `relay_mark_elixir`. Active first-party
Relay Elixir applications consume the latest published Hex release:

```elixir
{:relay_mark_elixir, ">= 0.6.1"}
```

The application lockfile records the exact tested release. An intentional
`mix deps.update relay_mark_elixir` selects the newest stable package without
requiring a manifest edit. Production Docker builds must not depend on access
to this private Git repository.

The Hex package is self-contained. It bundles the exact JSON Schemas and
directive registry required at compile time, while repository tests enforce
byte-for-byte parity with the canonical files under `spec/relaymark/`.

Hex adapter releases use their own version and annotated `elixir-X.Y.Z` source
tag. They do not wait for, or force, a repository/Swift version bump. Both
release streams declare the portable conformance-suite version they implement;
that contract version—not equal distribution numbers—is the cross-runtime
compatibility key.

Until the deliberate 1.0 boundary, compatible repository, Swift, and Hex
distribution releases remain on `0.6.x` and advance only the patch component.
Ordinary additive work does not consume another minor version.

The reference runtime intentionally starts small. Its job is to make the draft
spec executable before richer client/editor adapters exist.
