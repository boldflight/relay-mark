# Draft v3 inline-mark projection

This optional projection covers community TipTap/Yjs text runs in an authored
`relaymark-prosemirror-v3` document. It remains closed to product admission and
does not alter the v1/v2 XML contracts. The Yjs document is the collaborative
authority; the portable RelayMark AST is a validated read model.

The v3 mapper represents marks with existing portable inline wrappers and the
additive `strikethrough` inline type from draft suite `0.7.0-draft`:

| TipTap mark | RelayMark inline wrapper |
| --- | --- |
| `bold` | `strong` |
| `italic` | `emphasis` |
| `strike` | `strikethrough` |
| `code` | `code_span` |
| `link` | `link` with `href` |

Each wrapper has exactly one `content` child. The canonical outer-to-inner
order follows the installed TipTap schema: link, strong, code span, emphasis,
strikethrough. Code span excludes all other marks. Unmarked text is an inline
`text` node, while a `hardBreak` is a separate `hard_break` sibling. The mapper
does not flatten or silently drop an unknown mark, attribute, or wrapper.

The current Link extension normalizes `target: "_blank"`,
`rel: "noopener noreferrer nofollow"`, `class: null`, and `title: null`.
The portable AST stores its authored `href` and the inverse restores those exact
defaults. A different value or a missing attribute rejects because the AST
cannot preserve it. Link creation and navigation policy remain with the host;
`relay:entity/UUID` is an ordinary authored link destination, not an
authorization grant or server-hydrated label.

The [real community fixture](fixtures/inline-marks-v3-draft.json) contains one
Yjs update, TipTap-normalized ProseMirror JSON, and the exact expected AST. Its
[generator](../../../scripts/collaboration-inline-v3-fixture.mjs),
[JavaScript test](../../../test/collaboration-inline-v3-draft.test.js), and
native projection test verify replay, inverse mapping, Unicode text, formatting,
and a Relay entity link. This is a projection proof. Markdown serialization,
all RelayMark directives/widgets, native v3 editing, and live mixed-client
acceptance remain separate release gates.

The native YSwift adapter also has a bounded text-leaf mutation command. It
validates the whole v3 candidate on a scratch Yrs document before changing the
live replica, preserves marks only for edits inside one existing text run, and
returns the exact Yjs update for the host to persist. Cross-mark replacements
and structural input are rejected without changing the live document. This is
a low-level command, not v3 editor admission or a complete typing path.

For documents accepted by the strict v3 AST projector, the native prose
projector has an explicit v3 mode that retains the existing selection/path map
for basic Markdown blocks and marked text with stable `relaymarkId` attributes.
The legacy mode continues to reject those attributes. Tables and other shapes
outside that attributed-text map remain noneditable, and the app's v3 admission
gate stays closed.

The same bounded text command can locate a paragraph by its stable RelayMark
block ID before editing one current XmlText leaf. A YSwift fixture proves a
spanned table cell's text can change without rebuilding its table, spans, IDs,
or peer-replay bytes. Text edits must stay inside one mark run and at Swift
character boundaries; table structure and full native table UI are still gated.
