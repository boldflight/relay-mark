# RelayMark

RelayMark is a Markdown-compatible document format for human prose plus
validated declarative blocks.

RelayMark `0.5.1` implements the portable `0.5.0-draft` contract line in the
reference runtime and generic adapters. Semantic version tags are the
distribution boundary for Swift consumers; the matching
`relay_mark_elixir` Hex release is the distribution boundary for Elixir
consumers. Package-manifest versions or an untagged branch do not establish
publication.

This repository owns the portable RelayMark contract:

- `spec/relaymark/` - normative draft spec, JSON Schemas, directive registry,
  examples, and conformance fixtures.
- `src/` - dependency-free reference runtime for parsing, validation, compiling,
  projections, and conformance.
- `bin/relaymark.mjs` - small CLI wrapper.
- `adapters/swift/` - generic Swift value models and Agent Answer validation,
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
- A future generic Tiptap/ProseMirror adapter if it only maps RelayMark AST to
  editor nodes and back.

Keep these in client repos:

- Relay Elixir persistence, `Relay.Action.Registry` execution, LiveView hooks,
  toolbar UX, and app authorization.
- Swift app UI, local cache, action queues, and product-specific screens.
- Any adapter code that depends on a specific app's entities, routes,
  permissions, or theme.

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
version tags. Applications should use a version requirement and commit their
`Package.resolved`; the nested package remains available for focused adapter
development. The Swift package manifest requires Swift tools 6.3 for the Xcode
26.6 production baseline and is also verified using the current Swift 6.4 beta
toolchain.

SwiftPM does not provide named `PackageDescription` enum cases for every Apple
OS patch release, so both package manifests use the supported string form for
their `26.6` deployment floors. `swift package dump-package` must preserve
`26.6`; local verification uses Xcode 27 beta, while Xcode 26.6/Swift 6.3
remains the production CI compatibility gate.

## Elixir package distribution

`RelayMark` is distributed on Hex as `relay_mark_elixir`. Applications should
use a compatible version requirement and commit `mix.lock`:

```elixir
{:relay_mark_elixir, "~> 0.5.1"}
```

The Hex package is self-contained. It bundles the exact JSON Schemas and
directive registry required at compile time, while repository tests enforce
byte-for-byte parity with the canonical files under `spec/relaymark/`.

The reference runtime intentionally starts small. Its job is to make the draft
spec executable before richer client/editor adapters exist.
