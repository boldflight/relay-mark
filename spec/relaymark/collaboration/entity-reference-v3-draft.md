# Draft v3 EntityRef block

This optional offered-node mapping leaves live v3 admission closed. The
browser's `relayEntityReference` is an atom with `relaymarkId`, `entityRef`,
`entityId`, `entityType`, `label`, `projection`, and exact authored `source`.
The portable form is
`{id, type: "relay.entity_reference", props: {id, label, projection, source}, content: []}`.
The portable ID is the stable `relaymarkId`; `props.id` is the authored host
entity reference. The atom has no Yjs children, so its authored fallback stays
inside `props.source` rather than acquiring a synthetic child block identity.

The offered subset requires a canonical `entity:UUID` reference, fixed
`entityType: "Entity"`, link/chip/card projection, and one plain fallback line
with two-space indentation. It accepts exact LF, CRLF, or CR endings, attribute
order, and optional authored label/projection. Source, derived entity UUID,
label, and projection must agree with the TipTap attributes. Unknown attributes,
hidden children, source drift, and host hydration/action state are rejected.
No authorized label, entity fields, action state, or access claim is portable.

The [fixture](fixtures/entity-reference-v3-draft.json) is a real Relay TipTap
schema and Yjs update using the community `y-tiptap` bridge. The generic
RelayMark compiler retains exact source for this safe subset and the serializer
emits it verbatim. Generic directive compilation retains its existing authored
paragraph body; the v3 atom projection has no child content. Both serialize to
the same authored source. Native Swift reads the same Yjs update without
admitting an editable v3 session. Packaged Elixir validates the same portable
AST and exposes `RelayMark.parse_v3_entity_reference_source/1` for server
admission to compare authored fields with XML attributes. The fallback line is
text only; richer directive bodies require a separate
mapping with stable child identities.
