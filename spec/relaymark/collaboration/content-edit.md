# Canonical content edit evidence

The contract identity is `contract.json`; there is no separate operation version.
The live source owner sends `operation_contract: "content_edit"` and one object:

```json
{"before_snapshot_base64":"upstream Snapshot bytes","steps":[],"copies":[],"history":{"kind":"undo","reference":"accepted operation UUID"}}
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


Native owned command groups use maintained StackItem metadata `operation_ids`, an ordered unique UUID list. The first UUID is the source history reference; `OwnedHistoryEffect.operationIDs` exposes the exact popped group's membership rather than guessing by time or visible text. `performOwnedCommand(operationID:separateHistoryItem:_:)` keeps normal capture by default; an explicit semantic boundary closes a group. Checkpoint export preserves live capture. Restore retains all group metadata with the same document/items. `importRetainedHistoryState` is the finite saved `operation_id` metadata decoder, returning original bytes, converted state and normalization records; unknown metadata stays unbound. Hosts preserve originals and verify scoped accepted receipts before treating any group as authoritative. This group binding alone does not provide actual inverse Step capture or server-owned manager replay.

### Trusted maintained owned inverse replay

`replayContentEditMutation` uses the same private evidence owner for ordinary and inverse commands. History additionally requires `initial_state_base64` and bounded chronological `receipts` with exact `transaction_id`, `operation`, `update_base64` and server-derived `sender_state_base64`. Hosts independently authorize receipt scope, group prefixes/full membership, immutable bytes, ordering, completeness and undo/redo cycles before supplying them. These are private trusted inputs, never a client history blob or extra wire contract.

The proof merges peer catch-up under an excluded origin, executes every ordinary receipt through the actual canonical ProseMirror/Yjs writer, and applies its accepted update under one maintained UndoManager origin. Accepted explicit group boundaries reproduce StackItem membership without timer inference. Every accepted and candidate inverse executes that same maintained manager; supplied inverse Step JSON must agree with its actual result and its complete allocation/deletion/format/topology/field footprint. Sender frontier equality includes state vector, retained deletion coverage, full rich identity tree and authored metadata. Original receipts remain unchanged.

A successful inverse returns `owned_history_correspondence: true`, exact `restored_copies` selected from newly changed maintained `Item.redone` links, and `retained_field_changes` with actual allocated/deleted keyed or format item evidence. These supplement existing attribution owners; they are not source classification or permission. Unknown, unavailable, pruned, partial or oversized evidence refuses loudly. Inserted clipboard source authority, structural/field copy ancestry and native actual widget/mark/inverse Step producers remain separate acceptance work; successful inverse correspondence does not enable those capabilities.

Explicit ordinary `operation.copies` may bind retained source IDs to fresh text inside actual final `inserted_ranges` computed by maintained StepMaps. Source type, exact text/full attributes, actual insertion payload and disjoint destination allocations are independently checked; one source may legitimately be copied twice. The builder combines supplied Slice claims with automatic retained-range relocations and removes their exact destinations from human selectors. It never discovers clipboard source by text equality or authorizes its provenance.

Ordinary witness preparation refuses `history`. The same maintained receipt replay returns inverse `fresh_items`, empty `text_items`, and `proven_copies` selected from actual restored links; those destinations must cover every fresh inverse string exactly. Hosts bind declared wire selectors to this trusted result and immutable accepted source ancestry. A redo allocation cannot be silently relabeled human.

Browser `prepareOwnedCommandGroup(manager,UUID)` checks duplicates before mutation and closes only a pre-existing unbound or full 4096-receipt StackItem boundary. Native `NativeContentEdit.ownedGroup` freezes the actual same membership with update/UUID/snapshot/steps; nil remains unproven. Checkpoint/export never splits normal typing.
