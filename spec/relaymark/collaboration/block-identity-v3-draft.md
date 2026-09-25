# Draft optional v3 collaborative block identity

This is an **unregistered, opt-in contract slice** for a future exact
`relaymark-prosemirror-v3` document schema. It does not add nodes or attributes
to the live v1/v2 profiles, admit tables, or change the portable RelayMark AST
version. A host may enable it only after browser, server, and native clients
negotiate the same new document descriptor and source contract.

## Identity on XML and AST blocks

Every `Y.XmlElement` that the negotiated profile projects to a portable
RelayMark AST block carries an explicit `relaymarkId` XML attribute. Its value
is also that block's canonical AST `id`; it is not a Yjs position, client ID,
text hash, or UI key. `Y.XmlText` and inline marks do not gain a block ID.
The current heading `headingId` remains a separate author-facing Markdown
anchor (`{#id}`), so a heading may carry both attributes. No table, media, or
callout AST property mapping is specified by this identity slice.

New collaborative IDs have the form `b` followed by the **32 lowercase hex
digits of a UUIDv4**, with hyphens removed. The strict pattern is
`^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$`. It is a subset of the
existing portable AST block-ID schema pattern
`^[A-Za-z][A-Za-z0-9_-]*$`. The prefix is part of the stored ID, so clients
do not each invent a different AST projection. IDs are unique within a
document and stay with surviving blocks across text edits and moves. A pasted
copy gets new IDs; an existing block keeps its ID. A server rejects missing,
malformed, or duplicate `relaymarkId` values for a profile that requires them
instead of silently regenerating them during validation.

The browser should use the community [TipTap UniqueID extension](https://tiptap.dev/docs/editor/extensions/functionality/uniqueid)
with `attributeName: 'relaymarkId'`, an explicit list of admitted block node
types (including `table`, `tableRow`, `tableHeader`, and `tableCell` only when
tables are separately admitted), and a configured generator that encodes a
UUIDv4 in the form above. Filter remote Yjs-origin transactions and mount the
editor only after its provider has synced, as the extension documents. Native
and server code use their platform UUIDv4 generator and the same encoding;
they do not need a second CRDT or a custom node-ID allocator. UniqueID may
assign an ID in an appended editor transaction; a future wire fixture must
prove that creation plus ID is admitted atomically, or that the host safely
groups the updates, before rejecting transient idless states on the live
channel. Validate split/merge, paste, undo, and offline concurrent creation
before production admission.

## Migration boundary

The existing v1→v2 migration remains an exact copy of the Yjs bytes, with no
ID rewrite. A later v3 migration first checkpoints and copies the old Yjs
bytes into a new incarnation under the existing document/entity locks, then
applies and durably records a **separate** ID-backfill Yjs update while clients
are fenced. Only after uniqueness, profile/source projection, and descriptor
validation pass may v3 clients join. Preserve the old pending journal and
checkpoint under the old incarnation; never replay it blindly into v3.
TipTap's automatic initial ID generation must not race across clients as an
implicit migration. If an existing portable AST block ID is externally
referenced or cannot be preserved under this ID shape, migration must stop for
an explicit identity decision rather than silently remap references.

The [ID-only fixture](fixtures/block-identity-v3-draft.json) proves attribute
shape and binary Yjs replay. It is **not** a table AST/source conformance
fixture; richer table semantics remain [gated](fixtures/rich-table-ast.pending.json).
