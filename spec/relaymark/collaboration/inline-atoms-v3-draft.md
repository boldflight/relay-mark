# Draft v3 inline identity atoms

This read-only projection maps Relay's existing TipTap `relayReference` and
`relayTag` atoms into portable inline AST. The real community Yjs fixture is
[inline-atoms-v3-draft.json](fixtures/inline-atoms-v3-draft.json). It does not
open the v3 live editor gate or change the v1/v2 XML contract.

| TipTap node | Portable inline node |
| --- | --- |
| `relayReference` | `relay.entity_ref` with canonical lowercase UUID `id`, authored `label`, and `props: {entityType, source}` |
| `relayTag` | `relay.tag_ref` with canonical lowercase UUID `id`, authored `#name` label, and `props: {name, source}` |

`source` must equal the exact canonical `[[Type: UUID | Label]]` or
`[[Tag: UUID | #name]]` spelling derived from the other fields. A tag `name`
is a normalized Relay tag name: it starts with a lowercase, modifier or other
letter or a decimal digit from any script, then holds those, combining marks
and `-`, so `#仕事` and `#ラーメン` are tags and `_`, spaces and punctuation
are not part of one. Relay's shared table of inputs and their
normalized names is [tag-names.json](../conformance/tag-names.json), copied
verbatim from the Relay server; every runtime accepts each name it lists. The generic
RelayMark source parser and serializer preserve this spelling for these nodes;
legacy inline references without `props.source` retain their existing link
syntax. Plain `[[unknown]]` text stays inert. Missing IDs, mismatched source,
unknown attributes, and unresolved atoms fail closed in the v3 projection.

Browser-only `status`, `subtitle`, and tag `color` must be null in this strict
profile and are omitted from the AST. Non-null values are rejected because a
portable inverse cannot restore them. HTML/presentation and hydration remain
with the host. The draft portable suite advances to `0.9.0-draft` for this
additional source projection; AST document version remains 1.
