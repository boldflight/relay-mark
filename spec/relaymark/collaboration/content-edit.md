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
