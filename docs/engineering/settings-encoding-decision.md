# Question settings: the aggregate encoding is canonical

**Permanent rule: never reintroduce per-key `settings:<key>` storage.** Douglas,
2026-11-02: per-key settings storage "killed performance". Stock y-tiptap also
erases the fields. The branches `codex/canonical-settings-key-ownership` and
`settings-key-cutover` are history only and must never be merged.

**Decision (Douglas, 2026-11-02, confirming the 2026-10-18 community-first design):**
a form question's settings are stored in the collaborative document as one
aggregate `settings` attribute on the `questionBlock` / `questionOption`
element. There is no per-key cutover and no server migration.

## Reasons

- The web editor uses stock `@tiptap/y-tiptap`, which maps ProseMirror node
  attributes to XML attributes one to one. It erases `settings:<key>` fields on
  the next edit, so per-key storage needs a forked or patched y-tiptap, which
  the community-first design deliberately removed.
- relay-elixir migration `20261019170000_convert_form_question_settings`
  already converted stored documents to the aggregate, and `DocServer`
  normalizes per-key updates it receives to the aggregate. The aggregate is the
  stored form.
- The cost is accepted: two people editing different settings of one question
  are last-writer-wins on that question's settings.

## What this means for the code here

- Swift keeps reading the aggregate the server stores (`ad20f9f`).
- The per-key codec (`spec/relaymark/xml-attribute-encoding.json`,
  `canonicalAttributeCodec` in `src/document-attributes.js`,
  `encode_attributes` / `decode_attributes` in `relaymark-core`) is **not** a
  write path for stored documents. It is still referenced, so it is not dead
  code to delete now:
  - Rust `document_to_snapshot` / `snapshot_to_document` and
    `import_aggregate_settings_snapshot` call it; the server projects stored
    aggregate documents through the latter.
  - The Swift native editor encodes through it
    (`PMYXmlBridge`, `RelayMarkCollaborativeProse`,
    `RelayMarkNativeWidgetMutation`), so a native settings edit produces
    per-key fields that the server normalizes back to the aggregate.
## The per-key codec is still live, so it stays for now

Checked 2026-11-02 against relay-elixir (`lib`, `assets/js`, `test`), relay-swift
and relay-kit:

- relay-elixir `Relay.Sync.RichDocumentAST` calls
  `RelayMark.DocumentXML.import_aggregate_settings_snapshot/1` (job
  `aggregate_settings`) to read every stored paper. Live.
- relay-elixir builds nodes from `RelayMark.DocumentXML.from_document/1`
  (43 snapshot call sites across `lib`); the engine emits per-key fields there
  and `Relay.Sync.FormSettingsAttributes.aggregate/2` folds them into the
  aggregate. `to_document/1` reads only per-key. Live, through
  `encode_attributes` / `decode_attributes` inside `snapshot.rs`.
- The Swift native editor encodes and decodes through the codec
  (`PMYXmlBridge`, `RelayMarkCollaborativeProse`, `RelayMarkNativeWidgetMutation`).
  relay-swift and relay-kit have no direct callers; the web (`assets/js`) has none.
- `FormSettingsAttributes.convert/1`, `convert_stored/1` and the Oct 19
  migration read Yjs attributes directly with Yex and call no relay-mark function.

So nothing in relay-mark can be deleted on its own. Removal is one coordinated
change: the engine's `to_snapshot` / `from_snapshot` carry the aggregate
`settings` object natively (JS, Rust and Swift), `aggregate_settings` becomes the
plain `from_snapshot`, and relay-elixir drops `aggregate/2` and the import call.
Removing `xml-attribute-encoding.json` also changes the contract `schema_hash`
(its digest covers that file), which stored collaboration descriptors carry, so
it needs a coordinated bump and a server re-stamp. To remove together then:
`spec/relaymark/xml-attribute-encoding.json` (and generated copies),
`settingsAttributeKey` and `canonicalAttributeCodec`
(`src/document-attributes.js`), `encode_attributes` / `decode_attributes` and the
`snapshot.rs` codec, the `aggregate_settings` job and
`importAggregateSettingsSnapshot`, and their tests and fixtures.

## Branches that are history only (to be deleted by Douglas, not by an agent)

| Branch | Head | Date | Why |
|---|---|---|---|
| `codex/canonical-settings-key-ownership` | `5c4859b0f11c5dbc0efba7bf415a06d1e65c1815` | 2026-10-11 (49 commits from 2026-10-06) | Per-key settings ownership prototype with owned-history, receipt and recovery runtimes; superseded by the Oct 18 design; per-key storage killed performance |
| `settings-key-cutover` | `8f0eb4ac89eafbf7352936e6fe6fc4c58b945f84` | 2026-11-02 | Port of that prototype onto main (per-key cutover, Swift aggregate reader removed); rejected the same day |

Never merge either. Descriptor admission was extracted to `descriptor-admission`.
