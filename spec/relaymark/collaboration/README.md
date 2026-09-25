# RelayMark collaborative prose v1

This is the canonical contract for `relaymark-prosemirror-v1`, a bounded collaborative prose representation of a separately authorized document layer. It complements the portable RelayMark AST; it does not turn entity headers, permissions, transcripts, task execution, or the whole paper into CRDT state. The host owns those concerns. This document distinguishes the wire contract from each adapter's editing coverage.

## Version identities

| Identity | Value | Meaning |
| --- | --- | --- |
| Document schema | `relaymark-prosemirror-v1` | Exact negotiated XML/mark meaning |
| XML root | `default` | One `Y.XmlFragment` per document incarnation |
| Binary update encoding | Yjs update v1 | `encodeStateAsUpdate` / `applyUpdate`, not their V2 variants |
| Reference implementation | Yjs `13.6.32` | Bundled offline in the optional native adapter |
| Awareness implementation | `y-protocols` `1.0.7` | Ephemeral presence and relative selections |
| Fixture format | `fixture_version: 1` | This directory's binary convergence fixture format |
| Relay host document protocol | `protocol_version: 2` | Host channel negotiation; distinct from Yjs encoding |
| Portable RelayMark suite | `0.6.0-draft` | Existing AST/source conformance identity, unchanged by this additive document boundary |

Schema negotiation must be exact before binding an editor. A client must not silently accept an unknown schema, switch root fields, flatten unknown content, or recreate another incarnation from rendered text. Changing document identity, incarnation, accepted grammar, or semantics requires an explicit migration/negotiation decision. Compatible adapter distribution releases do not themselves change these identities.

## XML and source representation

The root is `Y.XmlFragment('default')`. Elements use ProseMirror node names, not HTML tag names. Inline content is `Y.XmlText` with attributed delta runs; text embeds are outside v1. A text block can contain text and `hardBreak` children. Normalized adjacent text runs may coalesce. Their segmentation is not identity.

| Element | Attributes | Children and meaning |
| --- | --- | --- |
| `paragraph` | none | Inline content |
| `heading` | `level`: integer 1 through 6; default 1; optional nonempty `headingId` | Inline content |
| `blockquote` | none | Block children |
| `bulletList` | none | `listItem` children |
| `orderedList` | `start`: positive integer; default 1 | `listItem` children |
| `listItem` | none | Paragraph and nested block children |
| `codeBlock` | `language`: string or null | Unmarked literal text; newlines retained |
| `horizontalRule` | none | No children |
| `hardBreak` | none | No children; inline line break |

An ordinary empty editable document is a paragraph with empty inline content. An empty binary update is a valid transport update and is not evidence that initial hydration completed. A fragment without supported text blocks may remain read-only in a bounded native projection.

`headingId` is the stable author-facing heading anchor carried by the host's
Markdown heading syntax (`{#id}`). Editors preserve it when editing heading
text; it is not derived from or replaced by a Yjs XML position.

Allowed text marks are `bold`, `italic`, `strike`, `code`, and `link`. Boolean-style formatting uses an attribute object (normally `{}`). `null` removes a mark in an edit operation; it is not an enabled style. `link` contains `href` plus optional `target`, `rel`, and `class` presentation attributes. Unknown non-null attributes fail closed for canonical source serialization. Link titles are not yet in this profile; replicas preserve them, but native editing/source projection must not discard them to obtain acceptance.

Code spans exclude other marks. Their literal backticks and leading/trailing spaces are representable through dynamic delimiters and padding. CommonMark normalizes line endings inside inline code; v1 therefore does not claim exact inline-code newline preservation. Use a `codeBlock` for multiline literal code. Code-block delimiters must be longer than content delimiter runs, and language info must not contain a line ending. The generic Elixir codec implements these rules and has a standalone MDEx roundtrip probe. See [CommonMark code spans](https://spec.commonmark.org/0.31.2/#code-spans) and [fenced code blocks](https://spec.commonmark.org/0.31.2/#fenced-code-blocks).

Canonical entity references in this profile are ordinary labeled links: `[Label](relay:entity/ID)`, represented by a `link` mark with `href: "relay:entity/ID"`. The ID is opaque to RelayMark; the host resolves it and authorizes navigation/actions. Concurrent formatting must preserve the link destination and label. Custom task/entity chips, tables, images, suggestions, forms, media, and portable AST directives are not v1 XML nodes. Their existence in other RelayMark surfaces does not authorize inserting them here.

## Snapshot adapter shapes

Swift/JavaScript snapshots are lossless diagnostic trees:

```json
{"kind":"fragment","children":[{"kind":"element","name":"paragraph","attributes":{},"children":[{"kind":"text","delta":[{"insert":"Alex","attributes":{"link":{"href":"relay:entity/ID"}}}]}]}]}
```

The generic Elixir Markdown codec accepts the equivalent structural shape with `tag` instead of `name` and text leaves containing `delta`. Host adapters translate these field names; neither JSON snapshot shape replaces the binary replica as the durable authority. Unsupported XML remains in binary state even when a source/rendering adapter cannot interpret it.

## Positions, edits, and origins

All XML text indices and lengths are UTF-16 code units. JavaScript string length and Foundation `NSRange` use that coordinate system; Swift `Character` counts and UTF-8 byte counts do not. UI edits must respect grapheme boundaries while converting to UTF-16. The fixture includes an emoji skin-tone/ZWJ cluster, a regional-indicator flag, a decomposed combining accent, and Japanese text. Applying/replaying an update must not normalize Unicode.

Index paths are transient positions in the current XML tree. They must not be persisted as stable selection identities. Use Yjs encoded relative positions for selections that survive concurrent edits; resolve them immediately before mutation. A deleted/unavailable type can resolve to nil. The host handles that case without guessing another location.

The optional native engine exposes bounded `insertNodes`, `deleteNodes`, `insertText`, `deleteText`, and `formatText` operations. Local edits preserve unrelated XML identities. Full source replacement is not the steady-state synchronization algorithm. A logical text-plus-formatting edit may produce multiple binary updates; `mergeUpdates` combines them without losing deletions.

Native local editing uses the process-local origin `relay.local.editor`; restored/received updates use `relay.remote`. `Y.UndoManager` tracks local editing, including grouped text-plus-formatting edits, while excluding remote replay. Undo/redo produce new local updates. Undo history is session-only; restarting restores document content, not the prior undo stack. Origin strings are local routing information, not authenticated actor identities or provider provenance.

## Delivery, durability, and recovery obligations

Updates must converge under duplicate, reordered, and dependency-before-parent delivery. A receiver must retain out-of-order causal data until dependencies arrive. A state vector describes integrated structure clocks; it is not a delivery receipt. In particular, a deletion-only update can leave the state vector unchanged and still require durable delivery.

The host must:

1. Persist exact local binary bytes before claiming local save or sending them. Preserve the original pending entry across retries; do not regenerate a replacement update merely to obtain a new digest.
2. Keep local-save and server-durable states distinct. Only an exact server receipt for the current authorized document binding and update digest can clear the matching pending entry. Socket send success, remote echo, and state-vector equality are insufficient.
3. Validate incoming updates against a temporary replica before committing them to an active durable replica. Persist received updates before presenting their effects.
4. Persist successful initial hydration atomically with its validated baseline. A stream delta arriving before the initial join must not make a restarted incomplete replica editable. A completed blank baseline is valid.
5. Bind cached replicas/outboxes to authority, history epoch, account, organization, document incarnation, authorization lane/epoch, and schema. Account switching cannot adopt another account's pending edits.
6. Treat disconnection as resumable offline work. Treat confirmed authorization loss as a permanent session retirement and mandatory host-owned purge. Replacement/restore gets a new incarnation; pending old-incarnation edits are preserved for explicit recovery, never automatically replayed into the new document.

RelayMark owns no socket, account, grant, database, retry scheduler, or receipt authority. Enhanced contribution provenance is a host contract beyond this v1 prose spec; minimal text diffs alone cannot identify which previous human contribution a deletion replaces.

## Presence

Presence uses standard y-protocols awareness binary updates, not a custom cursor wire codec. States contain `user: {name, color}` with optional `id`, plus optional `cursor: {anchor, head}` relative-position JSON compatible with the matching Yjs/TipTap binding. The host supplies `user.id` from its authenticated principal; the awareness payload itself is not proof of identity and receivers must not authorize actions from it. Awareness clocks/client IDs are separate from server channel origins and authenticated identities. Presence is ephemeral and must never enter the durable text journal. The host removes peers when their connection origin disappears and drives standard renewal/expiry while connected. Presence failure must not corrupt or acknowledge document updates.

## Editing coverage and evidence

| Capability | Browser v1 profile | Native prose projection | Elixir source codec |
| --- | --- | --- | --- |
| Paragraph/heading/list/quote/code block | Editable | Projected; native editing currently covers ordinary paragraphs and one-block heading/text edits | Serialized |
| Five v1 marks and entity links | Editable | Projected; native prose-range edit currently covers bold/italic | Serialized |
| Horizontal rule / hard break | Editable | Projected; native one-block edit inserts/deletes hard breaks, rules remain read-only | Serialized |
| Multiple text/hard-break children in one block | ProseMirror binding | Projected; native one-block text replacement and hard-break operations | Supported text/hard-break sequence |
| Unknown schema or unsupported attributes | Reject before binding/authoring | Preserve and refuse editing | Refuse lossy serialization |
| Rich noncollaborative editor extensions | Legacy editor only | Outside this adapter | Outside v1 |

The browser uses one bounded extension helper for online and offline editing. It omits unsupported nodes/marks, slash/entity insertion extensions, form extensions, and native ProseMirror undo while Yjs owns history. The native projection rejects invalid heading levels/list starts and unsupported attributes. Replica support is broader than editable projection support; preserving unknown binary content is not proof of authoring parity.

`fixtures/convergence-v1.json` is canonical. Its Swift resource copy is checked byte-for-byte by the Node test. It records seeds, incremental updates, delivery orders, expected structural/mark semantics, and unchanged state vectors around a real deletion. Ordinary verification never regenerates it.

```sh
node --test test/collaboration-conformance.test.js
RELAY_COLLABORATION_CONFORMANCE_OUTPUT=/private/tmp/relay-native-conformance.json \
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --filter RelayMarkCollaborationTests
node scripts/collaboration-conformance.mjs /private/tmp/relay-native-conformance.json
elixir -r adapters/elixir/lib/relay_mark/collaborative_prose.ex \
  -r adapters/elixir/test/test_helper.exs \
  adapters/elixir/test/relay_mark/collaborative_prose_test.exs
```

The fixture gate proves Node → actual Swift JavaScriptCore → Node interoperability. The new adversarial corpus also passes Yex semantic checks, duplicate/reordered delivery, checkpoint reload, and Node verification of its reencoded native updates using `scripts/collaboration-yex-conformance.exs`. That standalone probe loads already-built consumer dependencies without starting a server or database. The earlier `yjs-v13-xml.json` fixture additionally has a separately verified database persistence/reencoding loop in the Relay server consumer; the standalone corpus does not replace that durability test. The generic source codec's MDEx probe is `scripts/collaboration-markdown-roundtrip.exs`, run with the consumer's already-built MDEx dependencies on the Elixir code path. Platform editor composition, large-document latency, server persistence/ACLs, and browser/native interaction still require their own application gates.

## Portable relative ranges

A durable range uses `{ "version": 1, "anchor": "<base64>", "head": "<base64>" }`.
Each endpoint is the canonical modern binary returned by
`Y.encodeRelativePosition(Y.createRelativePositionFromTypeIndex(...))`, bounded to
1–256 bytes. Swift `RelativeRange` uses `Data` and Codable's base64 encoding.
The value initializer checks framing/version; `resolve(range:)` validates both
Yjs encodings before resolving either endpoint. Truncated, trailing, overlong,
unsafe-integer, and unknown-root encodings throw without mutating document state.
Unknown item IDs or deleted endpoint containers return `nil`; deletion of the
selected characters may instead collapse both endpoints to the same position.
Anchor/head order is preserved, including backward selections. Indices are
UTF-16 code units; combining sequences and emoji do not change the offset unit.

The host must bind the range to document ID, incarnation, schema and root before
passing it to the engine. These bytes are not an authorization token or a globally
unique document identity. A root-name-only position refers to `default` and can
resolve in any replica exposing that name; only the outer host binding prevents
cross-document or old-incarnation reuse. Unknown nested item IDs safely resolve
to `nil` until their defining updates arrive. The engine never invents a new
scope or infers access from successful resolution.

Portable resolution passes `followUndoneDeletions: false` to the actual Yjs API.
Local undo mappings are not synchronized to other peers, so following them would
make durable contribution ranges resolve differently across replicas. Existing
raw `resolve(anchor:)` retains its local-caret behavior for source compatibility.
Any safe signed association integer is accepted: a negative association follows
the left side; a nonnegative association follows the right side.

`fixtures/relative-ranges-v1.json` contains deterministic real-Yjs nested Unicode,
root-boundary, signed-association and foreign-item fixtures. Node verifies them
and their byte-identical Swift resource; Swift resolves and recreates every known
range byte-for-byte. Native tests also cover concurrent edits, deletion, malformed
input and cross-replica undo consistency:

```sh
node --test test/collaboration-relative-ranges.test.js
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --filter RelayMarkRelativeRangeTests
```

API provenance: [Yjs relative positions](https://docs.yjs.dev/api/relative-positions)
and the pinned Yjs 13.6.32 `src/utils/RelativePosition.js` implementation, including
its documented cross-peer `followUndoneDeletions` behavior. This primitive does
not yet associate human contributions with ranges or implement a contribution
ledger, synthesis reduction, or Enhanced transport.


## Native mixed inline and rule projection

The native attributed projection represents `hardBreak` as U+2028 (one UTF-16
unit) inside its existing paragraph/heading intent. A `horizontalRule` is one
U+FFFC atom with `PresentationIntent.Kind.thematicBreak`; native hosts render it
as an attachment/rule while retaining that one-unit backing string. Paragraph
separators remain U+000A. These are presentation coordinates, never replacements
for the XML or canonical Markdown source. Typing beside a rule creates an adjacent
paragraph; selecting the rule character replaces it with a paragraph, including
an empty paragraph when deletion leaves the document otherwise empty.

`RelayMarkCollaborativeProse.textRanges(in:)` maps formatting to the actual
`XmlText` leaf paths and local offsets, excluding breaks/rules/separators. Hosts
must use those ranges instead of assuming `blockPath + [0]`. Position mapping
uses text indices and XML element boundaries; a hard break/rule's own empty
container anchors its beginning, and its parent boundary anchors its end.

Local inline splices retain untouched text siblings, block identities, and entity
link metadata. Inserting a break inside a text leaf splits only that leaf's suffix.
Splitting/merging paragraphs moves the affected suffix by cloning it: integrated
Yjs types cannot be relocated. This does not rebuild the fragment or unrelated
blocks. Cross-block merges that would copy marked text or a hard break into a
literal code block reject before mutation rather than dropping formatting. This
is an explicit editing restriction, not a document-wide read-only fallback.

`fixtures/inline-v1.json` covers mixed heading text, Unicode, hard breaks, a rule,
nested quotes, and multiple code-text children. Eight incremental edits have
handwritten expected presentation strings; duplicate/out-of-order updates and
concurrent entity-reference typing verify binary convergence. Native tests cover
every UTF-16 selection coordinate, per-leaf formatting, rule-only deletion/undo,
and fail-closed unknown inline nodes. Regeneration is explicit, never part of
ordinary verification:

```sh
node --test test/collaboration-inline.test.js
RELAY_INLINE_CONFORMANCE_OUTPUT=/private/tmp/relay-inline-native.json \
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --filter RelayMarkInlineProseTests
node scripts/collaboration-inline-conformance.mjs /private/tmp/relay-inline-native.json
```

The final command consumes actual Swift JavaScriptCore output in upstream Yjs;
it is not a substitute for platform attachment/IME or server durability gates.
