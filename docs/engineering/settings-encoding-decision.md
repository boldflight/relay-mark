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
- Separate follow-up for the lead to schedule (not done here): decide whether
  native editing should write the aggregate directly, after which the per-key
  policy file, the JS codec, and the encode/decode jobs and their tests can be
  removed together.

## Listed for removal (separate step, not done here)

The per-key codec is the code to remove together once native editing writes the
aggregate: `spec/relaymark/xml-attribute-encoding.json` (and its generated
copies and the `schema_hash` derived from it), `settingsAttributeKey` and
`canonicalAttributeCodec` in `src/document-attributes.js`, the
`encode_attributes` / `decode_attributes` jobs and `snapshot.rs` codec, the
`aggregate_settings` conversion job, and their tests.

History: `codex/canonical-settings-key-ownership` (October 6 to 11); never merge.
