# RelayMark Swift Adapter

Generic Swift value models for RelayMark AST and manifest JSON.

This adapter maps the Agent Paper RelayMark document to portable Swift values.
Native app screens and their headers, navigation, sheets, footers, previews,
and collection engines remain host UI outside Agent Paper.

The adapter also provides `RelayMarkAttributedTextCodec`, a product-neutral
authoring bridge between Markdown-compatible RelayMark prose source and
Foundation `AttributedString`. It round-trips headings, lists, emphasis, code,
links, and canonical `relay:` entity references. The canonical interchange is
still `RelayMarkDocument`; host apps resolve entity identities and choose their
native editor and chip presentation.

The package requires Swift tools 6.3 to match production Xcode 26.5 and is
continuously verified with Swift 6.4. It supports macOS, iOS,
and visionOS 26.5 or newer. Manifest models include generic inline-reference,
versioned-evidence, action-proposal lifecycle, research-claim, and
structured-comparison projections. The adapter validates and projects the
portable `relaymark.agent_answer.v1` profile, applies Scripture evidence rules
only from explicit host action context, and validates exact transported
AST/manifest byte pairs without adding product-specific UI or authorization.
The shared receipt binds the exact canonical answered and refused fixture
bytes. Host apps remain responsible for rendering, authorization, review
persistence, execution, and undo.

The `0.6.0-draft` value models also decode Agent Paper property-sheet and data-
view binding manifests, open renderer capability IDs, and portable semantic
layer roles/anchors/fallbacks. These are data-only values. `RelayMarkSwift`
does not depend on Relay Kit; a UI renderer may depend on both RelayMarkSwift
and Relay Kit without creating a reverse dependency.

For durable action rows, `proposalID` is the generator/client identity and
`proposalRecordID` is the distinct host record address passed to an authorized
review or undo API. Neither field is an authorization credential.

```swift
let transport = try RelayMarkAgentAnswerValidator.validateTransport(
    documentJSON: documentData,
    manifestJSON: manifestData,
    context: .scriptureAsk
)
let answer = try transport.requireProjection()
```

```sh
swift test
```

Run that command from the repository root. The root manifest is both the
published Swift package and the focused adapter-development entry point.

This package is intentionally product-neutral. It does not execute Relay actions
or know about app UI, persistence, routes, local caches, or action queues.

### Scratch replica completeness

`RelayMarkCollaborationDocument.integrationStatus()` exposes unresolved structure
and deletion dependencies separately. After restoring a checkpoint and applying
an ordered local suffix, require `isComplete` before treating the scratch document
as complete source. Applying updates successfully or comparing state vectors
does not cover pending delete sets. Ordinary replay keeps its existing behavior:
missing dependencies remain retained and settle when their updates arrive.

This additive adapter checks the bundled Yjs store representation and
fails closed if that representation changes. It establishes neither authorization,
authorship, server receipt coverage nor equality with current remote state. Hosts
still validate their own source frame, journal cuts and exact contribution IDs.
