# RelayMark Swift Adapter

Generic Swift value models for RelayMark AST and manifest JSON.

The package uses Swift tools 6.4 and declares visionOS 27 alongside its macOS
and iOS support. Manifest models include generic inline-reference, research
claim, and structured-comparison projections; host apps remain responsible for
rendering and executing reviewed actions.

```sh
swift test --package-path adapters/swift
```

This package is intentionally product-neutral. It does not execute Relay actions
or know about app UI, persistence, routes, local caches, or action queues.
