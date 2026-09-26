# Draft v3 rich-table AST projection

This optional projection is scoped to a future negotiated
`relaymark-prosemirror-v3` authored/default document. It does not change the
portable AST version, v1/v2 Yjs admission, or the authored Markdown source
contract. Tables must remain gated until a lossless, safe source/export path and
browser, server, and native editing are separately proven.

The pure JavaScript v3 mapper also has a separate Markdown-block fixture at
[`markdown-blocks-v3-draft.json`](fixtures/markdown-blocks-v3-draft.json).
It is generated with community TipTap StarterKit, Relay PaperHeading, UniqueID,
y-tiptap and Yjs by
[`collaboration-markdown-block-v3-fixture.mjs`](../../../scripts/collaboration-markdown-block-v3-fixture.mjs).
The fixture carries an actual Yjs update, schema-normalized ProseMirror JSON,
and the exact expected portable AST. The additive block mappings are:

| ProseMirror/XML | Portable AST |
| --- | --- |
| `heading` (`level`, nullable `headingId`) | `heading`, `props: {level, headingId}` |
| `blockquote` with paragraphs | `quote` with paragraph blocks |
| `bulletList` | `list`, `props: {kind: "bullet"}` |
| `orderedList` (`start`, `type: null`) | `list`, `props: {kind: "ordered", start}` |
| `listItem` (paragraph, optional nested list) | `list_item` with the same blocks |
| `codeBlock` (nullable `language`, unmarked text) | `code`, `props: {language}` with text |
| `horizontalRule` | `horizontal_rule`, empty content |
| `hardBreak` (inline; no block ID) | inline `hard_break` |

All block XML elements require stable `relaymarkId` values. An ordered list's
nullable TipTap `type` attribute must be null for this slice; non-null list
numbering variants fail. Only one nested list level, one paragraph per list item,
paragraph-only quotes, and the [bounded v3 inline marks](inline-marks-v3-draft.md)
are admitted. Other RelayMark elements and all product admission remain separate work. Table
cell paragraphs stay plain-text-only; this expansion does not silently broaden
the existing table source contract.

The canonical collaborative structure is the community TipTap/ProseMirror
`table → tableRow → tableHeader | tableCell → paragraph → text` hierarchy in
Yjs XML. The [pure mapping](../../../src/collaboration-table-v3.js) translates
this admitted subset to existing RelayMark AST block types. Its mixed-document
entry points also accept plain top-level paragraphs before or after tables;
the existing table-only entry points retain their stricter contract:

| ProseMirror type | RelayMark AST type | Required AST properties |
| --- | --- | --- |
| `table` | `table` | none |
| `tableRow` | `table_row` | none |
| `tableHeader` | `table_cell` | `header: true`, `colspan`, `rowspan`, `colwidth`, `align` |
| `tableCell` | `table_cell` | `header: false`, same cell properties |
| `paragraph` | `paragraph` | none |
| `text` | inline `text` | `text` |

Every mapped block, including each row, cell, and paragraph, requires an
existing `relaymarkId` ProseMirror/Yjs attribute in the [v3 block-ID
shape](block-identity-v3-draft.md). It becomes the AST `id`. The mapper does
not generate or backfill IDs. IDs must be unique across the projected document.

Cell `colspan` and `rowspan` are positive integers. `colwidth` is either
`null` or an array of positive integer pixel widths with one entry per spanned
column. `align` is `null`, `left`, `center`, or `right`, matching installed
TipTap table attributes. Header identity is the explicit `header` Boolean;
the existing AST schema has `table_cell` but no `table_header` type. Each cell
contains at least one paragraph; text leaves are plain text in this first
slice. Rows must form a complete non-overlapping rectangle, including cells
spanning later rows. Unknown attributes, marks, node types, or AST fields fail
projection; they are never silently omitted.

This draft bounds each table to 256 rows, 256 columns, and 4,096 explicit
cells before building its span grid. Larger tables require a separately
reviewed resource limit rather than allowing an untrusted span to amplify
allocation.

The [test](../../../test/collaboration-rich-table-v3-draft.test.js) enriches
the existing real TipTap/Yjs table cases with explicit v3 IDs and proves
ProseMirror JSON → AST → ProseMirror JSON equality for rectangular, colspan,
and rowspan examples. It also exercises rejection boundaries. This proves a
portable data projection, not a Markdown/HTML source round-trip, table UI,
collaborative admission, or v1/v2 migration. Those remain separate release
gates.

The [concurrent table fixture](fixtures/table-concurrent-v3-draft.json) captures
two independent cell edits followed by community `addRowAfter`. Raw
`yDocToProsemirrorJSON` omits default cell attributes such as `align: null`;
the strict mapper rejects that shape. Pass it through the negotiated TipTap
schema's `nodeFromJSON(...).toJSON()` before mapping. The inverse mapper writes
`content: []` on new empty cell paragraphs, while canonical ProseMirror JSON
omits that empty property; normalize the inverse through the same community
schema before comparing or rendering. Neither boundary changes stored IDs,
spans, column widths or text. The official static renderer can display the
normalized table and existing `relaymarkId` attributes, but it is a view path,
not source validation or live v3 admission.

The [mixed update fixture](fixtures/table-mixed-v3-draft.json) is reproducibly
built from that real concurrent table Yjs update by inserting ID-bearing Yjs
paragraphs before and after the table, including one empty paragraph. The
[generator](../../../scripts/collaboration-mixed-table-v3-fixture.mjs) projects
the resulting update through the installed community y-tiptap binding and
normalizes it with TipTap's schema. The test verifies block order, IDs, empty
content, text, spans and widths through AST and inverse ProseMirror JSON.
This is a mixed-document Yjs projection proof, not live v3 admission or a
browser/native editing acceptance test for surrounding prose. Unsupported
top-level nodes, unknown inline marks or attributes, and duplicate IDs fail closed.
