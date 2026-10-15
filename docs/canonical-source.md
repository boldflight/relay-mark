# Canonical document source

`spec/relaymark/contract.json` owns compatibility. Documents have no nested version.

The shared source APIs are JS `parseDocument(source, {namespace})`,
`serializeDocument(ast)`, `projectDocumentMarkdown(ast)` and `renderDocument(ast)`;
Elixir exposes `RelayMark.parse_document/2`, `serialize_document/1`,
`project_document_markdown/1` and `render_document/1`.

`serializeDocument` / `serialize_document` writes one fenced `relaymark-ast`
declaration containing the exact authored AST. This is the lossless interchange
syntax: identities, rich wrappers, geometry, form configuration and authored
metadata survive. It does not contain a second visible copy of the document.
The parser validates it against the same current rich schema before admission.

Ordinary Markdown import uses maintained CommonMark implementations (markdown-it
in JavaScript, MDEx/comrak in Elixir) and authored RelayMark directives. Imports
allocate UUID-shaped block identities from the retained import namespace and
structural path. Retrying must retain that namespace or the already parsed AST.
Importing changed source is an explicit replacement operation; ordinary editor
changes use incremental community CRDT operations and never run an initializer.

CommonMark import normalizes only the representation needed by the existing
editor grammar. Empty list items and items beginning with another block receive
an empty leading paragraph with an identity derived from the item path plus
`leading-paragraph`; existing children keep their identities and order. Source
marks apply to text runs, while hard breaks and canonical reference/tag atoms
remain unmarked. Reference UUID, type, label and source stay unchanged, and
marked ordinary wiki text stays literal marked text. Surrounding text retains
its marks. The caller retains the original source as conversion evidence; this
normalization grants no reference access and does not relax canonical AST rules.
Registered directives may omit attributes and use registry-declared defaults.

Readable Markdown is a derived human/search/export projection. It is not a
second writable body and is not roundtrip evidence: Markdown cannot express all
rich identities, merged table geometry or host widget settings. Authored HTML
is another derived projection with escaped text/attributes. Hosts sanitize
output, authorize references and resolve widgets; no private records, hydrated
media credentials, publishing authority or form answers enter the portable AST.

The same Yjs document stores rich XML in `default` and optional authored metadata
as direct `frontmatter`, `annotations`, `resources`, `meta` keys of the `relaymark`
map. The portable XML snapshot calls that optional map `metadata`. Snapshot
conversion and exact source interchange preserve it; unknown keys fail loudly.

These APIs do not imply feature completeness of every native authoring operation.
Missing offered nodes or editing semantics remain explicit implementation gates.

Historical AST input uses JS `importDocument(original, {namespace})` or Elixir
`RelayMark.import_document(original, namespace: namespace)`. This finite migration
boundary removes the obsolete AST counter and known historical profile suffixes,
retains existing canonical block IDs, maps earlier IDs deterministically, and wraps
inline directive bodies in identified paragraphs without changing text or marks.
It returns `{document, identity_mapping}` (Elixir uses atom keys for that result;
the mapping's `retained`, `remapped`, and `added` keys are JSON strings). The caller
must retain the immutable original, namespace and mapping with migration evidence.
Only explicit AST block references are remapped; host entity/resource identities
remain unchanged. Ambiguous duplicated evidence fields and unknown historical
shapes fail. Current admission and normal editing never invoke this decoder.
