# Community table interoperability probe

Status: experimental evidence, **not** a negotiated schema extension or an enabled editor capability.

The existing community representation is sufficient for CRDT transport. Actual installed TipTap core/table 3.30.2, y-tiptap 3.0.9 and Yjs 13.6.32 produced the committed fixture through `getSchema`, `schema.nodeFromJSON` and `prosemirrorJSONToYDoc`, using root `default`. No parallel Relay table model was introduced.

The XML hierarchy is `table → tableRow → tableHeader/tableCell → paragraph → Y.XmlText`. Cell attributes include `colspan`, `rowspan`, `colwidth` and `align`; null defaults are omitted by the Yjs binding and restored by the ProseMirror schema. The fixture includes:

- A 2×2 table with a header row, Unicode and two body cells.
- A two-column merged header (`colspan: 2`, `colwidth: [120, 180]`).
- A vertically merged cell (`rowspan: 2`, `colwidth: [140]`).

The YSwift/Yrs adapter accepts each binary update, integrates duplicate delivery without pending structs/deletes, and produces the same lossless XML snapshot. Re-encoding in Yrs and importing into upstream Yjs restores the same schema-normalized ProseMirror document. A native low-level cell text insertion preserves cell attributes, advances an existing relative text anchor, and converges with the JavaScriptCore reference adapter. These are CRDT/data results; they do not prove a native table layout, merge/split commands, table undo behavior or authorization/admission.

Both native prose admission methods and the native prose projection continue to reject table editing. An attempted basic-prose edit leaves the encoded document unchanged. The generic Elixir `CollaborativeProse.to_markdown/1` returns `{:unsupported_collaboration_content, {:node, "table"}}` for all three real snapshots rather than dropping cells or spans.

## Source mapping decision

Do not enable table enrollment until the source roundtrip is explicit and tested in every consumer. GFM pipe tables cannot encode row/column spans or column widths. Even a rectangular table is not automatically lossless: multiple blocks inside a cell, header placement and formatting need separate checks.

One narrow source case is now proven. The committed 2×2 unmerged Yjs/ProseMirror fixture passes through the installed `tiptap-markdown` 0.9.0 serializer to `| Name | Value |` / `| --- | --- |` / `| Hello 🌍 | 二 |` and back to the same ProseMirror JSON, with TipTap's optional trailing empty paragraph disabled for the probe. Relay's MDEx parser reads exactly two rows, two columns, and the same four cell texts. Both live server profiles still reject that Markdown table; this is evidence for a future negotiated subset, not enabled table collaboration. The merged-cell fixtures remain Yjs-only because pipe Markdown cannot represent their spans or widths.

The installed `tiptap-markdown` table serializer checks spans, header placement and multiple cell blocks, falling back to its HTML serializer for incompatible tables. The current server `Relay.Markdown` uses MDEx with `unsafe: false`; the parent investigation found that this omits raw table HTML. Therefore that fallback is currently unsafe as a *content-preservation* path. Do not merely turn on global unsafe HTML.

TipTap 3.30.2's newer built-in `renderTableToMarkdown` is not a merged-cell escape hatch: its implementation builds rows of `{text, isHeader, align}` and does not preserve `colspan`, `rowspan` or `colwidth`. A dependency switch alone would silently change meaning.

Recommended next decision: retain the community XML/ProseMirror table as the authoritative collaborative structure, and choose one explicit, versioned source/export contract before admission. If Markdown-compatible HTML is chosen, use maintained HTML parsing/sanitization and community table serialization with a narrowly allowed table/inline vocabulary; prove both safe rendering and exact cell/span/width roundtrip through server and native source readers. Keep unsupported source conversions as explicit errors. A separately approved GFM-only subset can be smaller, but must reject merged cells and other unrepresentable attributes rather than presenting itself as full table support. This probe does not implement either source format or a custom parser.

## Reproduce

Run from the Mark worktree with its existing YSwift dependency available. Supply an actual web assets directory containing the community packages:

```sh
node scripts/collaboration-table-probe.mjs /absolute/path/to/web/assets
RELAY_TABLE_NATIVE_OUTPUT=/tmp/relay-table-native-output.json \
  swift test --filter RelayMarkNativeTableProbeTests
node scripts/collaboration-table-probe.mjs /absolute/path/to/web/assets \
  /tmp/relay-table-native-output.json
node scripts/collaboration-table-probe.mjs /absolute/path/to/web/assets --source-only
```

The first command regenerates experimental binary fixtures (Yjs replica IDs may differ). The second reads the committed fixtures and verifies native re-encoded updates; it does not overwrite fixtures. The focused Elixir test is `adapters/elixir/test/relay_mark/collaborative_table_probe_test.exs`; it consumes the exact same snapshot fixture. In the probe environment it passed via `elixir -pa <existing-jason-ebin> -r adapters/elixir/lib/relay_mark/collaborative_prose.ex -e 'ExUnit.start(); Code.require_file("adapters/elixir/test/relay_mark/collaborative_table_probe_test.exs")'`, without starting a server or database.

The `--source-only` command reads the committed rectangle fixture and verifies the community serializer/parse roundtrip without rewriting its Yjs update. Relay Elixir's `test/relay/sync/document_prose_enrollment_test.exs` separately checks the MDEx table shape and continued v1/v2 seed rejection.

Verified with installed Swift 6.4/Xcode.app: one native XCTest over three fixtures, one Elixir test over three fixtures, and three native-to-community-Yjs roundtrips. No platform app build, Yex persistence test, interactive table UI, or live schema change was performed.

## Primary implementation evidence

Inspected installed sources, not inferred table conventions:

- `@tiptap/extension-table/src/cell/table-cell.ts` and `src/header/table-header.ts`: cell attributes and `block+` content.
- `@tiptap/extension-table/src/table/table.ts` / `src/row/table-row.ts`: table/row content and table roles.
- `@tiptap/y-tiptap/dist/y-tiptap.js`: actual ProseMirror↔Yjs conversion used by the generator.
- `tiptap-markdown/src/extensions/nodes/table.js`: `isMarkdownSerializable` and HTML fallback.
- `@tiptap/extension-table/src/table/utilities/markdown.ts`: built-in Markdown renderer's limited row representation.
- Server `lib/relay/markdown.ex`: MDEx safe rendering configuration.
