# Optional native Yjs collaboration adapter

`RelayMarkCollaboration` embeds the actual Yjs 13.6.32 runtime in JavaScriptCore. It does not render a WebView, download executable code, or own a database, account, authorization or transport. `RelayMarkSwift` remains free of this dependency. Rebuild the committed bundle with `npm ci && npm run build:collaboration`; the exact dependency lock and MIT notices are committed.

## Decision and upstream contribution path

We first inspected and ran upstream [y-crdt/yswift](https://github.com/y-crdt/yswift) at `d22bde0fb1fe134ccda7e22a97f0b2c19f5710c5`. Its 51 existing tests pass on Xcode 27 beta / Swift 6.4 macOS. `Sources/YSwift` and `lib/src` expose arrays, maps and text, origins and undo, but no XML fragment/element/text or relative-position bindings. The released 0.2.1 XCFramework plist contains macOS, iOS and iOS simulator slices; it has no visionOS slice. These are capability gaps, not a failed macOS build. Adding the complete XML/anchor bridge and building/distributing new Rust binaries is larger than a small support patch. JavaScriptCore is therefore the simplest complete fallback for this milestone.

A future upstream contribution should add Yrs XML fragment/element/text operations, attributed deltas, relative positions, and visionOS device/simulator artifacts together with these interop fixtures. Evaluate a switch only after the same fixture and destination gates pass. No fork or upstream issue/PR has been published.

## Contract

The canonical versioned contract and capability matrix live in
[the collaboration specification](../../spec/relaymark/collaboration/README.md).
This adapter guide describes implementation and invocation details.


* Schema negotiation identifier: `relaymark-prosemirror-v1` (the host negotiates supported editing capabilities).
* One authorized document incarnation per replica; root `Y.XmlFragment('default')`, matching TipTap Collaboration's default field.
* Binary updates and state vectors use Yjs v1 encoding (Yjs major 13); `encodeUpdate(since:)` includes deletion-only differences.
* `@MainActor` confines JavaScriptCore ownership and supports synchronous native editor transactions. JSON and `Data` are the only public boundary values.
* `snapshot()` returns `{kind:"fragment",children:[...]}`. Elements contain `kind:"element",name,attributes,children`; text contains `kind:"text",delta:[{insert,attributes?}]`. Unknown XML nodes and marks survive round trips. This does **not** prove that the native editor can author them; unsupported content must remain read-only until its binding is implemented.
* XML paths are current child indices. Resolve a relative anchor immediately before an edit when selection may have moved due to remote updates. Text offsets and lengths are UTF-16 code units, never Swift Character counts.
* `edit` accepts one operation: `insertNodes` (path/index/nodes), `deleteNodes` (path/index/length), `insertText` (path/index/text/attributes), `deleteText` (path/index/length), or `formatText` (path/index/length/attributes). A null mark attribute removes that mark. Range/path/type checks precede mutation. `insertText` without attributes inserts an unformatted run; callers resolve native typing attributes explicitly.
* `edit`, `undo`, and `redo` return the local incremental binary updates. The host must persist them before claiming local save or sending them. Remote/restored updates do not enter local selective undo. A process restart restores text from a checkpoint and updates; the undo stack itself is intentionally session-only.
* Relative anchor resolution returns nil when its type cannot be found. Awareness transport and cursor identity are host responsibilities.

The JavaScriptCore host supplies cryptographic random bytes and UTF-8 encoding through Swift. The app drives the standard y-protocols awareness timer every three seconds while connected; the library itself owns local renewal and peer expiry. Awareness bytes never enter the durable text journal. There are no network providers in the bundle. Large-document input latency and IME/selection UI behavior still require application-level measurement.

## Verification

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
RELAY_COLLABORATION_INTEROP_OUTPUT=/private/tmp/relay-native-interop.json \
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --filter RelayMarkCollaborationTests
node scripts/collaboration-interop.mjs /private/tmp/relay-native-interop.json
```

The fixture tests Node-created XML and formatting/reference marks, independent native/browser edits, duplicate updates, restart from binary state, local selective undo preserving a remote edit, relative anchors, Unicode, deletion-only diff, and invalid range rejection. `scripts/collaboration-interop.mjs --generate` regenerates the deterministic browser fixture; fixture regeneration is deliberate, not a step in ordinary verification.

Generic iOS and visionOS compiler builds of `RelayMarkCollaboration` passed using Xcode 27 beta with signing disabled. This is a replica proof; it does not establish integrated native input composition, server durability, permissions, persistence policy, or a complete offline client.

## Native structured prose and presence

The editable projection supports paragraph, heading, codeBlock, blockquote, bulletList, orderedList and listItem, including nested container paths. It carries Foundation presentation intents, preserves unmodified XML identities, inserts a sibling list item for Enter in a simple item, and retains literal newlines inside code. Unsupported embedded blocks or marks remain preserved and read-only. Cross-block replacement removes only affected leaf blocks and empty ancestors; it does not rebuild the fragment. The native editor groups text and formatting into one local undo step.

Standard `y-protocols` 1.0.7 awareness uses `user: {name, color}` and y-prosemirror-compatible relative `cursor: {anchor, head}` values. The host publishes throttled selection changes, invokes library renewal/expiry, and removes peers by server channel origin. The fixture proves browser-to-native and native-to-browser cursor decoding and that awareness does not change durable document bytes. Relay Swift now supplies a host presence list and narrow AppKit/UIKit TextKit adapters that draw remote carets and ranges using native layout geometry. Its marked-text probe buffers intermediate composition and rebases committed input through these anchors.
# Exact text item selection

`captureTextItems({path,index,length})` captures a text-only UTF-16 selection as
opaque JSON `{version:1,runs:[{item:{client,clock},type:{client,clock},count}]}`.
The item identifies the first exact UTF-16 unit and the type identifies its shared
text leaf. Association zero is implicit. `count` represents consecutive clocks
for that client and shared type. Explicit identity JSON works through public
Yjs/Yex relative-position JSON APIs without requiring interchangeable binary
codecs. Both IDs are strictly shaped, clients are nonnegative safe integers,
clocks are UInt32, and item clock plus count cannot exceed 2^32.
Replica client IDs never identify human actors. The host supplies trusted edit
intent and binds this value to a document/incarnation; this API supplies identity
only, not authorization or source-contribution semantics.

`resolveTextItems(selection)` returns `{segments,collapsedUnits,unavailableRuns}`.
Segments contain `{path,index,length,text}` in current document order, regardless
of input run order, and merge adjacent selected units only. They exclude unrelated
intervening insertions. `unavailableRuns` names original run indices whose items
or shared types cannot be resolved, including deleted ancestors; callers must not
use partial output as complete source text. Zero-width identities are counted
separately as collapsed units. Public Yjs resolution cannot prove a forged
collapsed ID historically represented text rather than a formatting structure;
shape validation does not authenticate provenance. Hosts must preserve trusted
capture intent and servers must validate against the accepted baseline.
Resolution never follows local-only undo mappings. Undo restoration
requires the host's saved ownership intent; fresh CRDT IDs do not prove authorship.

Input rejects unknown fields, invalid identities, overflow,
overlapping item clocks, more than 4096 runs or 131072 total UTF-16 units, paths
deeper than 128, atoms and split/unpaired surrogate sequences. Resolution also
rejects more than 4096 output segments or traversal beyond 65536 nodes/depth128.
Child counts are admitted before allocating traversal arrays. Capture and
resolution inspect each selected leaf's full text delta to reject embedded atoms;
their full-leaf scanning cost is bounded by the host's existing document admission
limits, not by the selected-unit bound. This API does not impose a new document
size policy.
Text selections
cannot silently flatten structural separators. These bounds limit allocation but
are not a worst-case latency guarantee for heavily fragmented document history.
Swift exposes `captureTextItems(path:index:length:) -> Data` and
`resolveTextItems(_:) -> TextItemResolution`; JSON remains opaque at the host seam
and is validated by the same runtime. The host must preserve exact bytes when it
persists an immutable operation.

The generic seam does not establish server-side Yex anchor validation or a
cross-device contribution-index protocol. Those capabilities require separately
verified supported server APIs and acceptance/persistence integration before
Enhanced source mapping can be activated. The exploratory script and its limits
remain documented in `CONTRIBUTION_IDENTITY_PROTOTYPE.md`.

`elixir scripts/verify-text-items-yex.exs` installs exact Yex 0.11.0/Jason 1.4.5
and checks the trusted portable fixture (four scenarios, 28 item identities).
It can also run through `mix run /absolute/path/to/verify-text-items-yex.exs`
in a consumer already loading those versions. Yex requires
`Yex.Doc.Options{offset_kind: :utf16}` for matching native/Yjs coordinates;
default byte offsets produce wrong positions after emoji. The proof uses public
[`StickyIndex.from_json/to_json/get_offset`](https://github.com/satoren/y_ex/blob/v0.11.0/lib/sticky_index.ex)
APIs; Yex's `encode_v1` representation is not interchangeable with Yjs's canonical
relative-position binary encoding. The script relies on trusted expected paths
to check surviving item/leaf identity and cannot authenticate collapsed item type
using `get_offset` alone. It is interoperability evidence, not a production server
resolver or permission to upgrade a consumer dependency.

## Browser package consumption

The Elixir package includes the pure identity adapter at
`priv/collaboration/text-items.js`. Browser hosts can import `captureTextItems` and
`resolveTextItems` through their existing dependency resolver. The adapter imports
the host's `yjs`; it does not construct a document or include another runtime.
`npm run build:collaboration` refreshes this packaged copy from the canonical source.
The package test checks byte equality. Host code still owns edit intent and
authenticated source admission. Availability requires a package revision containing
this export; this source change does not publish a Hex release.
