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

This does not establish durable server validation, history-stack restoration
across process restart, or broad nested-structure support. Those remain separate
integration/acceptance requirements.
