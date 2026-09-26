# Draft v3 callout source boundary

The optional `relaymark-prosemirror-v3` projector maps the existing TipTap
`callout` and `calloutTitle` nodes to `relay.callout` and
`relay.callout_title` blocks. Each block has its own `relaymarkId`; the title is
the first child rather than a string property, so inline marks and a selection
anchor can survive a Yjs update. Tone and emphasis use the ordinary editor's
enumerated values. The real TipTap/Yjs fixture in
`fixtures/rich-callout-v3-draft.json` covers a bold title between ordinary
paragraphs and proves an exact ProseMirror JSON ↔ RelayMark AST inversion.

The `@Callout(title: "…", tone: "…", emphasis: "…") { … }` source parser can
compile a plain title into the same AST shape. This parser does not yet express
rich title marks or the ordinary editor's full nested Markdown grammar; the
versioned AST and exact Yjs bytes remain the portable rich source. Live v3
enrollment stays closed until Phoenix and native project/edit paths, source
presentation, migration, and mixed-client recovery pass. Host actions and
authorization never belong in the callout node.
