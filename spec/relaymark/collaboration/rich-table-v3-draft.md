# Draft v3 rich-table AST projection

This optional projection is scoped to a future negotiated
`relaymark-prosemirror-v3` authored/default document. It does not change the
portable AST version, v1/v2 Yjs admission, or the authored Markdown source
contract. Tables must remain gated until a lossless, safe source/export path and
browser, server, and native editing are separately proven.

The canonical collaborative structure is the community TipTap/ProseMirror
`table → tableRow → tableHeader | tableCell → paragraph → text` hierarchy in
Yjs XML. The [pure mapping](../../../src/collaboration-table-v3.js) translates
only this admitted subset to existing RelayMark AST block types:

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
