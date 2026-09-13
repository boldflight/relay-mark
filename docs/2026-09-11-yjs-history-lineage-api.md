# Yjs history lineage adapter and upstream API proposal

Local design note only; no upstream issue or message has been sent.

RelayMark currently pins Yjs 13.6.32. Its UndoManager's public events identify the
actual performed stack item and inverse, but do not expose which old text IDs
were restored into which new IDs. Plaintext equality is insufficient for mixed
human/generated text provenance.

The isolated `adapters/collaboration/history-lineage.js` adapter therefore checks
the exact bundled version and required metadata shapes. It copies insertion and
deletion sets, stack metadata, and `Item.redone` pointers to a `gc:false` clone.
Exported `getItemCleanStart`/`getItemCleanEnd` reconstruct original struct boundaries
before redone links are copied. The same Yjs UndoManager implementation runs on
the clone; no independent undo algorithm is implemented. New visible text must
be covered completely by actual old-item → redone-item lineage. Live execution
must match preflight's complete encoded state, not only rendered text.

The canonical collaboration build now applies a small in-memory transform to
Yjs 13.6.32's `dist/yjs.mjs`. `scripts/yjs-history-hook.mjs` verifies the complete
upstream SHA-256 before adding an optional `beforeHistoryTransactionCommit`
hook and version marker. The default is null, the native inverse algorithm is
unchanged, and installed dependency files are not modified. The hook runs after
the actual inverse mutations and before the same transaction's cleanup; it does
not extend UndoManager flags or use side effects in its delete predicate.

A shared `deleteFilter` preserves containers whose descendants survive local
child deletion. Undo can leave a peer-only paragraph in place; redo restores the
local structure around the same peer identities. In the transaction hook,
current attributes on surviving text IDs remain unchanged. Current marks on a
copied counterpart also flow to its restored source identities, including mark
removals. Actual inverse stack metadata retains the counterpart correspondence
so later peer formatting changes flow back through redo. These corrections are
part of one update and one inverse item, not additional history operations.

Desired upstream API:

- An opaque, validated checkpoint/restore API for one UndoManager and its retained
  redone metadata, bound to an exact document state/vector.
- A prepare/commit history operation returning the actual performed stack item,
  inverse stack item, update bytes, and ordered source/destination text identity
  intervals (including restored parent type identities).
- Explicit ineffective/mixed/unsupported results before mutation.

Host operation UUIDs remain metadata on actual isolated stack items. They are
references for server-verified durable receipts, never actor identity or proof of
human authorship. Undo/redo inverse calls receive a new host UUID and reference
the previously accepted operation UUID. Existing history API signatures remain unchanged.

Current focused evidence covers deletion/replacement restoration, four inverse
cycles, mark additions/removals and changes between undo/redo, marked mixed-origin
split tails, surviving peer text/attributes, peer prefix insertion, exact duplicate
update replay, untracked refusal, and stable allocated-client sets after the
first local allocation. A deletion-only forward operation has no local clock
entry until undo first allocates restored items; this is not client rotation.
There is no diagnostic client-ID endpoint added solely for the test.

Focused validation passed 26 JavaScript tests, and two consecutive canonical
builds produced identical bundle bytes. The complete JavaScript suite passed 76 tests, all 17 portable conformance
cases passed, and the portable contract 0.6.0-draft consistency check passed.

The forward lineage endpoint currently accepts top-level paragraphs with text
leaves and marks. Nested/list/code/atom structures remain unsupported by this
evidence endpoint, although the existing generic editor supports more shapes.

This does not establish server validation or broad nested-structure support.
Process restart is covered by the generic snapshot proof below; app activation
and atomic journal integration remain separate acceptance requirements.


## Qualified history snapshots (September 13)

`exportHistorySnapshot({scope_token})` returns a JSON object. The token is opaque
and caller supplied. The native store defines it as `paper-history-v1:` followed
by SHA-256 of sorted-key JSON for the full source cut (scope ID, generation,
local sequence, remote epoch). Mark checks exact equality, not authorization.

The envelope contains `version:1`, `yjs_version:"13.6.32"`, `hook_version:1`,
`scope_token`, `client_id`, `state_update` (complete standard Yjs update bytes),
`state_vector`, `undo`, `redo`, `redone`, and `retained`. Stack entries contain
`insertions` and `deletions` as canonical client/clock/length intervals,
`operation_id`, `counterparts` (exact source/destination selection pairs),
`inserted_text_items` (selection version 1), and `formatting_mark` (null, bold,
or italic). Redone entries carry item ID, length and target ID; retained entries
carry item ID and length. These private snapshot fields are not server receipts.

`restoreHistorySnapshot({snapshot,scope_token,transaction_ids})` returns null.
The host supplies the exact retained journal receipt UUID allowlist separately;
every stack operation ID must occur in it. Extra validated retained receipts are
allowed. Duplicate IDs, unknown references, malformed intervals, unavailable
content, counterpart type mismatch and redone cycles refuse before live mutation.

Restore requires a pristine document, empty stacks and inactive presence. It
validates complete state/vector and metadata on a scratch document, then imports
state and restores retained/deleted content before normal GC can discard it.
The live document's normal GC setting is restored immediately. Applying ordinary
updates first and then importing history is unsupported: deleted text may already
be irreversibly garbage collected. No blanket disabling of GC is required.
After bootstrap, normal peer updates can arrive before undo/redo; restart tests
preserve peer text, marks and original local client identity across two restores.

Limits are 64 MiB serialized envelope, 8 MiB state update, 2,048 UTF-8 token bytes,
4,096 entries per stack, 65,536 retained/redone structs, and 16,384 allowlisted
transaction IDs. Existing selection limits also apply. Refusal does not authorize
purging a host's durable bytes.

The host must save the snapshot atomically with its associated journal updates
and resulting source cut. It must qualify scope/account ownership before export
and restore. The initial native-store contract only returns a snapshot at its
exact current cut; no suffix ordering or stale snapshot recovery is inferred by
this API. Failed persistence must retry the original update/snapshot pair.

Supported tracked operations are `replaceProseWithLineage` (including supported
inline replacements and multiline text) and isolated `nativeFormatting` bold or
italic, each with an explicit optional `operation_id`. Formatting undo/redo
endpoints accept optional `{operation_id}` so the actual inverse stack item can
be durably referenced. Omitting IDs preserves legacy behavior and leaves that
item untracked. No UUID is invented. Formatting history uses its existing typed
formatting evidence and the same native UndoManager; the prose peer-mark overlay
must not cancel an intentional mark reversal. `undoWithLineage` refuses a
formatting item; a backend formatting receipt contract is still required before
new delivery activation.

Legacy `replaceProse`, generic `edit` (text/node insert/delete/format),
`nativeParagraphAfter`, `nativeParagraphPaste`, and mixed undo groups remain
untracked when callers use those endpoints. Unsupported nested/list/code/atom
operations cannot be relabeled as supported prose evidence. Export refuses a
stack containing untracked items rather than silently dropping undo history.

Final focused snapshot/format validation passed 31 tests; the full JavaScript
suite passed 81 tests. This includes invalid import atomic refusal, lossy-GC
refusal, exact typed evidence retention, and formatting undo/redo restart with
host-assigned inverse IDs. Earlier 29-test snapshot artifacts remain preserved.

## Unified tracked history evidence

`undoWithEvidence` / `redoWithEvidence` accept `{operation_id}` and return the
actual performed kind (`prose` or `formatting`), updates, typed item selection,
and either prose lineage or formatting mark evidence. Dispatch selects the exact
tracked item before the shared UndoManager preflight; it does not retry a second
history route after an error. Ineffective top items currently refuse instead of
silently skipping to an earlier operation. Legacy unqualified history APIs retain
their prior behavior.

The additive Swift bridge exposes `HistoryEvidenceResult` and an explicit
`editNativeFormatting(_:operationID:)` overload. `exportHistoryState(scopeToken:)`
returns `SnapshotExport(bytes, transactionIDs)` so hosts receive the validated
canonical unique reference closure without parsing private stack fields. The
existing Data export API is unchanged.

Focused dispatcher JavaScript tests passed 18/18. The matched native fixture
`/private/tmp/relay-native-history-v18-v3-20260913` passed 41 tests including five
opt-in editor tests: split/join reference identity, exact failed-save retries with
peer arrival after structural forward/undo, mixed-mark refusal/default-off
compatibility, and ordinary formatting undo/redo with the typed snapshot closure.
App activation remains separate from this library/editor capability.
