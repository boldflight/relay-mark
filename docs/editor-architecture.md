# Native editor architecture

A native, collaborative, ProseMirror-compatible editor for Apple platforms;
one document model shared with TipTap through Yjs; Markdown is a portable
format, not the storage.

A paper is a Yjs document whose shape is the ProseMirror schema the web editor
uses. Web edits it with TipTap and y-prosemirror. Apple platforms edit the same
Yjs document natively: a Swift port of ProseMirror's model and transforms
applies each command, a Yjs binding writes its steps, and a TextKit 2 view
shows a projection of the document. Markdown import and export go through the
RelayMark format; nothing stores Markdown.

## Native foundation policy

The [November 13 standing rule and foundation plan](plans/2026-11-13-native-editor-foundation.md)
supersede earlier recommendations to build custom geometry, layout fragments or
overlays for web parity. The current editor uses Apple framework text views and native list attributes. Preserve the canonical
model/engine and replace unsupported presentation with established primitives.

## Layers

| Layer | Swift product | Owns | Depends on |
| --- | --- | --- | --- |
| 1. Format | `RelayMarkSwift` | The RelayMark document and source codecs, the schema contract, HTML and clipboard import, editor commands, clipboard navigation plans and the causal write plan (relaymark-core through `RelayMarkEngine`) | Foundation, RelayMarkEngine |
| 2. Model | `RelayMarkModel` | The ProseMirror port: schema, nodes, slices, resolved positions, steps, transforms, commands | Foundation |
| 3. Collaboration | `RelayMarkNativeCollaboration` | The Yjs binding (`PMYXmlBridge`), the native replica, editing commands as Yjs transactions, presence, update footprints | 1, 2, `RelayMarkProseProjection`, YSwift |
| 4a. Editor core | `RelayMarkEditorCore` | The editor session and its editing APIs, the command catalog with platform-neutral shortcuts, and the task glyph value (shape and semantic tint), without SwiftUI, AppKit or UIKit | 1, 3, `RelayMarkProseProjection`, `RelayMarkCollaboration` |
| 4b. Editor | `RelayMarkEditor` | The TextKit 2 paper views, isolated Apple TextKit 1 table attachments, native Find/accessibility, command menus, rendering-only peer-selection highlights and task icon graphics, and the services a host supplies | 4a, 1, 3, `RelayMarkProseProjection`, `RelayMarkCollaboration`, SwiftUI, AppKit/UIKit |
| 5. Host | outside this repository | Persistence and transport, authorization, product authoring and UI around the paper | 1–4 |

`RelayMarkProseProjection` and `RelayMarkCollaboration` are shared value types:
the attributed-text projection of a paper and the local transaction a host
saves.

Each table has one explicitly initialized `NSTextView`/`UITextView` with native
`NSTextTable` attributes. Its surrounding paper remains TextKit 2. Apple owns
table geometry and input primitives; `RelayTableEditor` maps semantic ranges into
the existing editor session, including collaboration and undo. Table structure
uses shared engine commands through native controls. See the
[approved table boundary](plans/2026-11-13-native-editor-foundation.md#native-table-views--approved-follow-up)
for supported editing and preserved read-only cases.

### The dependency rule

Layers 1–4 never import a host module. A layer depends only on the layers
below it, and the model depends on nothing but Foundation. The rule is enforced
by the package manifest: each target lists only the targets beneath it, so
`swift build` in this repository proves it. The editor builds and its tests run
without any host.

Two conventions in the editor come from the RelayMark specification, not from
a host: canonical entity references are `relay:entity/<id>` links, and durable
media sources are `/m/<id>`. The schema also includes the authored nodes
Relay's papers use (questions, data views, paper controls, agent suggestions);
they are part of the format, and the editor projects them. Authoring them is
host work.

## The editor

### Session

`RelayMarkEditorSession` edits one `RelayMarkNativeDocument`. It holds the
projected text, the selection, presence and marked input, and applies every
edit as a command on the replica. Typing, Return, joins, paste, marks, list
depth, tables, callouts, links and undo are its own commands.

Every change reaches the view as a splice where it can be located: typing
re-projects one text leaf, a structural command or a peer's update re-projects
the top-level nodes, list items or table rows it touched, and the view
replaces only those. Updates that wait on a missing predecessor are located
together once it arrives. A change that cannot be located re-projects the
paper.

A host builds its own commands on the same footing with `perform`: the
command runs as its own undo item, only the nodes its update touched are shown
again, and its update is saved.

### Seams

The editor reaches its host only through what the host gives it:

- **Persistence.** The session's `persist` closure receives each local
  transaction; `canEdit` decides whether the paper accepts input. These are
  required: an editor that silently dropped edits would be worse than none.
- **Peers.** The host hands each remote update to `applyRemoteUpdate`, and
  reads `selectionAnchors` and `refreshPresence` for awareness.
- **Services.** `RelayMarkEditorServices` carries the rest. Each service is
  optional; a missing one is a capability the editor does not offer.
  - `RelayMarkImageService`: accepted image types, size limit, and intakes for
    pasted or dropped images.
  - `RelayMarkPasteService`: rich clipboard HTML, which the host converts and
    inserts.
  - `RelayMarkLinkService`: fragment links such as `#heading`.
  - `RelayMarkPaperControlService`: paper buttons.
  - `RelayMarkImageStore`: images for media blocks, loaded by the host.
  - Collaborator colors and refused-input messages.
- **Hooks.** `onLinkedTaskItem` hands a checkbox bound to an entity to the
  host; `onHistory` reports the task items an undo or redo changed;
  `pausesHistory` holds undo while a host command is in flight.

Entity references and tags render from the labels stored in the document, so
the editor needs no reference service; previews and pickers are host UI built
on `selectedEntityReferenceID` and the session's insertion commands.

### Public surface

The public API is the session's state and command vocabulary, the SwiftUI
`RelayMarkEditorView`, and the service and intake types. The text-view
coordinator, table attachments, the attributed-text codec
and the splice machinery are internal; this repository's tests reach them
with `@testable import`. The session's contract with the text view
(`RelayPaperTextEditing` and its native edit commands) is `package` in
`RelayMarkEditorCore`, so only RelayMarkEditor uses it.

## Current native presentation

Apple's OS 27 `NSTextView` and `UITextView` own TextKit 2 rendering, input,
selection and hit testing. `NSParagraphStyle.textLists` owns bullets, numbers and
checklist markers. No Relay line-layout fragment, glyph rectangle reconstruction,
marker gutter, nearest-character scan or custom caret painting remains.

The canonical bridge retains Rust/Comrak, ProseMirror/Yjs meaning, UTF-16 range
mapping, incremental edits, marked input, persistence and semantic undo. Native
presentation is intentionally smaller than the web editor:

- Prose, marks, headings and lists use native attributed text. Continuation
  paragraphs in one list item remain plain; a final empty list marker appears
  after typing because the system drops zero-length paragraph list attributes.
- Subscript/superscript request the font's native vertical-position features.
  Missing glyph forms stay plain; no baseline offsets or font-size arithmetic.
- Callouts/questions use native background attributes, without custom borders or
  fragment padding. Inline atoms use system-measured SwiftUI attachment labels.
- Tables preserve the complete tree, spans, widths and embedded payloads, with a
  read-only system layout. Whole-table copy/delete and remote updates remain;
  cell editing and new-table creation are not offered by the native UI.
- Folding uses shared commands and the content-storage enumeration delegate.
  There are no painted chevrons or marker hit regions.
- Remote nonempty selections use TextKit rendering-only background attributes.
  Presence transport/state is unchanged. Remote caret/name drawing is deferred.
- Native Find handles its own decoration. Matches inside preserved tables select
  the whole attachment; cell-specific geometry is not synthesized.

The app keeps a single host-owned scroll view. Text sizing consumes UIKit fitting
sizes or TextKit usage bounds only at the sizing boundary. Native selection
segments/coordinate conversion support explicit caret reveal; selection-only
notifications never force measurement or scroll changes. The app's Actions menu
has stable placement, independent of selection-dependent available commands.

## Performance

Relay's engine and bridge work must stay bounded as papers grow. The edit-cost
tests compare 1 KB and 1 MB papers: the ordinary native edit gates allow at most
four times the small-paper cost plus 20 ms. They cover typing, Return and joins,
selection replacement, marked input, bold, list depth, paste, undo/redo, tables,
scrolling and peer edits. Existing engine/bridge thresholds remain unchanged.

Douglas accepted one documented exception on November 13: very large native
`NSTextList` layouts take roughly 200 ms per edit in both stock NSTextView and
STTextView. The large-list native test retains local/remote correctness,
convergence and no-whole-paper-fallback assertions at 1 KB and 1 MB, and reports
timings without asserting constant-time platform layout. Keep true native list
semantics; no per-item list fragmentation or custom markers to hide this limit.
See the [qualification evidence and decision](plans/2026-11-13-native-editor-foundation.md#large-list-performance-qualification--accepted-native-limit).

Tests run on macOS with `swift test` and on iOS through
`xcodebuild test -scheme RelayMark-Package`.

### Remaining whole-paper paths

None of these runs per keystroke.

- Opening a paper renders it in full.
- Committing marked input whose text spans several text leaves applies it
  through the whole-paper candidate path. Marked input inside one leaf, the
  usual case, is a leaf edit.
- On iOS, a paste the session cannot apply as a range command is validated
  against a whole-paper baseline before it is refused.
- Most block commands (list starts, tables, callouts, headings, task lists)
  validate on a scratch replica of the whole paper before they apply. The
  view still re-renders only their nodes.
- Applying a link or an offered mark (underline, highlight, superscript,
  subscript) projects the whole paper on a scratch replica.

## Patterns borrowed

From [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine),
keeping our document model rather than its Markdown storage:

- Work scoped to the blocks an edit touches, with the projection kept and
  updated per block instead of rebuilt.
- Removed: custom block-decoration fragments. Native attributes now supply
  the supported presentation; do not restore the historical layout machinery.
- Synchronous host services with no-op defaults; the engine ships no picker
  UI.
- Standard view-coordinate conversion remains valid integration; custom overlay
  geometry and placement are superseded by the November 13 rule.
