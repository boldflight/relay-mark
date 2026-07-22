# RelayMark Swift Adapter

Generic Swift value models for RelayMark AST and manifest JSON.

The package requires Swift tools 6.3 to match production Xcode 26.6 and is
continuously verified with Swift 6.4. It supports macOS, iOS,
and visionOS 26.6 or newer. Manifest models include generic inline-reference,
versioned-evidence, action-proposal lifecycle, research-claim, and
structured-comparison projections; host apps remain responsible for rendering,
authorization, review persistence, execution, and undo.

For durable action rows, `proposalID` is the generator/client identity and
`proposalRecordID` is the distinct host record address passed to an authorized
review or undo API. Neither field is an authorization credential.

```sh
swift test

# The nested adapter manifest remains available for focused adapter development.
swift test --package-path adapters/swift
```

This package is intentionally product-neutral. It does not execute Relay actions
or know about app UI, persistence, routes, local caches, or action queues.
