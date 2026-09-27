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

The separate draft v3 portable AST projection now preserves task-list and
task-item `relaymarkId` values, checked state, and an optional canonical entity
UUID as inert metadata. It accepts a first paragraph followed by paragraphs or
nested task/plain lists, with at most 16 task-list levels and 4,096 direct
children per task node. Yjs omits a null `entityId` XML attribute; the native
read projector restores the portable null value. This does not change the
existing narrow native task editor or admit task lists to a live profile.

Draft v3 native Return now splits a top-level paragraph with at most one XML
text leaf into an identified sibling. It retains the original block ID,
preserves suffix marks, checks the exact snapshot and relative anchor, and
produces one Yrs update for peer replay and undo. This is an editor operation,
not live v3 admission or support for Return in every RelayMark structure.
The v3 native prose map also retains a validated block entity reference as one
inert selection unit, so an adjacent paragraph remains editable without
flattening or rewriting the reference. Target resolution remains host-owned.

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

### Formatting existing headings and bounded list paragraphs

`supportsInlineFormatting()` admits the same validated basic paragraph/heading
blocks or bounded bullet/ordered-list items as native editing. `formatProse`
uses the shared projection's text-leaf intersections and formats them in one Yrs
transaction, retaining XML paths, heading IDs/levels, ordered starts and anchors.
It does not admit mixed top-level list/prose documents or arbitrary containers.
Native hosts may further restrict structured selections to one block/item.

Within-leaf heading and list text replacement now delegates to the same existing
mark-preserving `replaceText` operation as ordinary prose. The browser-generated
`structured-v1.json` fixtures cover both list directions and all heading levels;
focused tests assert structure and anchors, code/strike, marked replacement and
undo. Structural edits and unhandled mixed-run styling remain separately gated.

### Interior list Return anchor gate (September 26, 2026)

The experimental `scripts/collaboration-list-split-probe.mjs <web-assets-path>`
creates a fresh Chromium TipTap editor with its community Collaboration extension
and invokes `splitListItem` inside a nested ordered item. It records the real
Yjs seed/update and preexisting relative anchors in `list-split-probe-v1.json`.
No live server or application document is involved.

Splitting `Nested 🌍 text` at UTF-16 offset 3 produces `Nes` and a new sibling
containing `ted 🌍 text`, retaining the ordered start of 3. Prefix and unrelated
sibling anchors retain their positions. However, the old suffix anchor at offset
10 resolves to offset 3 in the old XML text leaf; it does not follow the suffix
to offset 7 in the new leaf. `RelayMarkNativeListSplitProbeTests` proves Yrs
replays the browser update and resolves these anchors identically.

This is a standard split/copy identity limitation, not a missing XML insertion
binding. Native Return/split remains gated: we do not silently relocate durable
anchors or add a custom CRDT move algorithm. Backspace/join has the same moved-text
question and is not admitted by this experiment. A safer next independent step
is faithful empty-item presentation, permitting end-of-item Return to add an
empty sibling without moving existing text. Durable anchors across moved text
require a separately reviewed identity/remapping contract or community engine
capability before interior split/join can claim preservation.


### Empty list items and end-of-item insertion (September 26, 2026)

`scripts/collaboration-list-end-return-probe.mjs <web-assets-path>` records
community TipTap end-of-item Return in Chromium. The new sibling is a listItem
containing an empty paragraph with no XmlText child. No existing text is moved;
prefix, suffix and unrelated sibling anchors retain their original positions.

The additive native `appendEmptyListItem(after:)` uses existing YSwift/Yrs XML
insertion in one local undo transaction and matches that browser shape. It accepts
only a nonempty paragraph in an admitted list item with no nested descendants.
The host must establish an exact end caret before invoking it. Empty-item exit,
interior split, joins, reordering and deeper/mixed structures remain unsupported.
`replaceListParagraphText` can subsequently create the first XmlText in an empty
paragraph. Projection `blockIntents` carries each block's presentation even when
its text range is empty; it adds no sentinel or placeholder characters.

`RelayMarkNativeEmptyListTests` covers browser-update replay, native-to-Yjs replay,
unchanged original anchors, nested ordered start/ordinal, trailing empty rows,
typing, undo/redo, and nonmutating malformed/foreign/unsupported anchors. These
adapter tests do not by themselves establish native host rendering, Return routing
or durable application journaling; those remain a separate host gate.


### Existing authored link marks (September 26, 2026)

`scripts/collaboration-link-fixture.mjs <web-assets-path>` uses the actual Relay
collaborative Link and PaperHeading extensions in a Chromium TipTap editor.
The fixture covers HTTP, HTTPS, mailto and canonical `relay:entity/UUID` in
paragraph, stable-ID heading, bullet and ordered-list text. Native `formatProse`
already supports these marks; no new CRDT operation or mark grammar is introduced.
The cross-runtime test matches browser snapshots, preserves bold text and original
relative anchors, removes/undoes links, and rejects unsupported title metadata
without mutation. Host destination policy and authorized navigation stay outside
RelayMark; labels are authored text, never hydrated server titles.

Community Link currently declares a nullable title attribute. The strict v1/v2
profile excludes that attribute, so the fixture uses Relay's narrow collaborative
extension that omits it. It does not strip unknown metadata from stored documents.

### Existing ordered-list start command

`RelayMarkNativeDocument.setOrderedListStart(anchor:expectedStart:start:)` changes
only the `start` attribute of an existing top-level or one-level nested ordered
list. Its authoring bound is 1...1,000,000; the stored v1 grammar is unchanged.
The command validates the current anchored list and expected effective start
(default 1), uses Yrs's existing attribute transaction, and preserves every child
XML identity. It does not convert lists, indent, reorder, split or join text.

`bun scripts/collaboration-list-start-probe.mjs /absolute/path/to/web/assets`
produces the real Chromium TipTap Collaboration `updateAttributes('orderedList',
{start:7})` fixture. `RelayMarkNativeListStartTests` checks semantic browser parity,
unchanged Unicode text anchors, concurrent peer text convergence, undo/redo,
encoded-state reopen, and nonmutating invalid/stale/foreign commands.

### Existing single-leaf code block

`supportsCodeBlockEditing()` and `replaceCodeBlockText(start:end:text:)` admit one
existing v1 code-only document with one unmarked `codeBlock` / `XmlText` leaf.
The language attribute and both XML identities remain in place. LF and tabs
are text inside that leaf; the command uses the existing Yrs UTF-16 replacement
transaction and origin-specific undo. Emptying the leaf preserves it and remains
editable. Zero-leaf seeds, mixed/nested blocks, marks, invalid UTF-16 boundaries,
CR/Unicode line separators/object atoms and oversized content fail closed.
There is no create/convert/exit command and no v2 admission change.

The real Chromium TipTap Collaboration fixture is generated by
`bun scripts/collaboration-code-block-probe.mjs /absolute/path/to/web/assets`.
`RelayMarkNativeCodeBlockTests` covers multiline Unicode/backticks, peer merge,
unchanged anchors, undo/reopen and invalid shapes. The generic Elixir codec test
checks its four-backtick Markdown fence. Independent server validation on
September 26 confirmed `DocumentProse.source → seed → source` preserves exact
code text, language `swift` and the one-leaf shape; no live server was changed.

### Existing single-paragraph quote

`supportsQuoteEditing()` and `replaceQuoteText(start:end:text:)` admit only a v1
quote-only root with one paragraph and one XmlText. The operation changes text
inside that same leaf using existing Yrs replacement semantics. Existing grammar
marks are read/preserved; callers still validate mixed-run typing presentation.
Quote/paragraph/leaf identities are retained. LF, hard breaks, wrapping/unwrapping,
multiple paragraphs, nested/mixed blocks and unsupported attributes stay gated.

The actual Chromium TipTap Collaboration fixture `quote-v1.json` proves Unicode
insertion inside bold text, unchanged prefix anchor and correctly shifted suffix
anchor. Native tests cover replay, origin undo, peer convergence, reopen, empty
leaf typing and invalid shapes. The generic Elixir source fixture preserves the
quote and bold Markdown rather than flattening it to ordinary prose.

### Bounded native quote end Return

The native Yrs adapter can append one empty second paragraph to an existing
single-paragraph quote. Existing quote/paragraph/text objects are retained.
Within-paragraph typing admits this exact flat one-or-two-paragraph shape; the
second paragraph may initially have no text child. Its first typed text creates
one XmlText and inherits the preceding last-run marks, matching the real TipTap
fixture. This does not implement interior splits, joins, third paragraphs,
wrapping, unwrapping, mixed blocks or arbitrary quote nesting. Hosts must require
a collapsed end caret for append and persist the returned update normally.

`collaboration-quote-return-probe.mjs` captures actual community `splitBlock` and
subsequent typing. Focused tests compare XML and marks against that fixture,
original anchors, undo/redo and cross-runtime replay/reopen. Native UI admission
and actual input remain a separate consumer gate.
