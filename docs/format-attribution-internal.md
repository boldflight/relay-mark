# Internal formatting attribution and undo checkpoint

This is an internal preflight mechanism, not an activated client capability or a
new history store. Yjs UndoManager still owns the undo/redo stacks and performs
all mutations in its normal transaction. The public runtime commands do not yet
accept attribution plans. The standalone public restored-tail regression remains
an open integration gate until authenticated host delivery is wired.

The ephemeral reducer consumes an immutable document cut and exact update bytes.
Format witnesses are revalidated against prestate. Structural-copy identities must
come from the existing placement graph after the host authenticates the receipt
and pairs its exact update hash. Matching text or marks alone never proves ancestry.
Unknown raw-update suffixes fence attribution; serialized candidate shells cannot
restore authority. Trusted recipe replay is implemented below; atomic host persistence and authenticated checkpoint/backfill remain required.

Each forward format contribution has an immutable identity and an active/retired
disposition. Inverse references retain their own operation identities. Logical
scope is retained separately from the actual changed units, so a partial undo can
retire a contribution hidden by a peer, and redo can restore the original scope
when that peer override is later undone. Boundary resets outside declared selection
do not acquire ownership. Exact predecessor identity handles equal-value ABA;
visible formatting alone cannot authorize an inverse.

Plan applicability hashes a fresh GC-normalized full Yjs state. This allows owners
to retain different already-deleted undo payloads while checking live structures,
causal clocks and deletions. Pending integration refuses. Original update hashes
remain byte-exact. The existing staged execution validates the plan before live
execution. A version-pinned optional item-skip hook allows a verified plan to make
real formatting changes when the original markers are already gone; normal Yjs
inverse capture then runs once. Stale/mismatched plans leave bytes and stacks intact.

Actual internal UndoManager tests cover restored-tail undo/redo, null and partial
peer ABA, disjoint protected islands, restored predecessor ownership, retirement
of masked contributions, and redo over the full original scope. Entirely
no-effect inverses remain explicit `noop` results and unmutating runtime refusals;
metadata-only no-op history acceptance is not implemented. Native UI validation
and wire contracts still need to carry exact disjoint history intent without
widening a single range. No cross-client deployment or acceptance claim follows
from these component tests.

Bounds are explicit refusals, never silent eviction: 8 MiB original/normalized
state, 131,072 retained units and aggregate event/scope units, 16,384 events, and
bounded predecessor traversal. Receipt persistence must preserve these semantics
within the existing app-owned journal, alongside the existing placement graph.

Verification for this checkpoint: 106 collaboration JavaScript tests passed in
`/private/tmp/relay-attributed-collaboration-v3-20260914.log`, including eight actual
staged/live UndoManager sequences. The rebuilt native resource passed 46 Swift
collaboration adapter tests in `/private/tmp/relay-attributed-swift-v1-20260914.log`.
Packaged browser modules match their source copies. Exact source/resource/log
hashes are recorded in `/private/tmp/relay-attributed-undo-checkpoint-20260914.json`.
These are component gates, not server transport, app-session or hosted CI results.


## September 14 restart verification

`format-attribution-replay.js` reconstructs an opaque candidate from an exact JSON
recipe. The host must independently supply its persisted SHA-256, owner scope,
document/incarnation binding, and expected normalized final cut. Those expectations
must be paired atomically with the existing journal; a digest calculated from an
untrusted recipe is not authorization. Ordered format steps revalidate exact
witnesses and inverse references. Structural steps rebuild the existing placement
graph at each prefix before transferring contribution identity. No serialized
tokens, dispositions, or caller-computed predecessor state are imported.

The baseline must precede every retained contribution and referenced predecessor.
A current content snapshot is not an attribution baseline. The recipe is bounded
to 64 MiB of UTF-8 JSON, 16,384 steps and 8 MiB per update, alongside existing
reducer/state bounds. Replay still costs repeated document scans; these are size
limits, not a measured latency guarantee. Compaction cannot discard required
history to fit them. The returned graph is a structural projection, not a
replacement for an owner graph that also retains empty-copy formatting receipts.

Actual owner restart testing exposed a separate GC defect: remote split undo could
collect the old text parent still referenced by another owner's formatting stack.
The runtime now composes an owner-specific GC filter with Yjs's existing policy.
It retains metadata-referenced intervals and ancestors from undo/redo stacks,
the currently popped item, and in-flight capture. It does not claim Yjs keep flags
or disable collection globally. A bounded interval index refreshes on transaction
and stack events. Overflow preserves content during cleanup and causes subsequent
checkpoint/preflight refusal. Cleared references are eligible for normal or
explicit host GC; clearing alone does not run whole-document compaction. Direct
out-of-band metadata mutation followed by explicit GC is unsupported.

Verification: 115 collaboration JavaScript tests passed, including serialized
replay into fresh owner runtimes, restored-tail undo/redo, masked-contribution
retirement and reactivation, reordered evidence with identical final CRDT state,
malformed proof refusal, retained ancestor release, and layered-filter disposal.
The rebuilt native runtime passed 47 Swift adapter tests in eight suites, including
a JavaScriptCore regression that restores both owners after peer split undo. That
Swift test proves snapshot retention, not app-level attribution replay activation.

Exact evidence is recorded in
`/private/tmp/relay-attribution-replay-checkpoint-20260914.json`.
App journal metadata/order, native replay bridge, provider/session activation,
server-authorized format receipts/backfill and cross-client acceptance remain open.
The public standalone restored-tail undo probe is still an integration gate. This
checkpoint does not claim complete offline multiplayer, final repository gates,
backup of these Relay commits, deployment, or staging merge.
