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


## DOM-free command production

`produceContentEdit(input)` and Elixir `RelayMark.ContentEdit.produce(runtime, input)` execute one actual command through the same maintained ProseMirror schema, `createContentEditWrite` causal plan, `updateYFragment` writer and protected UndoManager. Input is exactly `{state_base64, writer_client, transaction_id, owner_id, steps}`. The host admits the retained state and supplies fresh server command and manager UUIDs; these inputs are not client authority. Steps carry their original canonical IDs, marks, atoms, structure and `DocAttrStep` metadata. Invalid closed content, missing IDs, unsupported steps and no-op transactions fail without producing a receipt.

The result contains the actual `update_base64`, retained `state_base64`, `authored_document`, `text_items`, and current `content_edit` `{before_snapshot_base64, steps, copies, group}`, plus independently replayed mutation proof. The snapshot precedes the actual mutation, copies come from maintained StepMaps and original item/type identities, and the group comes from the actual manager event. Metadata and body mutate in one transaction. A supplied writer can emit a pure deletion with no allocated structs; the independent proof then observes no fresh writer.

This is one fresh maintained manager invocation, with one actual command group. It does not claim continuity with another client's persisted undo history. The host supplies its authorized document/body/source envelope, applies provider/source policy, and independently admits the original returned update through its existing receipt owner. Production is not authorization, human-source classification or persistence. No mounted browser, new editable replica, parallel converter or client-supplied footprint is required.


## Reviewed target planning and maintained owned-history checkpoints

`produceDocumentPatch(input)` and Elixir `RelayMark.ContentEdit.produce_document_patch(runtime, input)` accept the same trusted producer identities and retained state, replacing `steps` with a complete canonical `target_document`. The existing owner reads the admitted retained PM tree, validates the full target with the shared adapter/schema, plans maintained Fragment differences and Transform replacement, and includes one DocAttrStep when authored metadata changes. It executes through `produceContentEdit` and refuses unless its complete result equals the reviewed target. This is an ordinary target planner, not an independent body writer or permission grant.

`createOwnedHistoryCheckpoint({initial_state_base64, receipts, current_state_base64, owner_id})` and `RelayMark.ContentEdit.checkpoint_owned_history(runtime, input)` reconstruct the actual maintained UndoManager from host-authenticated chronological same-owner receipts, then overlay the exact trusted cut. The returned data-only checkpoint contains `owner_id`, observed `state_vector`, real `undo_stack`/`redo_stack` insertion/deletion interval sets and groups, exact `redone` links, and retained item ranges. It contains no document state or archive of original updates. The host persists its exact digest, scope, cut and existing receipt-coverage binding; these values are never client authority.

Checkpoint export at subsequent cuts and the existing inverse replay API accept exactly one private reconstruction basis: `initial_state_base64` plus receipts, or this authenticated `checkpoint` plus only post-cut receipts. Genuine maintained stack items are initialized through the narrow fork hooks `exportHistoryStacks`/`restoreHistoryStacks`; all actual item IDs, redo links, scoped deletions and group metadata remain intact. Checkpointing/export does not end a natural typing group. The adapter bounds the checkpoint to 32 MiB, retained items/edges to one million, and each stack to the existing 4096 replay group bound; resource refusal retains original host work.

A sender frontier earlier than the cut remains valid when later advancement was peer-only and the complete owned stack exists in that retained sender state. The package proves actual offline Enter undo across a later peer paragraph, a second cut using only its first checkpoint plus the original post-cut undo receipt, cold redo with restored generated identities, and natural marked typing continuation after a cut. Omitting a later already accepted same-owner command is a strict conflict; no synthetic rewind is performed. Root authorization must still authenticate original command membership and all supplied suffix receipts.

The exact maintained Yjs fork is `65fe85d366beba7d28bda1367cd6a35e592c620f`, based on the prior scoped history fork. The two new hook bodies in the preparation owner match the committed fork byte-for-byte. The full prepared module SHA256 is `86e2d731c8426e3c5ef01d4b59a7157bb8ada19cbdb9039a1849f4fb96117761`. The published npm pin remains truthful; fork publication and client artifact rebuilds are unfinished operational acceptance. This package proof does not advance a server attribution baseline or enable source/history delivery.


Canonical form AST output includes explicit null for unused numeric settings:
question `points`, `min`, `max`, and option `points`. Maintained XML may omit
these unused attrs; the shared XML projector supplies the same PM defaults.
Configured numeric values and every JSON value in authored metadata/settings,
including explicit nulls, remain exact. Original XML/update bytes are unchanged.

Owned inverse allocation uses the original retained item identity order:
`client` ascending, then `clock` ascending. Both maintained UndoManager owners
sort the actual redo candidate set before execution and retain that same set for
recursive parent and redone dependency checks. A required parent is still
restored recursively before its child. Neither hash-set order nor serialized
DeleteSet map order may assign fresh item identities to different authored
fields. Exact candidate footprints remain mandatory: earlier random-order
native inverse bytes are retained recovery evidence and are not rewritten or
accepted merely because their final visible content matches.

## Reviewed complete-block recovery regions

`prepareReviewedRecoveryWitness` uses the current maintained Step/identity owner
for an explicitly reviewed complete-block root-end append. Its evidence is the
seven normal witness fields plus `archive_identity_snapshot` and
`reviewed_document`. The internal operation additionally carries
`reviewed_recovery` with exact archive/review digests, ascending original
`block_indices`, a fresh `target_guard`, and optional authenticated `donor_cut`.
The host authenticates those bytes, scope and donor cut; digest syntax checks in
this library confer no authority.

The exact append Slice ordinal binds each original archive block. The proof
checks its complete props, marks, atoms and child order, allowing only newly
allocated `relaymarkId` values. Following AttrSteps or the exact maintained `Transform.setNodeMarkup` output
(ReplaceAroundStep for containers, ReplaceStep for leaves) may repair null or
duplicate imported IDs. The witness compares the original Step to the maintained
command with only `relaymarkId` changed, preserving type, marks, content, other
attributes and exact gap/Slice geometry. Unique-ID rewrites, old-node repairs,
other attributes, open Slices, content replacements and metadata changes refuse.
Target document metadata remains unchanged; donor metadata remains review evidence.
Reviewed-document hashes use the shared recursive canonical JSON encoder: valid
Unicode keys sort by UTF-8 binary order, preserving decomposed keys and explicit
values. Locale sorting and UTF-16 code-unit sorting are not wire encodings.
Previously retained original JSON bytes and receipt hashes remain immutable.

The result's `recovery_regions` entries contain original XML `archive_path`,
UTF16 `archive_offset`, `count`, and a bare destination selector. They account
for all fresh imported text, disjoint from ordinary typed/copy destinations.
This first lane has empty `text_items` and `proven_copies`; it never discovers
source by text equality or asserts donor human ancestry. The backend separately
maps only independently authenticated donor-human intervals into these regions;
unproven remainder stays unknown/generated. Normal command/reference semantics
are unchanged. Commands retain their 131072-unit and 4096-run guards.

`complete_recovery_correspondence` proves this structural allocation mapping,
while `requires_mutation_correspondence` and `requires_recovery_authorization`
remain true. Complete original-update replay, immutable accepted receipts, current
authorization and reverse donor-erasure checks remain necessary for admission.
The normal witness entry points refuse `reviewed_recovery` without this regional
proof, rather than classifying all imported allocations as typed human text.

Swift's `buildReviewedRecoveryWitness` consumes the existing same-owner immediate
observation token only after successful proof, and returns exact bytes for the
same immutable `NativeContentEdit.witness` carrier. It adds no replica, archive,
source store, UndoManager, wire version or alternative editor.


### Reviewed recovery candidates and human destination mapping

`reviewedRecoverySourceSelection({archive_identity_snapshot,recovery_regions})`
returns bare imported source candidates only, bounded by the unchanged command
extent/run limits. The authority owner independently authenticates/classifies
those candidates against the final archive-visible identities after exact donor
and pending-journal reconstruction. It must not substitute the complete earlier
donor-cut human selector: pending deletions can remove those identities.

`mapReviewedRecoverySelection({archive_identity_snapshot,recovery_regions,source_selector})`
returns `{destination:{runs}}` for only that independently authenticated human
subset. Exact source item/type identities resolve to original path/UTF16 offsets,
which intersect the recomputed region's ordered destination runs. Identical text
at another path is never searched or inherited. Missing/forged identities,
Unicode splits, overlapping source/destination regions and mismatched extents
refuse. Empty authenticated human input produces empty destination; remaining
imported allocations stay unknown until the backend separately proves ancestry.
These read helpers do not authenticate archives, issue references, or grant human
or inverse authority. Full original mutation replay and independently recomputed
region accounting remain mandatory before admission.

The optional maintained manager `retireHistoryStackItems` operation is a private
trusted transition, not a document command or receipt credential. The scoped
`retireOwnedHistoryGroups(manager,groups)` adapter requires exact current owner,
reference and complete ordered membership before invoking actual whole-stack
removal. The maintained release owner preserves survivor insertion/deletion,
redone and ancestor keep reachability, leaves needed global redone links intact,
and ends capture at the explicit erasure boundary without changing document
bytes. Source-classification closure and whole-group capability retirement are
distinct: removing a mixed group's undo ability does not itself erase a later,
independently authenticated human source fact.


`retireOwnedHistoryCheckpoint({initial_state_base64 OR checkpoint,receipts,
current_state_base64,owner_id,groups})` uses the existing receipt replay owner to
reconstruct every provided command, compare complete retained cut identity, and
validate exact whole groups before invoking that maintained transition. The
result `{checkpoint,retired_groups,undo,redo}` captures the surviving actual
manager; it contains no raw update archive. Invalid original Steps, owner or
membership refuse. This input is private trusted evidence: the host freshly
checks document/incarnation/actor/owner/cut/state digest, immutable receipt
bytes and erasure dependency closure. An owner UUID alone grants no actor or
account authority. Scoped native `retireOwnedHistoryGroups` validates the same
full membership before invoking the matching Yrs owner; archive restore retains
survivor redone/ancestor reachability and new authoring remains possible.

### Qualified recovery dependency cuts

`planReviewedRecoveryRetirement(input)` is a private read-only operation over
freshly authenticated original receipts and the same retained manager owner.
Elixir exposes `ContentEdit.plan_reviewed_recovery_retirement(runtime,input)`;
Swift exposes `RelayMarkContentEditCodec.planReviewedRecoveryRetirement(Data)`.
The host must authenticate every reviewed association's exact original command
JSON, update, issued outer reference digest and document/incarnation/actor/owner.
An association digest or actor string supplied to this operation is not a
credential. Import seeds must include **all** original fresh allocations,
including types, maps, attributes and formats. The operation independently
compares their union to the observed original command's fresh allocation union.
The host also recomputes the reviewed regional proof; dependency planning does
not authenticate archive hashes or grant donor authorship.

Input has `binding:{document_id,incarnation}`, `current_state_base64`,
`current_cut:{through_update_id,state_sha256}`, `expected_manager_scopes`,
`manager_contexts`, and `imports`. Each scope is `{actor_id,owner_id}`. Each
context has that exact pair, `initial_state_base64` **or** `checkpoint`, and the
existing chronological receipt objects
`{transaction_id,operation,update_base64,sender_state_base64}`. The independently
authenticated roster must equal the contexts exactly. It is not derived from
Yjs client IDs, origins, or caller stack metadata. Each import has
`receipt:{transaction_id,transaction_sha256,update_sha256,issued_reference_sha256,
actor_id,owner_id}` and `imported_items:[{item:{client,clock},count}]`.

Cold input additionally supplies `dependency_checkpoint` and the exact paired
`checkpoint_state_base64`. The summary is
`{binding,through_update_id,state_sha256,manager_scopes,associations}`. Each
association contains its original `receipt`, `imported_items`, closed
`capability_items`, and typed `source_items:{runs}`. Existing managers restore
from checkpoints at that exact state frontier; newly joined authenticated
managers may supply an initial basis. Scope, cut, state digest, retained items,
source type IDs, and aggregate budgets are checked before replay. Missing or
mismatched pre-cut evidence refuses completeness and requires the host's
supported recovery path. It does not justify disabling all future history.

The existing qualified checkpoint's **whole sidecar digest and coverage** must
commit these summary bytes, including every association receipt and interval.
A state digest alone does not authenticate a dependency summary. The existing
host stores it inside that sidecar, never in another archive or provenance
store. Pruning original rows is permitted only after this qualified transition;
no raw updates are added to the summary. Repeated cuts retain each import's
closed evidence separately. Erasing import A must select its exact issued
receipt association and preserve unrelated import B. A naturally mixed manager
group can require whole-group retirement without joining their source facts.

Capability closure includes effective deletions, exact copied subtree type and
field allocations, original field/format predecessors and maintained redone
links. Stable subtree identity and actual Step placement qualify copied field
correspondence; equal text or attributes alone do not. Parent, origin and
right-origin anchors alone do **not** propagate capability dependencies.
Independent adjacent or shared-parent typing survives. Source closure propagates
only imported text, independently verified copies and maintained text redone
links, so independent typed facts remain authenticated even when their mixed
StackItem's undo capability retires.

Output contains per-association `{receipt,retirements,source_dependencies}`, the
next `dependency_checkpoint`, diagnostic `dependency_edges`, and
`complete_dependency_correspondence:true`. Retirements name actual whole groups
under their exact actor/owner pair; they are consumed by the existing maintained
retirement operation, never by filtering serialized stacks. The planner changes
no document or persistent manager. Input and output are bounded to 32 MiB, with
one million aggregate interval records and bounded graph work. Existing receipt,
command, worker memory and timeout limits remain unchanged; unavailable evidence
or resource refusal is explicit. Production erasure, authoring continuity and
host digest persistence require their own integrated acceptance evidence.


### Accepted reviewed append replay

`prepareRetainedReviewedRecoveryWitness` accepts the same seven trusted
snapshot/vector/operation/original-footprint fields as normal preparation, plus
`regional_context: {recovery_regions, human_destinations}` from the existing
host-authenticated original issued association. The Elixir facade is
`RelayMark.ContentEdit.prepare_retained_reviewed_recovery_witness/2`.

This target-only read shares the exact root-end closed append and allocator-only
repair validation with fresh recovery preparation. It verifies original region
extent bounds, selected-block ordinal placement, contiguous fresh typed
item/type destinations in both sender-after and locked-after state, complete
fresh allocation coverage, and a disjoint typed human subset. Original regions
are preserved. Ordinary typed and copy selectors remain empty, and independent
complete maintained mutation replay is required before classification.

The host must bind the private context to the original immutable command UUID,
annotation, update/JSON/receipt digests, target namespace, actor/owner and covered
receipt history. Target-only replay cannot reauthenticate archive paths or donor
content and does not claim to. The original issued association authenticates
those pointers; no archive reread, text-equality provenance search, annotation
stripping, or producer complete flag substitutes for that authority. Missing or
mismatched private context refuses; normal preparation remains unchanged.


### Imported heading navigation correspondence

`planReviewedHeadingNavigation({archive_document,before_document,block_indices,steps})`
reads canonical PM trees and actual closed root append/replacement Steps.
`paperDocumentDestinations` resolves original explicit Anchor names first, then
heading names by source tree ordinal. Valid authored heading names are retained;
nullable names use deterministic PM-authored text slugs, excluding resolved
inline entity labels. Duplicate headings receive original ordinal suffixes.
Original names never discover imported nodes by text equality.

The planner returns maintained RemoveMark/AddMark Steps changing only link href,
and AttrSteps changing only anchor Button target. Other link attributes, marks,
node fields, target blocks and metadata remain exact. Raw fragment bytes stay
unchanged when the destination name is unchanged. Percent decoding happens once;
malformed, unresolved, ambiguous or unselected source destinations refuse before
writing. Complete commands retain the existing512-Step maximum; valid imports
needing more repairs remain explicitly unsupported under that budget.

Fresh reviewed preparation independently compares exact repairs, selected node
placement, original fields and the fresh allocation union. Its additional
`navigation_correspondence` has exactly:

- `source_inventory_sha256`: SHA256 of shared canonical JSON containing the full
  original `{destinations,references}` inventory.
- `destinations`: selected `{source_path,kind,source_name,destination_name}` entries,
  with kind heading or anchor.
- `references`: selected `{source_path,kind,source_target,destination_target}` entries,
  with kind link or button.

Paths are original PM node ordinals, bounded to128 safe nonnegative integers and
selected `block_indices`. Each array has at most4096 entries with unique kind/path
identities. The existing issued outer association may seal only selected entries
and the full-inventory digest, retaining no unselected private names. Normal
nested five-field references remain unchanged.

Target-only `prepareRetainedReviewedRecoveryWitness` accepts optional
`navigation_correspondence` separately from `regional_context`. The host already
authenticates original issuance, command/update/hash/scope and selected bindings.
The library checks all selected destinations and references against the original
Slice and permitted repair Steps; missing, extra, altered or claimed unchanged
entries cannot hide a repair. It retains the issued inventory digest without
pretending to rederive it from a partial Slice. Full original mutation replay,
current authorization and donor/source authority remain independent requirements.
Synthetic correspondence fixtures confer none.

Swift and Elixir expose the same planner through
`RelayMarkContentEditCodec.planReviewedHeadingNavigation` and
`RelayMark.ContentEdit.plan_reviewed_heading_navigation/2`. Native rich append/full
replacement applies its Steps before the existing one-writer commit. Browser
commands can append the same Steps after allocator repairs in their existing PM
transform. Explicit Anchor collisions and ambiguous duplicate original Anchors
remain refused pending the supported corresponding allocator operation.
