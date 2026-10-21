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

## Layers

| Layer | Swift product | Owns | Depends on |
| --- | --- | --- | --- |
| 1. Format | `RelayMarkSwift` | The RelayMark document and source codecs, the schema contract, HTML and clipboard import, editor commands, clipboard navigation plans and the causal write plan (relaymark-core through `RelayMarkEngine`) | Foundation, RelayMarkEngine |
| 2. Model | `RelayMarkModel` | The ProseMirror port: schema, nodes, slices, resolved positions, steps, transforms, commands | Foundation |
| 3. Collaboration | `RelayMarkNativeCollaboration` | The Yjs binding (`PMYXmlBridge`), the native replica, editing commands as Yjs transactions, presence, update footprints | 1, 2, `RelayMarkProseProjection`, YSwift |
| 4. Editor | `RelayMarkEditor` | The editor session, the TextKit 2 views for macOS and iOS, table attachments, layout fragments, Find, accessibility, and the services a host supplies | 1, 3, `RelayMarkProseProjection`, `RelayMarkCollaboration`, SwiftUI, AppKit/UIKit |
| 5. Host | outside this repository | Persistence and transport, authorization, product authoring and UI around the paper | 1–4 |

`RelayMarkProseProjection` and `RelayMarkCollaboration` are shared value types:
the attributed-text projection of a paper and the local transaction a host
saves.

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
coordinator, layout fragments, table attachments, the attributed-text codec
and the splice machinery are internal; this repository's tests reach them
with `@testable import`.

## Performance

Editing cost must not grow with the paper. The edit-cost tests compare a
1 KB and a 1 MB paper through the real text views on macOS and iOS: an edit
at 1 MB may cost at most four times its 1 KB cost plus 20 ms. The gates cover
typing, Return and joins, selection replacement, marked input, bold, list
depth, plain and rich paste, undo and redo, long lists, tables, scrolling, and
peers' typing and Return. They run on macOS with `swift test` and on iOS
through `xcodebuild test -scheme RelayMark-Package`.

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
- One custom layout fragment for block decoration.
- Synchronous host services with no-op defaults; the engine ships no picker
  UI.
- Overlay geometry converted through the view hierarchy rather than assumed
  from the text view's frame.
