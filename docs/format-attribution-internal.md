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
restore authority. Durable receipt replay and checkpoint/backfill remain required.

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
