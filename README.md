# RelayMark

RelayMark is a Markdown-compatible document format for human prose plus
validated declarative blocks.

This repository owns the portable RelayMark contract:

- `spec/relaymark/` - normative draft spec, JSON Schemas, directive registry,
  examples, and conformance fixtures.
- `src/` - dependency-free reference runtime for parsing, validation, compiling,
  projections, and conformance.
- `bin/relaymark.mjs` - small CLI wrapper.
- `adapters/swift/` - generic Swift value-model adapter for AST and manifest,
  exposed as the root Swift package product `RelayMarkSwift`
  JSON.
- `adapters/elixir/` - generic Elixir value-model adapter for AST and manifest
  JSON.

Relay app integrations belong in client repositories. Generic runtime pieces and
portable adapters belong here.

## Adapter Boundary

Keep these in this repo:

- Core parser, validator, compiler, projection, and conformance runner.
- JSON Schema and fixture definitions.
- Generic TypeScript/JavaScript APIs.
- Generic Swift and Elixir value models for RelayMark AST and manifests.
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

## Swift package distribution

`RelayMarkSwift` is distributed from the repository root at
`https://github.com/boldflight/relay-mark.git`. Published releases use semantic
version tags. Applications should use a version requirement and commit their
`Package.resolved`; the nested package remains available for focused adapter
development. The Swift package manifest requires Swift tools 6.2 for Xcode 26
compatibility and is also verified using the current Swift 6.4 beta toolchain.

The reference runtime intentionally starts small. Its job is to make the draft
spec executable before richer client/editor adapters exist.
