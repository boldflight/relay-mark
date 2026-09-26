# Draft v3 Paper controls

This optional mapping preserves ordinary authored `PaperButton`, `PaperAnchor`,
and `PaperConnection` as one inert portable block:

`{id: relaymarkId, type: "relay.paper_control", props: {control, ...authoredFields, source}, content: []}`.

`control` is exactly `button`, `anchor`, or `connection`. A button has `label`,
`kind` (`anchor`, `link`, or `command`), and `target`; an anchor has `name`; a
connection has `provider`. `source` is the canonical `@Button(...)`,
`@Anchor(...)`, or `@Connection(...)` line generated in the ordinary browser
field order with JSON strings. It must exactly agree with the typed fields.
The browser nodes do not store a source attribute; the projection derives it.
Existing valid ordinary Markdown spellings, including single quotes, spacing,
and attribute order, parse into the same typed fields and serialize to this
canonical source before v3 enrollment.

The portable contract rejects unknown fields, hidden children, unsafe link or
command syntax, source over 16,384 characters, and mismatched source. It carries no navigation result,
connection state, host authorization, or hydrated presentation. Hosts decide
whether and how to execute or render controls. The [fixture](fixtures/paper-controls-v3-draft.json)
contains a real Relay TipTap schema and community Yjs update. This mapping
does not admit a live v3 collaboration profile.
