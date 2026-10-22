# RelayMark Git and Swift release notes

## Unreleased

- VoiceOver hears what the checklist item at the caret is: the paper view's
  custom content reads "Checklist item" with the value "Draft task", "Task" or
  "Not a task", on AppKit and UIKit alike, since the checkbox is drawn rather
  than read. `RelayPaperTextEditing` exposes `armedTaskDrafts` for it.
- The Swift editor makes checklist items draft Tasks as the web does. A typed
  `[ ] `, the Checklist command on an empty line and Return in an armed item
  arm one; leaving it, Return and ticking it finish it, and
  `RelayMarkEditorSession.onTaskDraftsFinished` hands the host each finished
  `RelayTaskDraft`. Hosts turn this on with `createsTaskDrafts`, and arm or keep
  items local with `armTaskDrafts(_:)` and `keepTaskDraftsLocal(_:)`.
  relaymark-core's task_draft jobs decide, reading an outline of the task items
  only; nothing runs while no draft is armed. A peer's edit that shifts the text
  never finishes a draft. `RelayMarkNativeDocument.taskTitleAnchor(itemPath:)`
  gives the Yjs anchor task creation sends, as y-prosemirror makes it.
  `onTypedShortcut` is gone; nothing used it.
- relaymark-core decides which checklist items are draft Tasks, for every
  editor, through three jobs. `task_drafts` lists the unlinked task items, with
  each item's title, its parent Task and an operation id derived from its block
  identity. `task_draft_arm` gives the armed set after an editing event: a typed
  checklist, the Checklist command (empty items only), Return in an armed item,
  explicit arm and disarm, and remote, pasted or history changes, which only
  prune. `task_draft_boundary` lists the armed drafts that Return, a caret move or
  a checkbox tap finishes. The armed set stays the client's own state, never the
  document's. The cases are in `spec/relaymark/editor/task-drafts-v1.json`, the
  first `cases` fixture in the conformance suite: the reference runtime
  (`src/task-drafts.js`) and the Rust engine run them by job name.
- The package links one Rust library. `RelayMarkFFI.xcframework` now holds
  `crates/relaymark-apple`, a megazord static library built from
  relaymark-ffi and yrs's binding `crates/yniffi` (vendored from Relay's
  yswift fork at the same Yrs revision), with one C module, `RelayMarkFFI`,
  under the separate Swift modules. YSwift's Swift sources are package
  targets, and the yswift package dependency is gone. Apps and test bundles
  that linked both former static libraries had two Rust standard libraries
  and failed on a duplicate `rust_eh_personality`. `Origin.origin` is now
  `Data` ([one Rust library on Apple platforms](docs/engineering/apple-rust-library.md)).
- Tag atoms accept normalized Relay tag names from any script (`#仕事`,
  `#ラーメン`, `#二〇二六年`): a lowercase, modifier or other letter, decimal
  digit or letter number first, then those, combining marks and `-`. `_` is no longer part of
  a tag name, matching the Relay server, which has always turned it into `-`. The JavaScript runtime, relaymark-core and the
  Swift native projection share the rule, checked against Relay's tag-name
  table in `spec/relaymark/conformance/tag-names.json`. ASCII names are
  unchanged.
- iOS: a tap in a paper places the caret and shows the keyboard again. The
  editor's task-checkbox tap now recognizes alongside UITextView's own taps
  instead of winning over them, which had left papers impossible to focus.
- `RelayMarkSourceCodec`, HTML and clipboard import and the attribute codecs
  run in relaymark-core, the canonical Rust engine the server also uses,
  through `RelayMarkFFI.xcframework` (uniffi; Apple silicon slices for iOS,
  macOS and visionOS, built by `scripts/build-swift-engine.zsh` and fetched
  from an `engine-<commit>` release asset). The bundled
  `document-source.js` is gone; output is byte-identical.
- Editor commands (lists, tables with `fixTables`, marks, blocks), step
  application, the causal write plan and clipboard anchor and heading plans
  also run in relaymark-core, a port of prosemirror-model/-transform/
  -commands/-schema-list/-tables checked against recorded JavaScript output.
  `content-edit-runtime.js` is removed, and no Swift product imports
  JavaScriptCore.
- Adds `RelayMarkAgentAuthorship.markDocument(_:runID:)`, which marks a whole
  document's text, code excepted, as one agent run's `ai_authored` text, for
  a generation a client builds itself.
- Adds `RelayMarkEditor`, the native TextKit 2 editor for RelayMark papers on
  macOS and iOS, moved from relay-swift: an editor session over one Yjs
  replica whose edits re-render only the nodes they change, tables as
  attachments, Find, accessibility, and `RelayMarkEditorServices` for a
  host's images, rich paste, links and paper controls. It imports no host
  module. Its tests and 1 KB/1 MB edit-cost gates run here
  ([native editor architecture](docs/editor-architecture.md)).
- Splits the ProseMirror port into `RelayMarkModel`, with no Yjs or UI
  dependency; `RelayMarkNativeCollaboration` keeps the Yjs binding.
- The Swift package's platforms are now macOS, iOS and visionOS 27.0, which
  the editor's TextKit 2 requires.
- Removes `RelayMarkAttributedTextCodec`, which parsed Markdown with Apple's
  `AttributedString(markdown:)` beside the canonical engine. Swift reads and
  writes RelayMark source only through `RelayMarkSourceCodec`.
- Clipboard HTML from other applications imports with the web editor's TipTap
  paste rules; a paste service also receives the clipboard's plain text.
- Writing a paper into the replica no longer holds every node's bridged copy at once.

- Removes the custom history and attribution adapters retired by Relay's
  October 18 standard collaboration decision (`adapters/collaboration`: text
  items, prose operations and lineage, history and placement lineage, format
  attribution, attribution records and the collaboration runtime), the Yjs
  history hook and y-tiptap history-selection patches with the test loader that
  applied them, their generators, probes, docs, tests and fixtures. Tests now run
  against stock Yjs and y-tiptap, as the web editor does.
- Removes the dead content-edit proof runtime: witness preparation, the
  command producer, mutation replay and its observer, owned command groups and
  history persistence, reviewed recovery, document patches and source
  identities, with their tests and recorded fixtures. The native editing
  runtime keeps HTML and clipboard import, the attribute codec, maintained
  commands, clipboard navigation plans and the causal write plan
  (`spec/relaymark/collaboration/content-edit.md`).
- Native editing takes the `ai_authored{run_id}` mark. The rich prose
  projection carries it as `RelayMarkAIAuthoredAttribute` (the run id), the
  native AST projection and `RelayMarkInline.runID` keep it, and the portable
  snapshot and typing-attribute validation accept it. Text a person types or
  pastes through `RelayMarkNativeRichEditing` or `typeText` never carries it, even inside
  agent text; Return, undo and peers' updates keep it.
- Removes the Swift collaboration proof machinery under Relay's standard
  collaboration plan: the JavaScriptCore Yjs replica
  (`RelayMarkCollaborationDocument` and `yjs-runtime.js`), the content-edit
  witness, owned-history groups and archives, identity/text-item capture,
  reviewed-recovery import and the source-reference codec calls.
  `RelayMarkLocalTransaction` now carries only its id, update and input intent.
  `RelayMarkNativeDocument` keeps a plain Yrs `UndoManager` for its own origin,
  with `editorCommand(separateUndoItem:)` grouping a typing burst into one undo
  item, and garbage-collects deleted content. `RelayMarkRelativeRange` replaces
  the replica's relative range type.

- Repairs canonical browser history restoration after Yrs sorts mark attribute
  keys, reconstructing the known producer encoding against the unchanged
  original archive hash. The detached repair preserves selective Undo/Redo and
  rejects unsupported legacy shapes and corrupted content or identity.

- Preserves insertion-time empty callout source in retained revisions by creating
  one deterministic empty body paragraph across JavaScript, Elixir and Swift.
  Existing callout appearance/title and strict AST/XML validation remain intact.

- Normalizes valid empty and nonparagraph-first CommonMark list items into the
  existing paragraph-first editor grammar without dropping source blocks or
  changing their IDs; preserves marked text surrounding hard breaks.
- Adds shared JavaScript/Elixir source-compatibility fixtures. Canonical contract
  1 and the Swift document model remain unchanged.

- Clarifies the cross-platform boundary: Agent Paper is the editable RelayMark
  document surface, while entity/page chrome and collection engines belong to
  hosts.
- Defines transient decision and confirmation controls as non-authored runtime
  UI until a portable directive is standardized.

## 0.6.0

- Adds a generic Swift `AttributedString` authoring bridge for readable
  RelayMark prose and canonical `relay:` entity links without moving host UI,
  entity resolution, or authorization into the portable adapter.
- Implements the portable `0.6.0-draft` contract while preserving valid
  pre-1.0 document meaning and public Swift adapter source compatibility.
- Advances the portable contract to `0.6.0-draft` with additive Agent Paper
  entity-reference, property-sheet, bound-data-view, and layout directives.
- Adds registry-owned renderer capability negotiation with deterministic
  fallbacks and canonical source serialization for the supported authoring
  subset.
- Adds portable semantic layer roles, anchors, placement, and missing-anchor
  fallbacks over already-authorized contributions, without ACLs or private
  resolved values.
- Adds shared Task, Person, Collection, and layered Meeting conformance
  fixtures plus matching generic Swift and Elixir value models.

- Makes the portable conformance-suite version the cross-runtime compatibility
  identity while allowing Git/Swift and Hex adapter releases to version and
  ship independently.
- Removes the private npm version and redundant nested Swift manifest so
  distribution versions have one owner per ecosystem.
- Adds a shared contract-version check and cross-runtime CI for the reference
  runtime, Swift adapter, and Elixir adapter.

## 0.5.3

- Lowers both Swift package manifests to iOS, macOS, and visionOS 26.5 so
  Xcode 26.5/Xcode Cloud consumers can import `RelayMarkSwift`.
- Leaves the portable RelayMark contract, schemas, fixtures, and Elixir
  implementation unchanged. The Git/Swift and Hex versions happened to
  coincide for this release; that is not a lockstep versioning requirement.

## 0.5.2

- Bundles the canonical projection-manifest schema alongside the document and
  diagnostic schemas.
- Adds `RelayMark.validate_manifest/1` so host applications can validate
  manifests without reaching into package filesystem internals.

## 0.5.1

- Publishes the generic Elixir adapter as the `relay_mark_elixir` Hex package.
- Bundles the canonical document and diagnostic schemas plus directive registry
  required to compile and validate documents without a repository checkout.
- Verifies packaged schema and directive bytes against the canonical
  `spec/relaymark/` sources before release.
- Adds Hex package metadata, generated documentation, and package-consumer
  verification while leaving the portable `0.5.0-draft` contract unchanged.

## 0.5.0

- Adds the normative `relaymark.agent_answer.v1` profile for bounded answered
  and insufficient-evidence papers with exact question identity.
- Adds canonical answered and refused Scripture Ask AST/manifest fixtures to the
  shared conformance suite.
- Enforces the profile's outcome, structure, evidence, and read-only boundaries
  with portable diagnostics in the reference runtime and both generic adapters.
- Adds reusable transported AST/manifest pair validation that rejects canonical
  projection, action, and answer-content drift.
- Adds a machine-readable SHA-256 receipt asserted by JavaScript, Swift, and
  Elixir against the same exact answered and refused fixture bytes.
- Makes Scripture Ask validation an explicit host action-context policy rather
  than document-inferred state.
- Makes every transported-pair gate run the canonical document shape and full
  directive semantics before projection, including nested Relay blocks.
- Rejects malformed UTF-8, non-scalar strings, and non-portable JSON before
  binding exact-byte digests; valid escaped non-BMP scalars round-trip across
  JavaScript, Swift, and Elixir.

Existing AST and manifest documents remain version 1. The profile uses existing
headings, paragraphs, claims, source bundles, evidence references, resources,
and manifest projections.

## 0.4.1

- Keeps the canonical Elixir JSON Schema 2020-12 validator compatible with
  host applications using Decimal 3.
- Preserves the RelayMark document-validation API and portable diagnostics.

## 0.4.0

- Adds the portable `relaymark.scripture_release.v1` resource profile.
- Adds lossless `relaymark.scripture_span.v1` evidence selectors with
  chapter-or-section coordinates and string verse labels.
- Projects immutable Scripture release identity and provenance through existing
  `relay.evidence_ref` manifest sources.
- Adds matching Swift and Elixir typed adapters plus one shared AST/manifest
  conformance fixture.

Existing AST and manifest documents remain version 1. Existing generic resources
and evidence references retain their 0.3 behavior.
