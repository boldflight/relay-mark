# Question settings: the aggregate encoding is canonical

**Permanent rule: never reintroduce per-key `settings:<key>` storage.** Douglas,
2026-11-02: per-key settings storage "killed performance". Stock y-tiptap also
erases the fields. The branches `codex/canonical-settings-key-ownership` and
`settings-key-cutover` are history only and must never be merged.

**Decision (Douglas, 2026-11-02, confirming the 2026-10-18 community-first design):**
a form question's settings are stored in the collaborative document as one
aggregate `settings` attribute on the `questionBlock` / `questionOption`
element, byte-identical to what stock `@tiptap/y-tiptap` writes
(`spec/relaymark/editor/y-tiptap-settings-v1.json`, generated from it). There is
no per-key cutover and no server migration.

## Reasons

- The web editor uses stock `@tiptap/y-tiptap`, which maps ProseMirror node
  attributes to XML attributes one to one. It erases `settings:<key>` fields on
  the next edit, so per-key storage needs a forked or patched y-tiptap, which
  the community-first design deliberately removed.
- relay-elixir migration `20261019170000_convert_form_question_settings`
  already converted stored documents to the aggregate, and the aggregate is the
  stored form.
- The cost is accepted: two people editing different settings of one question
  are last-writer-wins on that question's settings, softened by the client-only
  rebase layer below.

## Conflict avoidance is a client layer, not per-key storage

Douglas, 2026-11-02, on keeping `settings_rebase`: "this is a valid enhancement of stock yjs behavior and better ux, so thats not the same as insanity per key checking."

- Forbidden: per-key settings STORAGE or WIRE, such as `settings:<key>` attributes, presence markers, per-key normalization, or any codec that splits `settings`.
- Approved: the client-only `settings_rebase` layer (relaymark-core job, JS mirror, Swift engine call; shared fixture `spec/relaymark/editor/settings-rebase-v1.json`). Storage and wire stay one whole `settings` attribute, byte-identical to stock @tiptap/y-tiptap. A client that sees its unconfirmed settings edit overwritten re-applies only its own changed keys onto the incoming value, in one follow-up write.
- Never remove the rebase layer as "per-key". Never add per-key storage as "conflict avoidance".

## What the code does now

The per-key encoding and decoding were deleted outright (branch
`aggregate-writer`, release 0.7.5). Production and staging counts of stored
per-key fields were 0, so there is no read path and no conversion.

- `encode_attributes` / `decode_attributes` (relaymark-core and the JavaScript
  mirror) pass the aggregate `settings` object through and refuse per-key
  `settings:<key>` fields and the `settings: true` marker.
- The engine's snapshot conversion carries the aggregate natively; the
  `aggregate_settings` job, `importAggregateSettingsSnapshot` and the key codec
  no longer exist, and the attribute policy has no `presence`, `field_prefix`
  or `key_encoding`.
- The Swift editor writes one `settings` attribute for a native edit of a
  question (`PMYXmlBridge`) and reads the same shape.
- The contract `schema_hash` covers `spec/relaymark/xml-attribute-encoding.json`,
  so the deletion changed it; descriptors stamped with an earlier hash are
  refused by descriptor admission (`admit_descriptor`,
  `spec/relaymark/editor/descriptor-admission-v1.json`), which reads a
  document descriptor only when it is exactly the runtime's own contract.

## Branches that are history only (to be deleted by Douglas, not by an agent)

| Branch | Head | Date | Why |
|---|---|---|---|
| `codex/canonical-settings-key-ownership` | `5c4859b0f11c5dbc0efba7bf415a06d1e65c1815` | 2026-10-11 (49 commits from 2026-10-06) | Per-key settings ownership prototype with owned-history, receipt and recovery runtimes; superseded by the Oct 18 design; per-key storage killed performance |
| `settings-key-cutover` | `8f0eb4ac89eafbf7352936e6fe6fc4c58b945f84` | 2026-11-02 | Port of that prototype onto main (per-key cutover, Swift aggregate reader removed); rejected the same day |

Never merge either.
