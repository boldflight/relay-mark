# Canonical authored table rendering

The canonical table AST, ProseMirror and XML keep each cell's `colspan`,
`rowspan`, `colwidth` and `align`. Static authored HTML preserves those values:
cell widths use the maintained comma-separated `colwidth` attribute, spans stay
on the `td`/`th`, and the validated alignment appears as both `data-align` and
`text-align`.

Following the maintained table renderer convention, the first row defines the
`colgroup`. Each spanned column gets its corresponding positive authored pixel
width. Zero or null widths produce an unspecified column; portable rendering
adds no minimum width or table sizing policy. Hosts can supply their own
presentation defaults without changing the authored document.

`fixtures/canonical-table-widths.json` is the independent cross-runtime
expectation for merged headers, row spans, marked Unicode content and partial
widths. Negative/fractional widths and an array whose length differs from the
cell's colspan remain invalid under the existing canonical table validator.
