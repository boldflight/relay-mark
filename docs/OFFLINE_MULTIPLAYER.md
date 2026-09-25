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
