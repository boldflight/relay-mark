# Native editor foundation sweep — November 13, 2026

Status: implementation qualified November 13, directly on `main` in relay-mark
and relay-swift; native-list performance exception explicitly accepted. Selected foundation: Apple's OS 27 TextKit 2
`NSTextView` / `UITextView`. STTextView is the strongest replacement-library
candidate, but no current Apple blocker justifies adopting it or maintaining a
visionOS fork. A selection-dependent app command strip was reproduced moving the
editor by 32 points after a host refresh; the stable Actions menu removes that
shift. The exact reported paper has not been exercised interactively, so this
evidence does not establish that every reported wrong-row symptom had one cause.
Douglas accepted the documented large-list limit on November 13. Publication
and app dependency-pin qualification proceed with that decision below.

## Final foundation decision

Apple's [WWDC26 TextKit session](https://developer.apple.com/videos/play/wwdc2026/370/)
and installed OS 27 SDK expose supported viewport lifecycle callbacks on both
framework text views. Apple's recommendation is to start with these framework
views. STTextView's rationale starts in February 2022; its heterogeneous feedback
list is not proof every listed defect persists on OS 27. No source found establishes
that Apple's current views are defect-free either.

A stock AppKit/TextKit 2 probe on macOS 27.2.1 rendered ordered lists, nested
bullets, a restart at seven, and an empty item using `NSParagraphStyle.textLists`
without inserting any marker characters. `NSTextList.includesTextListMarkers`
is false on this OS. Backing text stayed unchanged after actual mouse events,
and clicks selected the intended rows. Native line-fragment presentation ranges
can include markers, so canonical offsets must use content-storage/text-view APIs,
not arithmetic over line-fragment character ranges.

One current Apple limitation was reproduced separately in stock `NSTextView` on
macOS 27.2.1: at the final zero-length paragraph, assigning `typingAttributes`
containing `textLists` immediately returns a paragraph style with no lists;
setting `defaultParagraphStyle` does not change this. A newline-backed interior
empty list item renders its native marker, but the terminal empty item uses the
native caret without a marker until text is entered. The canonical empty list
item, typed text, save and undo remain intact; the marker appears after typing.
Do not add a placeholder character, custom marker, or replacement selection
engine to hide this limitation. Multi-paragraph canonical list items use a native
marker on their first paragraph and ordinary continuation paragraphs; TextKit
retains correct numbering for subsequent items without inferred indentation.

The additional library sweep found no stronger multiplatform rich-text candidate:
[STTextView](https://github.com/krzyzanowskim/STTextView) remains the fallback;
[SourceView](https://github.com/ChimeHQ/SourceView),
[CodeEditTextView](https://github.com/CodeEditApp/CodeEditTextView) and
[Runestone](https://github.com/simonbs/Runestone) target source/plain editing;
[RichTextKit](https://github.com/danielsaidi/RichTextKit) has an uncertain future
stated by its maintainer; newer Markdown editors add parser/layout responsibilities
we are removing. STTextView's package has no visionOS implementation route and its
GPL/commercial license needs a separate adoption decision for proprietary Relay
and permissively licensed RelayMark. No dependency or fork is being added.

Implementation decisions:

- System text views own prose rendering, lists, selection and pointer hit testing.
  Standard text lists render checklist markers; shared commands/accessibility
  remain their action surface. No independently hit-tested marker gutter.
- Remove custom block fragments, manual disclosure/cursor/chip painting, guessed
  final-line height and nearest-character scanning. Folding stays a semantic
  command using Apple's content-storage enumeration hook.
- Tables retain their canonical tree and range mapping. The subsequently approved
  native table implementation below replaces the initial read-only presentation.
- Native text sizing uses documented framework measurements at sizing boundaries,
  never in drawing or in response to a selection-only redraw. The paper keeps its
  host-owned scroll view. App title sizing follows the same policy.
- Comrak remains the universal parser; no swift-markdown. The surrounding paper
  remains TextKit 2; the explicitly approved table views use Apple's TextKit 1.

## Native table views — approved follow-up

Douglas approved one Apple TextKit 1 view per table on November 13, keeping the
surrounding paper on TextKit 2. No third-party table library or custom geometry.

Apple's Xcode MCP `DocumentationSearch` returned current `NSTextTable`,
`NSTextTableBlock`, UIKit table construction and AppKit `orderFrontTablePanel`
documentation. Framework-filtered queries reported "Asset is not installed";
unfiltered searches succeeded. The installed stable toolchain was Xcode 27.2.
Stock runtime probes on macOS 27.2.1 and iOS 27.2 confirmed that introducing
`textBlocks` switches the entire text view to TextKit 1, leaves independent text
views on TextKit 2, and does not switch back after table removal. Therefore each
table deliberately constructs its own `NSLayoutManager`/`NSTextContainer` stack.
The outer text view never receives native table paragraph attributes.

The implementation maps the existing canonical cells to `NSTextTableBlock`
attributes, including row/column spans. Apple handles layout, wrapping, selection,
pointer hit testing and caret placement. AppKit measurement uses native used/extra
line bounds; UIKit uses native `sizeThatFits`. The host keeps the vertical viewport.
`RelayNativeTableProjection` stores semantic UTF-16 ranges only, distinguishing
native cell-ending paragraph separators from canonical cell content. Unchanged
native block identities survive text edits; projection updates replace changed
cells, not the entire canonical table.

`RelayTableEditor` sends admitted native typing, paragraph edits, marked input,
formatting and undo/redo through the existing `RelayPaperTextEditing` owner.
UIKit also inserts text without calling its should-change delegate on some
`UITextInput` paths. The adapter adopts the exact character range and length
delta reported by `NSTextStorage`, mapped before updating presentation offsets,
through those same engine commands. It does not diff the rendered table or infer
text from geometry. Native Select All's final paragraph separator maps to the
last canonical cell endpoint, so structural commands use the visible selection.
Peer changes use the existing canonical splice and anchored-selection paths.
Structural controls use the shared table command catalog on every platform.
The AppKit table panel cannot bypass that owner with independent mutations.
No RTF/Markdown round-trip, second document state, or native undo history owns
durable edits.

Separate text views have separate selection boundaries; continuous selection
from outer prose into individual cells is not synthesized. Text replacements
crossing native cell separators are refused; shared structural commands operate
on canonical selected cells. Tables containing attachments that require TextKit 2
view providers remain read-only with native text labels; all canonical nodes are
preserved. Ordinary table text and supported inline marks are editable.

The final focused Mac run passed 28 table, TextKit-boundary and command tests,
including native typing, canonical/peer convergence, collaborative undo,
active-cell peer caret mapping, marked-input commit, structural commands,
native hit testing, Select All and restoration of unsupported native-only
formatting. Four mounted iPhone tests, including replacement/deletion/Return
cases, passed using an actual window and first responder. The complete Swift
package run passed its functional checks; three existing prose timing gates
failed in that run and all three passed in a fresh process with unchanged
thresholds. The timing failures were not reproduced in that fresh process;
their precise cause was not established.
Logs: `/tmp/relay-native-table-tests-{full,latest-focused,perf-rerun}.log` and
`/tmp/relay-native-table-iphone-adoption-tests.log`.
The app's full package suite passed 1,621 tests against the local candidate.
Final candidate Release builds passed for macOS, iOS and visionOS, using the
stable Xcode 27.2 toolchain and isolated caches. App publication also verifies
the tracked dependency pin against this published source without an override.

Actual mouse dispatch was exercised in the standalone stock AppKit probe.
The package suite checks Apple's native hit target and insertion index: sending
tracking events inside Swift Testing caused its helper to exit before reporting
a result, so that incomplete run is not counted as a pass. These checks do not
establish manual acceptance in Douglas's original paper.

The preceding stock UIKit probe found a border overlap when mixing
prose and tables in one text view; a table-only view sized by Apple's fitting API
contained the complete table without compensation.

Owning Apple APIs: [NSTextTable](https://developer.apple.com/documentation/appkit/nstexttable),
[NSTextTableBlock](https://developer.apple.com/documentation/appkit/nstexttableblock),
[UIKit attributed-string tables](https://developer.apple.com/documentation/uikit/adding-tables-to-attributed-strings),
and [NSTextStorage edit notifications](https://developer.apple.com/documentation/appkit/nstextstorage/didprocesseditingnotification).

## Large-list performance qualification — accepted native limit

The full native edit-cost suite exposed a current platform limit after adopting
`NSTextList`: a roughly 1 MB contiguous bullet list takes about 274 ms for local
typing and 281 ms for peer typing on macOS 27.2.1. The corresponding small-list
operations take about 3.4 ms and 0.55 ms. Ordinary 1 MB prose remains about 2 ms.
The former `large <= small * 4 + 20 ms` native-list gate failed for several
large-list operations. Douglas explicitly accepted this platform limit: keep
Apple's native list semantics and replace that gate, retaining the engine/bridge
correctness and performance checks. The native-list test now runs the same
local/remote operations at 1 KB and 1 MB, checks canonical convergence and zero
whole-paper fallback, and reports timings without claiming size-independent
native layout. No other performance threshold is relaxed.

Independent scratch probes reproduced the scaling without Relay. A stock
`NSTextView` backed by TextKit 2 and native `NSParagraphStyle.textLists` took
about 189–200 ms per insertion in the large list, versus 0.66–0.71 ms in the
small list. Forcing the pending native viewport layout after a direct storage
mutation took 191–204 ms versus 1.4–1.6 ms. The storage mutation itself took
1–3 ms; selection, typing-attribute access and edit notifications remained small.
Thus native list layout, rather than Relay's canonical document adapter, is the
reproduced bottleneck. These are observed measurements on this machine, not an
Apple performance guarantee or an assertion about every OS 27 release.

The same experiment with upstream STTextView commit
`c7d519318b06ebb7a99a641e4aa8831105d3b7d4` took 179–195 ms for insertion plus
layout and 178–194 ms for native viewport layout in the large list, versus
roughly 3 ms and 2.4 ms in the small list. Plain 1 MB prose remained below 2 ms.
STTextView therefore does not resolve this demonstrated blocker: it uses the
same TextKit 2 list primitives. No replacement dependency was added.

A scratch experiment using separate one-item native lists reduced the cost, but
that approach was rejected: fragmenting one canonical list into unrelated native
lists changes system list semantics and accessibility grouping. Do not adopt it,
bypass native insertion or restore custom markers to conceal the platform limit.
Douglas selected “Keep Apple; accept this documented limit.” The accepted
exception is specific to native layout of very large lists, not Relay's engine,
bridge, ordinary prose, table or other edit-cost requirements.

Local evidence (scratch, not committed product code):
`/tmp/relay-native-foundation-mark-full.log`,
`/tmp/relay-stock-list-cost.swift`,
`/tmp/relay-sttextview-cost/Sources/Probe/main.swift`, and
`/tmp/relay-sttextview-cost-results.log`. Both standalone probes used six samples
per condition, native 800 × 600 viewports, and compared matching 1 KB/1 MB inputs
with and without distinct paragraph metadata. ST insertion measurements include
pending view layout, so deferred rendering is not counted as completed work.

## Confirmed integration defects removed

- A selection-dependent app command strip shifted the editor by 32 points. The
  stable Actions menu keeps that host geometry unchanged.
- Rendering a partial ordered-list update seeded a new native list from that
  slice's first ordinal. Bolding the second item could reset the next item's
  native number to one. An editor-owned semantic context now preserves the
  complete canonical list's identity and start across partial updates; separate
  editors do not share mutable presentation state.
- SwiftUI fitting queries could leave the live AppKit text view at a rejected
  72-point proposal inside its actual 374-point container. The fitting boundary
  now restores the live native frame and completes native layout at its actual
  width after a rejected sizing proposal. No second text measurement or
  replacement geometry is introduced. Stock AppKit caret reveal did not reach
  the host-owned parent scroll, so the thin adapter consumes TextKit selection
  segments and uses native view-coordinate conversion and scrolling.
- Attachment activation used an insertion-boundary lookup, which could identify
  the position after a button. Native character hit testing plus native segment
  containment now identifies the attachment and rejects adjacent whitespace.
- Sub/superscript styling used hand-calculated baseline offsets and font scaling.
  It now requests Apple's vertical-position font features at the existing font
  size and traits. Glyph availability belongs to the font; missing forms use
  ordinary native presentation, with the canonical mark preserved. See Apple's
  [font feature registry](https://developer.apple.com/fonts/TrueType-Reference-Manual/RM09/AppendixF.html).

## Local verification checkpoint

Initial implementation qualification used an isolated workspace/package override
pointing at the exact RelayMark source. Publication then updates the app's tracked
lockfile to that published main revision and verifies the remote dependency graph
without overrides. The app's remote-main declarations remain unchanged.

- Xcode 27.2 / Swift 6.4.2 unsigned Release app builds passed for macOS, iOS and
  visionOS against the local override, including the final list-context,
  script-font and native fitting lifecycle corrections. All three final
  compiler runs completed successfully.
- Before the product decision, RelayMark passed with the native-list timing
  test explicitly excluded. After acceptance, that test is replaced by the
  large-list correctness/diagnostic test described above. The publication run
  passed the complete suite with no exclusions. The final 1 MB bullet-list
  measurements were roughly 234 ms for typing, 238 ms for peer typing and
  295 ms for Return; these are diagnostics, not a new performance promise.
- Native iPhone simulator content sizing, marked input and actual insertion
  passed; the agent-owned device was shut down. These are integration tests,
  not signed-in production or manual reported-paper acceptance.
- The app's hosted-editor regression failed on the old command strip with a
  32-point shift and passed with the stable menu. Title tests verify native
  fitting rather than a parallel text measurement.
- App integration: 1,547 non-UI tests passed in the full run; all 72 UI tests
  passed in the final UI rerun after the fitting fix. This includes unchanged
  resize acceptance, stable host positioning and read-only fragment navigation.
  Attachment activation tests use native hit-test data and validate dispatch;
  they are not claimed as physical pointer automation.
- The final RelayMark run passed every included suite, including semantic
  render-equivalence, list identity, checked-empty-task input, script-font
  features, content fitting and unchanged prose/table/indentation cost gates.
  These checks remain required alongside the replacement native-list test.
- Offline CLI action verification passed 28 contracts. App-owned sync and paper
  verification passed the repository assertions for schema 40.0.0, three paper
  fixtures, scoped authority and durable purge behavior.

Local logs are under `/tmp/relay-native-foundation-*`; they are transient evidence,
not checked-in test fixtures. No production app, account or stored paper was
changed by testing. The exact reported paper has not been manually rechecked.
The foundation rules are recorded in both repositories' AGENTS.md files and the
requested memory notes. The initial publication hold is lifted by the explicit
performance decision above. Temporary package-edit symlinks are removed from the
app checkout; isolated verification caches remain under `/tmp` for follow-up.

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
| STTextView | A reusable TextKit 2 NSTextView/UITextView replacement, with macOS/iOS implementations and custom rendering/selection internals maintained upstream. README describes a source-code-editor focus and GPL/commercial licensing. visionOS support and Relay's rich-tree/IME/undo/host integration are not established by this review. | Strongest directly relevant library candidate for a bounded comparison. Adoption would deliberately delegate primitives upstream, not eliminate custom machinery from the world. Require platform, maintenance, API and license fit before any later adoption. |
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

## Implementation sequence

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

Publication qualification: complete Swift suite passed without filters or skips
(`/tmp/relay-native-foundation-mark-accepted.log`), following the previously
passed macOS/iOS/visionOS builds of unchanged production source. No Rust, web,
Elixir engine binary, canonical contract or schema changed in this refactor.
