# Offline multiplayer: start here

The current branch is `codex/offline-multiplayer`. The [community-first implementation plan](https://github.com/boldflight/relay-elixir/blob/codex/offline-multiplayer/docs/plans/2026-09-14-community-first-multiplayer.md) is the single controlling scope, estimate and resume point. It supersedes the older custom lineage roadmap.

The September 24 integration spike is complete, and implementation has resumed.
The chosen native direction is a maintained fork of y-crdt/YSwift with Yrs as its
CRDT engine. Add the missing XML, relative-position, and Apple platform bindings
in reviewable upstream contributions; do not implement another CRDT algorithm.
`RelayMarkCollaboration` owns Relay's XML schema and native editor adapter, while
the app owns storage, account lifecycle, and Phoenix transport. The existing
JavaScriptCore adapter remains a reference and migration fallback until the native
binding passes the same cross-runtime fixtures and macOS/iOS/visionOS gates.

The server/browser direction keeps Phoenix, Yex, Yjs, and y-protocols. Hocuspocus
and y-websocket are reference implementations for provider behavior, not new
transport or service dependencies. Ordinary prose uses standard session undo;
advanced contribution-history work is outside this milestone.
