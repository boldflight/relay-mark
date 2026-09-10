# Exact contribution identity experiment

This is a reproducible exploratory artifact, not a production API, accepted wire
contract, provenance policy, or activation gate. Run from the registered checkout:

```sh
node scripts/contribution-identity-prototype.mjs
```

The script imports the pinned Yjs 13.6.32 used by the collaboration bundle and
also loads the actual committed Swift `yjs-runtime.js` in an isolated JavaScript
context. It uses public Yjs relative-position APIs only; it does not inspect
internal structs or implement a CRDT merge. Its final JSON reports assertions and
local size/timing measurements. All text and replica identities are synthetic.

## Findings

A single relative interval excludes insertion at its outer edges with suitable
endpoint association, but includes a remote insertion in its interior. It is
therefore insufficient to identify exclusively owned text.

For each selected UTF-16 unit, the public default-association start and
negative-association end reference the same item ID. Consecutive item clocks
within one client and type can be represented as a run. Re-expanding these runs
produces byte-identical canonical relative-position pairs to the per-character
oracle. Resolution disables following redone items and round-trips the resolved
start to check the exact item identity. Deleted units are omitted; unrelated
replacement text never inherits ownership based on matching content.

The executable covers both edge and interior insertions, partial/full deletion,
equal replacement text, reordered and duplicated concurrent updates, checkpoint
cloning, formatting, UTF-16 emoji/combining marks, shared-type deletion, multiple
leaves/clients, and undo/redo. Undo restores generated and human text with fresh
IDs: these new IDs alone establish neither authorship nor their old contribution.
The host must carry trusted saved edit intent and undo ownership through that
transition. A Yjs client ID is a replica identity, never an authenticated actor.

On this host, Node 26.8.1, the first successful 100 KiB contiguous ASCII sample
used one run, 101 bytes of compact JSON versus 7,380,789 bytes of per-character
oracle JSON. Capture took 163 ms and expansion plus double resolution/comparison
took 425 ms. Replica IDs are random, so exact byte counts vary. This measures an
exploratory Node implementation with substantial oracle allocation, not native
typing latency, JavaScriptCore performance, or a latency guarantee.

## Minimum proposed portable seam and remaining limits

An additive runtime operation could capture canonical exact-item runs for
validated text-only ranges in a specified replica, then resolve runs against a
candidate replica into surviving ordered leaf segments and exact text. The host
supplies source-transaction identity, intended human ranges and ownership policy;
the grammar/runtime does not choose them. Run locations need the shared-type
identity, client, starting clock and count. Resolution must expose missing/deleted
types distinctly so callers can fail recoverably when loss is ambiguous. This
experiment intentionally treats missing types as absent only for its assertions.

Before adopting a wire format, bound total units, runs, leaf count and encoded
bytes; validate safe integer IDs/counts and overflow, duplicates, overlap, shared
type and document/incarnation binding. Zero, malformed or enormous run lengths
must not allocate an unbounded expansion. The current script receives only its
own trusted synthetic capture results; it is not a decoder for untrusted input.

Compression is excellent for contiguous input but worst-case fragmentation still
requires one run per unit. This prototype expands all units and does not prove an
efficient bounded resolver under fragmented large histories. Multi-leaf ordering,
atoms, structural separators, malformed surrogate edits and deleted ancestors
require explicit supported semantics before general rich-text activation.

The per-character oracle independently stores original canonical anchors but
uses the same public resolver as the compact representation. It proves exact
encoding equivalence and the asserted scenarios, not every possible Yjs history.
Concurrent source replacement conflicts, durable ownership/index transitions,
native exact input intent, grouped undo mapping, server acceptance and authorized
cross-device recovery remain host/server integration work. A checkpoint here is
a standard full Yjs update, not a history-rewriting compaction or room reset.
