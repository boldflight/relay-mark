# Canonical content edit evidence

The contract identity is `contract.json`; there is no separate operation version.
The live source owner sends `operation_contract: "content_edit"` and one object:

```json
{"before_snapshot_base64":"upstream Snapshot bytes","steps":[],"copies":[],"history":{"kind":"undo","owner_id":"stable actual manager UUID","reference":"accepted operation UUID","operation_ids":["accepted operation UUID"]}}
```

`history` is optional. A real command has at least one actual maintained
ProseMirror Step JSON, including its appended identity-repair steps. The sender
snapshot is an upstream Yjs/Yrs Snapshot, not a client-provided document. A host
reconstructs it exclusively from retained admitted state, refusing future clocks,
unowned deletions, pruned items or unresolved pending state. Step positions use
that sender document and successive actual StepMaps; peer shifts never reinterpret
those positions against the receiver's newer tree. `copies` contains bare
`{source:{runs},destination:{runs}}` selectors with exact type/item/count IDs.

`applyContentEdit` executes the actual maintained schema/model/transform.
`prepareContentEditWitness` prepares causal identity evidence. Elixir exposes
`RelayMark.ContentEdit.prepare_witness(runtime, evidence)` on the same isolated
bounded interpreter. Trusted evidence keys are `sender_before_snapshot`,
`sender_after_snapshot`, `before_snapshot`, `after_snapshot`,
`before_state_vector`, `operation`, `text_items` and `footprint`. The four trees
are maintained identity snapshots, including metadata where present. The sender
post-tree results from the exact original update applied to the admitted sender
state. `operation` has the internal discriminator `kind: "content_edit"`; it is
supplied by the host's already-validated outer wire owner.

Browser observers `captureContentEditSnapshot(root)` and
`captureContentEditFootprint(candidateDoc, originalUpdateBytes)` ship in
`priv/collaboration/content-edit-observer.js`, importing the host's one Yjs
instance. Yex exposes matching `xml_snapshot` and `update_footprint`. These are
read-only maintained-item observers. They require retained settled state, use
UTF-16 item clocks and bounded item traversal, and refuse unsupported/pruned
content. The footprint includes all original structs, declared deletion ranges,
retained deleted-item contents and the maintained candidate state vector. An
empty original update can obtain the trusted before-vector without a host decoder.

Preparation proves retained-range copies such as an Enter command's relocated
suffix by actual StepMap causality, source/destination identity, text and full
mark attributes. It rejects wrongly typed selectors, overlapping destination or
human IDs, omitted fresh text and newly allocated hidden/deleted text. It returns
`proven_copies`, `fresh_items`, `text_items`, the maintained result and
`unproven_mutations` with `requires_mutation_correspondence: true`.

**Preparation is not admission.** Complete non-text, format, topology and old
item-deletion correspondence, inserted-duplicate Slice source authority, and
owned inverse/history references still require the final maintained mutation
proof and the host's accepted receipts/authorization. A caller must not interpret
successful preparation or authored-document equality as permission to accept an
update. An unresolved proof is recoverable refusal, never a fallback editor or
an invented authorship claim. The actual Enter fixture records these remaining
obligations explicitly.


## Complete maintained command mutation correspondence

`replayContentEditMutation` and Elixir `RelayMark.ContentEdit.replay_mutation(runtime, evidence)` take private trusted `sender_state_base64`, `current_state_base64`, independently derived `writer_client`, internal canonical `operation`, and the maintained observer's exact original `footprint`. These are host-derived inputs, never a client-supplied pre-document or a new transport shape. Sender state comes from the checked retained sender frontier; current state is the exclusively owned admitted prestate. The original command update bytes remain immutable receipt/recovery evidence.

The adapter constructs ephemeral retained proof replicas, uses the same canonical maintained ProseMirror schema, preserves `initProseMirrorDoc` Node mappings, applies the actual Step sequence, and runs one `updateYFragment` transaction. It captures that transaction's update rather than a state-vector diff containing unrelated historical delete sets. Its update overlays the same retained current prestate before complete footprint comparison. Every fresh text/format/type/attribute/topology allocation and every effective deletion must correspond exactly. Invisible allocate/remove formats or metadata cannot pass by producing the same final document.

Already-retained original struct prefixes must match their authoritative IDs, parents, keys, content and ordering origins exactly before exclusion. Already-deleted ranges are independently excluded using the admitted prestate's maintained delete set. Only physical segmentation of adjacent string/JSON/Any payloads is normalized; identity intervals and complete contents remain exact. New allocations from multiple writer clients refuse. A deletion-only command has `writer_client: null`, because no allocated writer identity exists to authenticate or invent. The adapter creates no external identity or permission.

The pinned binding is `@tiptap/y-tiptap 3.0.9` with the same maintained Yjs fork and model/transform pins used by the browser. Browser modules import the host's single instances. The bounded QuickJS bundle uses a deterministic constructor-only random hook for ephemeral proof Docs: GUID is explicit and the independently observed writer is assigned before execution. This hook creates no saved/client identity, authentication key or external random value. Maintained UTF-8 and base64 codecs/polyfills handle wire representation; no custom CRDT decoder is introduced.

`complete_mutation_correspondence: true` means only that the original update corresponds to the actual maintained authored command. Source attribution still needs separately verified human/copy selectors and source authority. Paste/duplicate source claims require explicit retained source evidence rather than text equality. Owned undo/redo require actual maintained manager execution with accepted scoped command/group receipt metadata; semantic inverse Steps alone cannot restore original owned item identities and are refused by this adapter. These remain explicit gates, not alternate engines or completion claims.

`buildContentEditWitness` / `RelayMark.ContentEdit.build_witness` derive relocation-copy selectors and fresh human selectors from exact sender identities and maintained retained StepMap ranges. Input has the same four snapshots, trusted before vector, operation Steps and complete footprint as preparation, without claimed `copies` or `text_items`. It returns the preparation fields plus the derived operation. It does not classify arbitrary inserted Slice content as an independently proven generated-source copy.


Normal `group` and inverse `history` require `owner_id`, the immutable UUID of the actual maintained UndoManager. Actor, document, server join origin and tab identity are separate scopes. `bindOwnedHistoryOwner(manager, ownerID)` explicitly binds a genuinely restored browser manager; a new manager automatically receives a fresh UUID. Rebinding another owner is refused. Reconnect retains the same manager owner, while a new manager without its archive receives a new namespace. Trusted replay receipts must all match the candidate inverse owner; host ancestry and source export retain verified peers across all managers.

Native owned command groups use maintained StackItem metadata `{owner_id, operation_ids}`, an ordered unique UUID list. `RelayMarkNativeDocument(..., historyOwnerID:)` takes the existing persisted journal UUID. Native group/history carriers expose `ownerID`; checkpoint envelopes retain `owner_id`, and restoration into a different manager is refused before replacing its stacks. The first UUID is the source history reference; `OwnedHistoryEffect.operationIDs` exposes the exact popped group's membership rather than guessing by time or visible text. `performOwnedCommand(operationID:separateHistoryItem:_:)` keeps normal capture by default; an explicit semantic boundary closes a group. Checkpoint export preserves live capture. Restore retains all group metadata with the same document/items. `importRetainedHistoryState(_:historyOwnerID:)` is the finite saved `operation_id`/ownerless `operation_ids` metadata decoder, requiring the original journal owner from the host, returning original bytes, converted state and normalization records; unknown metadata stays unbound. Hosts preserve originals and verify scoped accepted receipts before treating any group as authoritative. `OwnedHistoryEffect.beforeSnapshot` and `steps` capture the actual inverse effect: the maintained synchronization full-document ReplaceStep is independently applied to the pre-tree and checked against the post-tree. It neither manufactures a CRDT inverse nor authorizes the owned group.

### Trusted maintained owned inverse replay

`replayContentEditMutation` uses the same private evidence owner for ordinary and inverse commands. History additionally requires `initial_state_base64` and bounded chronological `receipts` with exact `transaction_id`, `operation`, `update_base64` and server-derived `sender_state_base64`. Hosts independently authorize receipt scope, group prefixes/full membership, immutable bytes, ordering, completeness and undo/redo cycles before supplying them. These are private trusted inputs, never a client history blob or extra wire contract.

The proof merges peer catch-up under an excluded origin, executes every ordinary receipt through the actual canonical ProseMirror/Yjs writer, and applies its accepted update under one maintained UndoManager origin. Accepted explicit group boundaries reproduce StackItem membership without timer inference. Every accepted and candidate inverse executes that same maintained manager; supplied inverse Step JSON must agree with its actual result and its complete allocation/deletion/format/topology/field footprint. Sender frontier equality includes state vector, retained deletion coverage, full rich identity tree and authored metadata. Original receipts remain unchanged.

A successful inverse returns `owned_history_correspondence: true`, exact `restored_copies` selected from newly changed maintained `Item.redone` links, and `retained_field_changes` with actual allocated/deleted keyed or format item evidence. These supplement existing attribution owners; they are not source classification or permission. Unknown, unavailable, pruned, partial or oversized evidence refuses loudly. Inserted clipboard source authority, structural/field copy ancestry and remaining native structural Step producers remain separate acceptance work; successful inverse correspondence does not enable those capabilities.

Explicit ordinary `operation.copies` may bind retained source IDs to fresh text inside actual final `inserted_ranges` computed by maintained StepMaps. Source type, exact text/full attributes, actual insertion payload and disjoint destination allocations are independently checked; one source may legitimately be copied twice. The builder combines supplied Slice claims with automatic retained-range relocations and removes their exact destinations from human selectors. It never discovers clipboard source by text equality or authorizes its provenance.

Ordinary witness preparation refuses `history`. The same maintained receipt replay returns inverse `fresh_items`, empty `text_items`, and `proven_copies` selected from actual restored links; those destinations must cover every fresh inverse string exactly. Hosts bind declared wire selectors to this trusted result and immutable accepted source ancestry. A redo allocation cannot be silently relabeled human.

Browser `prepareOwnedCommandGroup(manager,UUID)` checks duplicates before mutation and closes only a pre-existing unbound or full 4096-receipt StackItem boundary. Native `NativeContentEdit.ownedGroup` freezes the actual same membership with update/UUID/snapshot/steps; nil remains unproven. Checkpoint/export never splits normal typing.


### Peer-safe owned branch deletion and immediate inverse observation

The canonical owner enables the same optional maintained UndoManager branch policy
on browser creation/adoption, native creation/history restore, and headless owned
receipt replay. The actual popped StackItem supplies its materialized deletion
candidates after redone traversal. A rootmost owned-created XML subtree with a
surviving item outside that exact inverse retains its XML/attribute skeleton.
Owned text and format items are still undone. This preserves paragraph identities,
peer-only widget settings/formatting, and complete table scaffolding without
retaining unrelated owned insertions. Obsolete skipped groups never supply the
wrong candidate set. Normal typing capture and checkpoint boundaries stay intact.

Browser `protectOwnedHistoryBranches(manager)` imports the host's single Yjs
owner and requires its actual-pop deletion context. Native enables Yrs
`preserve_changed_xml` through `YUndoManager.preserveChangedXML()` on construction
and archive restore. No additional history stack or inverse engine exists.

`captureOwnedHistoryObservation(doc)` returns a private branded same-owner token
before the real manager effect. `finishOwnedHistoryObservation(doc, token)` reads
newly changed maintained redone links and requires exact coverage of all fresh
visible inverse text. It returns `fresh_items`, empty human `text_items`, and
`proven_copies`; reused/foreign tokens refuse. It is an immediate read observer,
not an accepted receipt or a complete mutation proof. Server replay independently
verifies the accepted group, actual Steps/final tree and original full footprint.

The focused maintained forks are Yjs
`7f0471751846dc28455668289aeb610145f21321` (base `54193eaa`) and Yrs
`7296361aa996e9c42c23dbf92a829d3fbea87e34`; YSwift
`b5ea832069262aa4e14f5af43abaff29efdd6f66` binds the latter. The existing exact-base
Yjs preparation hook consumes the reviewed three execution changes from that
fork: materialize the context once per actual pop, pass it to the deletion filter,
and advertise its availability. Existing other hook changes remain distinct.
No `node_modules` edits are used. The npm release pin remains the actually
published `v13.6.33-relay.1`; publishing the committed fork and rebuilding consumer
artifacts are still operational follow-ups, not a fabricated package release.


The maintained `@tiptap/y-tiptap` selection correction is fork
`1e59316d56ba8acd45c6c0bb54f3c5478ccc8252`, based on released 3.0.9 source
`d5a57985f998e4d2d2f960a4bbc605cf466ad488`. Actual UndoManager synchronization
reads the saved relative selection from its actual `currStackItem`; inverse
metadata captures the selection before its Y-to-PM mapping changes. The obsolete
late Popped setter is removed. Saved history offsets are never resolved against
the unrelated current pre-document, while ordinary remote structural recovery
keeps its existing behavior. The full maintained 53-case suite passes, including
a named peer-retained redo cursor fault observed before the correction.

The shipped `y-tiptap-history-selection.mjs` prepares exact released ESM/CommonJS
bytes with those reviewed changes, refusing source drift or repeated patching.
Browser hosts must alias one prepared binding module across editor, plugins and
proof helpers; no dependency directory is edited. The package pin remains the
actually published 3.0.9. Fork publication and consumer rebuild are operational
follow-ups. The optional `fallow` binary was unavailable; lint, typecheck, bundle
and all behavior tests ran through the maintained `npm test` owner.


Native `captureContentEditObservation()` retains a branded same-owner pre-command
identity tree, maintained clocks and Snapshot bytes. After the actual command,
`buildContentEditWitness(observation,steps:update:explicitCopies:)` reads that
original update's full Yrs footprint and current identity tree, then delegates to
the same shipped `buildContentEditWitness` interpreter used by browser/server.
It derives automatic structural relocations separately from fresh human text;
explicit clipboard claims still require independent source authority. Foreign,
reused and omitted-footprint observations refuse. This immediate synchronous
preparation does not reconstruct accepted peers, confer scoped receipts, prove
all non-text mutations, or enable source capability by itself. It returns the
existing `requires_mutation_correspondence` gate unchanged. Native normal Steps,
actual inverse Steps and immutable group/history metadata are evidence from one
live owner, not alternative operation formats.

### Reviewed native authored recovery

`RelayMarkNativeRichEditing.replaceDocument(document:authoredAST:expectedSnapshot:)`
validates the complete shared AST and candidate before mutation, then writes its
actual full ReplaceStep through the same maintained body diff. When the envelope
changes, an actual maintained DocAttrStep (`attr: "relaymark"`) follows in the
same Step sequence, Yrs transaction and UndoManager. The doc attribute defaults
to `{}` and carries exactly the optional `frontmatter`, `annotations`, `resources`
and `meta` fields already stored in `Y.Map('relaymark')`. Explicit empty values
are preserved; keys absent from the new envelope are removed. Unknown fields,
null maps and non-JSON values are refused. No entity fields or authorization are
stored here.

The maintained browser binding reads this same map into the doc attribute and
writes it with the body in one transaction, including metadata-only commands
in an empty document. Its actual synchronization observer emits DocAttrStep
alongside body Steps. The undo plugin includes this map in the existing manager
scope. Exact mutation replay and owned receipt replay account for metadata
allocations/deletions, including hidden transient writes; final-value equality
alone cannot prove correspondence. `content-edit-metadata-history.json` retains
actual command/update/frontier bytes and peer-preserving undo/redo evidence.

Original recovery bytes remain the host's immutable evidence. This command does
not reseed an incarnation or flatten rich blocks. `Change.authoredMetadataChanged`
reports the envelope change; it does not authorize source attribution. Immediate
native witnesses remain preliminary and accepted scoped receipts/full mutation
correspondence remain required. Peer state, stale candidates, invalid grammar
and exact undo/redo are exercised by the named reviewed recovery regression.

### Retained identities inside semantic input

The source witness refuses a normal command when actual maintained insertion
intervals reuse pre-frontier text item identities. Value-only binding diffs can
otherwise keep a generated or peer item at the newly inserted position and
allocate an equal suffix, silently issuing no typed input. Actual identical
selection replacement can also produce no Yjs update. Three preserved fixtures
(`content-edit-repeated-human-input.json`, `content-edit-repeated-peer-input.json`
and `content-edit-identical-human-replacement.json`) capture these real faults.
This refusal uses maintained StepMaps and item clocks, never equal text to
relabel provenance. Canonical local commands now prepare their complete initial and appended Step
sequence before the maintained writer runs. `createContentEditWrite(before,
steps, after)` verifies the actual final PM tree and plans retained text solely
from maintained StepMaps. The browser binding receives this through
`ySyncOptions.prepareContentEditWrite`; native uses the same packaged planner
before its existing Yrs writer. Authoritative normal replay requires that same
causal context. Remote/read synchronization carries no local authoring intent.

Each original XML text branch retains its exact type and item ranges even when
several adjacent branches represent one marked text group. Equal values only
check already-mapped retained ranges; they never discover retained input.
Identical selection replacement therefore deletes the selected items and
allocates the actual inserted input. Construction of new documents groups
adjacent text runs into one XML text branch with full delta marks; existing
multi-branch checkpoints remain unchanged and admitted.

Actual step-mapped retained text can acquire changed formatting during a move;
copy proof requires that exact retained source/destination mapping plus the
complete admitted Step consequence. Explicit inserted Slice copies still
require original source text and full attributes. Shared full-footprint replay,
scoped receipts and owned history remain separate mandatory admission gates.
These focused writer checks do not enable a source capability or establish
published client integration.


Native media and paper-control insertion/removal, full authored control updates,
and inline reference/tag insertion/replacement return the existing `Change`
with actual maintained Replace/AttrSteps and sender Snapshot bytes. They route
through the same command commit, candidate admission and UndoManager; no raw
XML writer remains for these migrated commands. Original text suffixes are
eligible for identity reuse only when their exact per-branch causal delta
wholly retains them. This preserves saved adjacent inline-atom anchors when an
atom splits marked text, without treating identical replacement as retained
input. Browser and native bindings use that same per-branch condition; the
browser's maintained anchor reconciliation remains its existing owner.

Native attribute allocation follows the property order in the canonical editor
schema, including its defaults and null omissions. Swift dictionary order is
not an authoring input. The generated Swift schema carries that order for the
maintained binding and document construction. Exact native image, button and
tag command fixtures retain original state/update bytes, owned command groups,
SnapshotV1, selectors and complete mutation footprints. Earlier image/button
updates with different attribute clocks remain immutable refusal fixtures;
matching AST values does not establish mutation correspondence.

Native suggestion acceptance uses the same full source importer and an actual
maintained root-range ReplaceStep with a canonical rich Slice. It may contain
multiple paragraphs, nested lists, callouts, tables, media and form widgets.
The proposal's exact review/content checks still guard that range. Document
envelope metadata is refused for this body-fragment action rather than dropped;
a full reviewed document replacement expresses metadata through DocAttrStep.
The reduced one-block Markdown converter and its independent XML writer are
removed. Native accept/dismiss now return the same immutable Change evidence.

Reviewed native recovery appends selected full rich blocks at the actual PM root
end with the same maintained ReplaceStep owner. Current item identities and
metadata remain retained; newly copied block/heading identities are allocated
once and included in actual command/append-repair Steps. Exact retained proposal
bytes remain recovery evidence. The append API returns Change, including its
original update, before SnapshotV1 and executed Steps; it no longer has a raw
XML append writer. This producer evidence does not establish historical source
ancestry or authorize Enhanced admission.

Canonical source construction emits only schema-owned reference/tag attrs.
Null status/subtitle/color from historical presentation are recorded finite
snapshot removals, with original bytes retained. Non-null authored/presentation
values require retained evidence and are refused rather than discarded.

Maintained checkpoint hydration uses TextSelection.between on resolved
endpoints in the new rich document. The initial paragraph caret must not become
an invalid caret inside a list/table/callout container during force-rerender.
This selection-only correction allocates no document items or alternate writer.
Fork 6ffa324bbcc9f61037e5d26b47da123e67afc8f4 is reproduced byte-for-byte
by the existing exact-3.0.9 binding preparation helper; library publication and
client artifact rebuild remain separate acceptance.
