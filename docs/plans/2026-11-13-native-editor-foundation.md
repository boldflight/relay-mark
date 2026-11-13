# Native editor foundation sweep — November 13, 2026

Status: standing policy approved by Douglas; implementation plan proposed.
No renderer replacement, dependency adoption or feature removal has shipped as
part of this document. The wrong-row click and moving numbered-list marker remain
open. This plan supersedes a narrow marker-position patch and earlier advice to
reproduce web presentation with custom geometry.

## Objective and boundaries

Make ordinary editing dependable by assigning layout, drawing, selection and
hit testing to Apple TextKit 2 or a selected maintained library. Remove bespoke
geometry throughout relay-swift and relay-mark, not only the reported symptom.
The binding and product integration may be ours; the text primitives must not be.
The enforceable rule is in [AGENTS.md](../../AGENTS.md).

Retain the universal Rust engine and the canonical RelayMark/ProseMirror/Yjs
contracts shared with web. Markdown is an interchange format, not a replacement
live document. Keep scoped writes, stable identities, collaboration, permissions,
marked input, durable local work and semantic undo. Do not replace them with
whole-document Markdown round trips or the text view's independent undo history.
A lower native presentation capability is acceptable; data loss is not.

Preserve the app's one paper host and one vertical scroll owner. If a candidate
cannot support that composition with documented primitives, record the conflict
and propose a product-level change before implementing it. Do not compensate
with nested viewports, inferred document heights or copied web layout.

## Evidence, not a premature diagnosis

The app pins RelayMark `2e6ac02dcbdc48121f7ab1c1e1a0ee862b9d8277` at investigation
start. Its ordinary prose click falls through to `NSTextView.mouseDown`; no
custom I-beam hotspot was found. Isolated stock and actual Relay text-view
mouse-click probes agreed with TextKit line geometry. That does not prove the
painted glyphs in the real paper agree with that geometry.

Douglas reports fully loaded prose selecting the row above; his later screenshot
shows a numbered marker moving independently of its item and recovering on a
subsequent click. Existing code paints native text first, then manually draws list
markers, task adornments, disclosure controls and remote selections. Geometry
helpers include nearest-character scanning, inferred final-line rectangles and
explicit layout requests. Selection also schedules measurement/reveal work.
These are concrete audit targets; inconsistent layout timing remains a hypothesis,
not a verified causal diagnosis. No mouse-coordinate correction is proposed.

## Foundations researched

| Candidate | Actual role and evidence | Proposed disposition |
| --- | --- | --- |
| Apple TextKit 2 with NSTextView/UITextView | Native editing primitives; current app already uses them underneath its custom layer. [Apple layout API](https://developer.apple.com/documentation/appkit/nstextlayoutmanager), [viewport lifecycle](https://developer.apple.com/documentation/uikit/managing-viewport-layout-and-attachment-reuse-in-a-text-view-subclass). | Preferred baseline. Prove a small documented integration before adding dependencies. Native APIs can have defects; their availability alone is not acceptance. |
| CotEditor | A macOS plain-text application, not a multiplatform rich-tree editing package. Its current `LayoutManager` subclasses **NSLayoutManager** and `EditorTextView` installs it: this is a TextKit 1 path, not evidence for a TextKit 2 implementation. | Study its system-first scope and document/input ownership. Do not port its layout manager or assume all its custom machinery fits this rule. |
| swift-markdown | A cmark-gfm-backed parser and persistent value-tree API. It really does support trees; “we are a tree editor” is not a valid categorical objection. It does not supply a text view, caret, selection or collaborative editor. | Evaluate as a parser/reference tool only if it removes a demonstrated responsibility. Do not adopt it as the rendering fix or a second canonical parser. |
| STTextView | A reusable TextKit 2 NSTextView/UITextView replacement, with macOS/iOS implementations and custom rendering/selection internals maintained upstream. README describes a source-code-editor focus and GPL/commercial licensing. visionOS support and Relay's rich-tree/IME/undo/host integration are not established by this review. | Strongest directly relevant library candidate for a bounded comparison. Adoption would deliberately delegate primitives upstream, not eliminate custom machinery from the world. Require platform, maintenance, API and license fit; no purchase or adoption is authorized here. |
| RichTextKit | Wraps native text views for rich editing. Maintainer explicitly questions its future direction after SwiftUI attributed TextEditor support. | Not the default new foundation on this evidence; does not establish a qualified TextKit 2 path for this app. |

Sources checked November 13:

- [CotEditor README and licensing](https://github.com/coteditor/CotEditor): source Apache-2.0; image resources have separate terms. Pinned source tree `10a159bbef53b09eddbf2bc7457576b211ba9617`:
  [LayoutManager.swift](https://github.com/coteditor/CotEditor/blob/10a159bbef53b09eddbf2bc7457576b211ba9617/CotEditor/Sources/Document%20Window/Text%20View/LayoutManager.swift#L32),
  [EditorTextView.swift](https://github.com/coteditor/CotEditor/blob/10a159bbef53b09eddbf2bc7457576b211ba9617/CotEditor/Sources/Document%20Window/Text%20View/EditorTextView.swift#L192).
- [swift-markdown README](https://github.com/swiftlang/swift-markdown), [requested package listing](https://swiftpackageindex.com/swiftlang/swift-markdown).
- [STTextView architecture and scope](https://github.com/krzyzanowskim/STTextView), [license](https://github.com/krzyzanowskim/STTextView/blob/main/LICENSE.md).
- [RichTextKit maintainer notice](https://github.com/danielsaidi/RichTextKit).

The historical reason swift-markdown was rejected was not recovered from the
owning repository docs. Current source provides a better reason to avoid adding
it casually: `crates/relaymark-core/src/source.rs` already parses CommonMark with
**Comrak**, through the universal engine. Swift calls that engine through
`RelayMarkSourceCodec`. Audit custom transformations around that established
parser, but keep one canonical interpretation across runtimes. If a parser change
is warranted, propose it at that shared boundary with conformance evidence.

## Proposed implementation sequence

### 1. Inventory the whole stack and assign each responsibility

Produce a short keep/replace/defer table with the Apple API or upstream owner
for every remaining primitive. Inspect these existing owners first:

| Area | Current owners to audit | Required direction |
| --- | --- | --- |
| App composition | `RelayPaperShellView`, `RelayNativeAuthoredEditor`, `RelayReadonlyAuthoredPaper`, paper scroll host | One stable native editor, supported sizing/scroll integration, no app-side geometry repair. Include preview-to-editor selection handoff. |
| Native rendering/input | `RelayMarkEditorView.swift`, `CollaborationTextContainer`, `CollaborationTextView`, UIKit counterpart | Preserve standard text input and selection. Remove geometry synthesis and independent draw/layout cycles. |
| Geometry and adornments | `RelayTextGeometry`, `drawListMarkers`, task/disclosure/presence drawing, `RelayTextKit2Layout.swift` | Remove manual line/marker/caret positioning and nearest-character loops; native/upstream primitives or reduced presentation. No renamed geometry service. |
| Tables and other blocks | `RelayTableAttachment.swift`, attachment sizing, callouts, forms, image/media views | Use supported attachment/control primitives; otherwise preserve content with an explicit noneditable presentation. No new grid/paragraph layout engine. |
| Editor bridge | `RelayPaperEditor`, `NativeProseCodec`, `RelayMarkEditorCore`, projections | Retain semantic commands and canonical range mapping. Audit empty blocks, native attribute round trips, composition and selection affinity. No hidden replacement layout state. |
| Model and engine | ProseMirror model/transform port, Yjs binding, Rust source/content jobs | Preserve compatibility and upstream provenance; distinguish domain transformations from rendering. Avoid duplicating parser/model ownership. |
| Auxiliary surfaces | Read-only papers, previews, transcript/Enhanced layers, table-cell editing, Find, accessibility, remote presence | Same primitives and capability policy; no second editor path that quietly reintroduces the removed machinery. |

### 2. Qualify the smallest native foundation

Compare stock TextKit 2 integration against STTextView only if the stock baseline
has a concrete blocker. Evaluate standard rich attributed TextEditor as an Apple
wrapper option if it can expose the required incremental edits/composition and
selection without lossy whole-document synchronization; do not assume that it can.
Use a short representative paper with wrapped prose, empty paragraphs, numbered
lists, Japanese composition and a remote edit. Check real painting and clicks,
not only coordinates queried from the same layout state.

Record which APIs cover lists, attachments, resizing and the one-scroll host.
Select one foundation before implementation; no permanent dual renderer,
capability negotiation or local library fork. If upstream behavior fails, narrow
the native feature or raise the upstream issue instead of inventing coordinates.

### 3. Remove the custom layer and resolve the reported bug

Delete rejected rendering/geometry code from the owning RelayMark package and
simplify the app integration alongside it. Selection-only interaction must not
cause an unrelated document relayout, attribute rewrite or scroll repositioning.
Use supported layout lifecycle callbacks rather than forcing layout during paint.
Native lists are candidates, not a predeclared fix: qualify their behavior on the
current supported SDKs before removing the old marker projection.

Keep baseline prose, selection, typing, paste and IME reliable first. For each
advanced feature, state its native presentation and editing capability. An
unsupported node stays in the canonical tree and survives saves/remote changes;
if safe partial editing is unavailable, make that region or paper noneditable
with truthful UI. Do not silently convert structured content into plain text.

### 4. Verify our integration, not reimplement Apple's test suite

Use a small real-editing acceptance check on Mac and iPhone: the reported scrolled
prose/list case, resize, selection/drag, Japanese composition and undo. Add only
focused regression coverage for a demonstrated bridge defect; no new pixel
framework or exhaustive geometry harness. Keep existing canonical conformance,
collaborative-update, unsupported-node preservation and edit-cost checks relevant
to the changed bridge. Library adoption does not remove our responsibility for
those boundaries. Compile macOS/iOS/visionOS at the normal release checkpoints.

### 5. Ship and close the old paths

Qualify exact package source and app integration together, publish the package
only through existing release gates, update the app's tracked dependency pins,
and remove obsolete editor paths/docs/tests that describe deleted implementation.
No data/schema migration is assumed. Completion requires the moving-marker and
wrong-row-click acceptance, an explicit native capability list, and an inventory
showing no remaining bespoke text geometry. Merely adding a dependency, passing
compiler checks or moving the old algorithms into another file is not completion.
