# Current source identity classification

`src/document-source-identities.js` owns stateless candidate-bounded classification. It consumes the canonical bare `{runs}` selectors and the existing five-field issued reference: binding, transaction_id, text_items, proven_copies, human_destinations. It adds no persistent identity map, editable replica, history engine, transport version or authorization grant.

The host must authenticate the original transaction/update/reference bytes and hashes, exact document/incarnation/actor scope and complete normal or owned-history mutation proof before classification. A JSON object or the returned reference alone is never a credential. Native offline consumers likewise verify the retained issued envelope before folding references.

`classifyContentEditReference` preserves typed human destinations and propagates only authenticated human ancestors through independently proven copies. Tombstoned human ancestors remain usable; absent ancestors remain generated. Another text type at the same item identity is refused. `foldSourceReferences` retains only requested current candidate identities and refuses foreign bindings or unproven destinations. Selectors bound units to 131072 and runs to 4096.

This primitive does not prove the semantic consequence of a maintained binding reusing an existing identity for inserted equal text. That correspondence must be proven by the shared command witness before the host issues a reference. It must never be inferred from equal text values or silently treated as completed source support.

The packaged `document-source.js` and headless `content-edit.js` export these
same two stateless functions. `RelayMarkSourceCodec.classifyContentEditReference`
and `foldSourceReferences` accept exact JSON Data. The existing caller-owned
Elixir `RelayMark.ContentEdit` runtime exposes `classify_source_reference/5`
and `fold_source_references/4`. No additional editor replica or persistent
classification store is constructed by any adapter.
