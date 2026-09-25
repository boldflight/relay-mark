# Offline multiplayer: start here

The current branch is `codex/offline-multiplayer`. The [community-first implementation plan](https://github.com/boldflight/relay-elixir/blob/codex/offline-multiplayer/docs/plans/2026-09-14-community-first-multiplayer.md) is the single controlling scope, estimate and resume point. It supersedes the older custom lineage roadmap.

The September 24 integration spike is complete, and implementation has resumed.
The chosen native direction is a maintained fork of y-crdt/YSwift with Yrs as its
CRDT engine. Add the missing XML, relative-position, and Apple platform bindings
in reviewable upstream contributions; do not implement another CRDT algorithm.
`RelayMarkProseProjection` contains the pure Swift presentation and UTF-16
position mapping shared by both adapters. `RelayMarkNativeCollaboration` adapts
YSwift XML updates to RelayMark's portable snapshot and editor operations.
`RelayMarkCollaboration` retains the existing JavaScriptCore adapter and its
public compatibility alias for the projection. The app owns storage, account
lifecycle, and Phoenix transport. JavaScriptCore remains a reference and
migration fallback until the native binding and app pass the cross-runtime and
macOS/iOS/visionOS gates.

The native adapter's ordinary prose edit scope is top-level, attribute-free
paragraphs with one XML text leaf each. It supports UTF-16 replacements, LF
splits/joins, inline formatting on a leaf, relative anchors and local session
undo through Yrs. `RelayMarkNativePresence` uses Yrs awareness, including
Yjs-compatible cursor JSON, origin-scoped removal, snapshots and expiry; those
bytes never enter document updates. Admission must check this shape before
mounting an editor and require `integrationStatus().isComplete` after replaying stored
updates, because an ordinary-looking snapshot can still have unresolved Yrs
structs or deletes. Unsupported structured documents remain on the existing
adapter. A host must persist each returned update before reporting local save.

The first basic-Markdown operation also admits top-level paragraphs and
headings (including stable `headingId`) containing text leaves and hard breaks.
It edits within one block and can insert/delete a hard break without changing
the heading element. This is adapter capability, not yet app-session admission;
the host must use it in the same editor path only after its own gates pass.

The server/browser direction keeps Phoenix, Yex, Yjs, and y-protocols. Hocuspocus
and y-websocket are reference implementations for provider behavior, not new
transport or service dependencies. Ordinary prose uses standard session undo;
advanced contribution-history work is outside this milestone.

An opt-in task-list experiment uses the browser's real Yjs XML shape:
`taskList` → `taskItem` (`checked`, optional `entityId`) → paragraph. The native
adapter can read these items and make narrow checked/text updates against a
Yjs relative item anchor while preserving the task UUID. It rejects unknown
metadata and nested shapes it cannot edit. Neither browser nor native live
admission enables this extension yet; task actions and native task UI remain
host-owned work after schema negotiation.

Two additional native operations are now covered by real Chromium TipTap/Yjs
fixtures: `setHeadingLevel(anchor:expectedHeadingID:level:)` changes an existing
top-level v1 heading to level 1–6 while retaining its XML identity and heading ID;
`replaceListParagraphText(anchor:start:end:text:)` edits one existing paragraph's
single text leaf in a bullet/ordered list with at most one nested list level.
Ordered-list start values and all container nodes remain intact. These operations
resolve Yjs relative anchors, reject invalid/foreign/deleted anchors and unsupported
shapes before mutation, and use the existing Yrs local-origin session undo stack.
They do not enable app admission, heading controls, list indentation/conversion,
item splitting, cross-item edits, multiple text leaves, or a second editor. Hosts
still bind anchors to an authorized document/incarnation and persist returned
updates before reporting save. Reproduce the browser fixtures with
`bun scripts/collaboration-structured-fixtures.mjs /absolute/path/to/web/assets`
and run `swift test --filter RelayMarkNativeStructuredTests`.

### Native inline mark command metadata

`RelayMarkLocalTransaction.NativeFormatting.Mark` also represents `strike` and
`code`; existing `bold`/`italic` encoded values are unchanged. The existing Yrs
`formatProse` operation accepts both marks, rejects incompatible combinations
before mutation, and accepts clearing other marks in the same transaction when
code is enabled. It remains scoped to ordinary paragraphs. This metadata change
does not enable link authoring or expand host admission to structured formatting.

`inline-marks-v1.json` is produced by an actual Chromium TipTap StarterKit editor
using `scripts/collaboration-inline-mark-fixture.mjs <web-assets-path>`. Its native
conformance test checks portable updates, a Unicode boundary, paragraph text
anchors, concurrent peer insertion and local undo/redo. Host UI and IME acceptance
are separate Swift app gates.

Native `replaceText` explicitly carries an existing run's attributes when the
replacement lies wholly in that run, or insertion lies strictly inside it.
YSwift's `insert` default passes an empty attributes map rather than inheriting
marks. The adapter supplies the existing attributes to that community operation;
no CRDT behavior is reimplemented. Mixed-run replacements and exact insertion
boundaries still require host candidate validation and are not newly promised.
