# RelayMark Swift Adapter

Generic Swift value models for RelayMark AST and manifest JSON.

The package uses Swift tools 6.4 and supports macOS, iOS, and visionOS 26 or
newer. Manifest models include generic inline-reference, research
claim, and structured-comparison projections; host apps remain responsible for
rendering and executing reviewed actions.

```sh
swift test

# The nested adapter manifest remains available for focused adapter development.
swift test --package-path adapters/swift
```

This package is intentionally product-neutral. It does not execute Relay actions
or know about app UI, persistence, routes, local caches, or action queues.
