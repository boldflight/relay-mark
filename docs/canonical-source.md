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
