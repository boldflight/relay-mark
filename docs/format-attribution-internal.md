# Internal formatting attribution and undo checkpoint

These are library preflight and replay mechanisms; app-session activation and
server-authorized delivery remain incomplete. They do not add a history store. Yjs UndoManager still owns the undo/redo stacks and performs
all mutations in its normal transaction. Public runtime commands accept independently trusted replay evidence, never
arbitrary caller-computed attribution plans. The standalone public restored-tail regression remains
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


## September 14 native attributed-history API

`undoWithAttributedEvidence` and `redoWithAttributedEvidence` now expose the
verified mechanism through both the runtime and Swift adapter. The caller supplies
the new operation UUID, exact referenced operation UUID, and an `AttributionReplay`
containing exact UTF-8 recipe bytes plus independently retained owner scope,
document/incarnation binding, digest and final cut. Mark cannot authenticate an
account or receipt solely from these supplied values; that remains the host's job.

Each invocation replays the evidence, checks the current owner cut, and prepares
the ordinary UndoManager inverse. It captures the staged transaction's actual
update bytes, validates its format witness and contribution transition, and checks
the complete successor recipe's bounds and operation-ID uniqueness before live
mutation. A collision with a remote structural operation also refuses. The live
state and emitted update must match preflight. The returned `AttributedHistoryResult`
contains ordinary evidence plus exact successor replay bytes/digest/cut for atomic
host persistence. There is no parallel runtime history store or different inverse
engine. Entirely ineffective operations still refuse without changing state or
advancing their recipe.

Production-command tests cover restored-tail undo/redo after fresh-owner restore,
disjoint peer-owned islands, fully masked no-ops, stale cut, altered recipe,
foreign reference and cross-kind UUID collision. A recorded actual two-client Yjs
fixture also passes Swift/JavaScriptCore undo, fresh-owner snapshot restore, and
redo using the returned replay. This now exercises the library API, not just a
test-only injected plan. The fixture can be regenerated with
`node scripts/generate-attribution-history-fixture.mjs adapters/swift/Tests/RelayMarkCollaborationTests/Fixtures/attributed-history-v1.json`.

Verification passed 118 collaboration JavaScript tests, 49 Swift adapter tests in
nine suites, and contract-version consistency. Exact source/resource/log hashes
are in `/private/tmp/relay-native-attribution-checkpoint-20260914.json`.

Still required: native forward-operation witness capture; ordered, atomic evidence
on existing app journal rows; pairing sibling/remote update delivery; owner snapshot
and replay persistence; negotiated server receipts/backfill; no-effect history
acceptance and cross-client/session acceptance. The old raw-evidence standalone
probe remains a migration gate until app callers move to the attributed API.
These adapter results are not final app/platform gates or complete offline sync.


## September 14 native forward-record checkpoint

Native clients can now call `createAttributionReplay` on an isolated owner with no
undo/redo history, then `editNativeFormattingWithAttribution` to generate their own
format witnesses and successor replay. Baseline creation is read-only and refuses
existing history. The forward API validates the current cut, prepares all ranges,
executes the same operation on a same-client scratch document, validates the exact
witness and successor candidate, and checks bounds before live mutation. It then
compares complete live state and exact emitted bytes to preflight. Invalid ranges,
UUID reuse, stale evidence and entirely ineffective formatting refuse unchanged.

Both forward and inverse APIs now return `record: Data`: exact UTF-8 JSON for the
single appended replay step, alongside update bytes and successor replay. Swift
preserves that string without re-encoding its object. The host must persist those
candidates atomically; returning them does not mean the app has saved them. These
records represent validated local operation evidence, not authenticated server
receipts or account authorization.

Two production runtimes and two Swift clients generate their own forward witnesses
and preserve a peer-owned middle character during undo. Native owner restart and
redo consume the returned replay. Verification passed 121 collaboration JavaScript
tests, 51 Swift tests in nine suites, and contract consistency. Exact source,
compiled-resource and log hashes are recorded in
`/private/tmp/relay-forward-attribution-checkpoint-20260914.json`.

The next storage slice uses the existing journal, not an envelope-owned duplicate
record index: optional immutable attribution sidecar and permanent mixed append
ordinal on each update row, plus owner replay/digest/applied position beside that
owner's snapshot. Current local sequence excludes remote rows; remote epoch also
advances on duplicate echoes; timestamp/digest sorting therefore cannot recover
attribution order. The head belongs in existing replica metadata. Duplicate echoes
must preserve row ordinal and metadata. Legacy nil order remains unproven.

The codec checkpoint below removes/reconstitutes the update array against exact
row bytes and digest so the app does not rewrite private step JSON or duplicate
payloads. Extend the existing owned append and proposal-resolution
transactions with shared-cut and owner replay/snapshot CAS, preserve sibling entries,
and deliver paired durable rows after saving. A trusted baseline must precede new
attributed history; no missing legacy events may be invented. Required tests include
migration, mixed order at equal timestamps, immutable retry/conflicts, save rollback,
two-owner CAS, restart parity, and missing-proof refusal. Concurrent/offline branches
and canonical server receipts still need their full cross-client acceptance gates.


## September 14 attribution record codec checkpoint

`packAttributionRecord` replaces the update array in an exact compact runtime
record with null and binds the sidecar to the original record, update and operation
ID. `unpackAttributionRecord` reconstructs the exact UTF-8 record using the existing
row's bytes and independently supplied sidecar digest and operation ID. Swift
exposes the same operations and immutable `AttributionRecordSidecar`; JSON is never
parsed and re-encoded by the host. Noncompact serialization refuses. JSON is bounded
to 64 MiB and update bytes to 8 MiB.

This codec validates header shape and integrity, not full witness semantics,
authorship or account authorization. The host must qualify the immutable row and
persist its metadata atomically. Replay still rejects semantically invalid witnesses
even when their sidecars pass integrity checks. No app migration, host activation,
server transport, cross-client acceptance or publication is established here.

Existing verification passed 127 collaboration JavaScript tests, 53 Swift adapter
tests in nine suites, and portable contract consistency. Tests include exact Unicode
and property-order reconstruction, placement and formatting records, forward and
inverse native records, wrong row bytes/digest/operation refusal, large payload
removal, and production replay/undo after reconstruction. No compiler or test rerun
was performed while recording this checkpoint.

Evidence logs (SHA-256):

- `/private/tmp/relay-attribution-codec-js-final-20260914.log`:
  `4d0d82e3bd14de62ecc8f6abb01217f0e53a0fdc18e658610dd715de0fcef425`.
- `/private/tmp/relay-attribution-codec-swift-v1-20260914.log`:
  `d363456219a268a1f0c70fe9772b44b7efe200bd60ab0b04b34b62a5670ba4ad`.
- `/private/tmp/relay-attribution-codec-contract-20260914.log`:
  `8c977b4ff0d4dc423faf0e654da9dd6160f2b7c3d62d3713aaebd43646247934`.

The source codec and packaged Elixir module are byte-identical, SHA-256
`e6abdf9cedd8abc15b4233ca12ac0e725a72afd16a1a0ec66c95cc9526850b93`.
The generated Swift runtime resource is SHA-256
`7036a7b7d682f65d0eeb0c4a6d48fb5d5778ca5b373fd68611af432d7f105b82`.

## September 14 ordered peer-record bridge

`validateAttributionReplay` checks the exact recipe and independently retained
scope/binding/digest/cut against the current document without editing it.
`applyAttributionRecord` accepts one compact runtime record, checks its update
binding through the codec, validates the old recipe/current cut, and preflights the
entire successor recipe on scratch state before applying the update with the same
remote origin as ordinary hydration. It returns exact successor JSON/digest/cut;
it does not capture a new local undo item. Duplicate, unknown, incomplete or
out-of-order evidence refuses before live application. Baseline and prior steps
remain in the recipe.

The host must qualify the row and sidecar independently, deliver contiguous mixed
journal order, and atomically save the returned replay and owner snapshot. These
commands do not authenticate peers, recover missing owner operations or persist
anything themselves. Restore owner snapshots into a pristine runtime; applying raw
suffix updates first deliberately makes the old replay stale.

Focused actual JavaScript evidence passed two tests in
`/private/tmp/relay-attribution-application-js-v2-20260914.log`: exact fixture replay
reconstruction, no local undo capture, restored owner undo, and refusal controls.
The initial test attempted snapshot restoration on a populated runtime and correctly
refused; v2 uses the required pristine owner. The additive Swift test is prepared
but has not yet been compiled at this source checkpoint. No host activation claim.

Validated application checkpoint: 129 collaboration JavaScript tests, 54 Swift tests across nine suites and contract validation passed. Logs and exact source manifests are retained in `/private/tmp/relay-owned-attribution-checkpoint-20260914.json`. The matching Swift host component gate passed 50 tests, plus a three-test assertion follow-up, including real two-owner peer formatting, disk restart and atomic proposal/history/replay save. This is not app-session activation, server authorization or concurrent network acceptance.

The additive attributed undo/redo overloads may omit `referenceID`. Mark selects
only the current tracked formatting candidate internally, then scratch execution
must prove that exact reference was actually performed. Explicit-reference APIs
remain unchanged. Peer-only, untracked, prose, skipped and ineffective top items
refuse unchanged; this is intermediate formatting dispatch, not general actionable
undo selection or full editor activation. Focused five-case JavaScript coverage is
recorded in `/private/tmp/relay-attribution-dispatch-js-v2-20260914.log`; the added
Swift overload test remains pending coordinated compilation.

Dispatch checkpoint: 132 collaboration JavaScript tests, 55 Swift tests/nine suites and contract validation passed. Matching host owner-refresh/persistence gate passed 51 tests/eight suites. Exact manifests and log hashes are embedded in `/private/tmp/relay-owner-refresh-dispatch-checkpoint-20260914.json`. This intermediate formatting dispatcher does not claim prose, skipped/no-effect history, app activation or network acceptance.

`replaceProseWithAttribution` now wraps the existing canonical paragraph replacement
with exact staged-update capture and full successor placement replay validation
before live execution. It returns the existing typed/copy evidence plus exact record
and replay; Swift exposes plain and uniform inserted-mark variants. Existing APIs
retain their behavior. Focused six-case JS proof, including typing, split, join and
styled multiline paste with peer replay parity, passed in
`/private/tmp/relay-attributed-prose-js-v1-20260914.log`. Swift coverage is source-ready.
Structural attributed undo/redo remains separate; unsupported structures, mixed marks,
ambiguous successor graphs and ineffective operations are not enabled by this wrapper.

Native candidate/prose checkpoint: 133 JavaScript tests, 57 Swift tests/nine suites and contract validation passed. The matching actual native editor/recovery + owner-store gate passed 66 tests, including typed replacement/split, exact failed-save retries, peer-only refresh and disjoint formatting inverse preserving peer ownership. Exact source manifests and log hashes are embedded in `/private/tmp/relay-attributed-editor-checkpoint-20260914.json`. Structural attributed undo and app-session/network activation remain pending.

### 2026-09-14: structural history and complete peer suffixes

Implicit attributed history now selects supported tracked prose as well as formatting.
It proves the actual performed reference on scratch, validates the successor placement
recipe before live undo/redo, and compares the exact resulting update. Explicit-reference
formatting dispatch stays compatible; skipped, unknown and ineffective history still
refuses unchanged. Split undo/redo preserves peer formatting through the copy lineage.

`applyAttributionRecords` validates the entire nonempty ordered suffix before any live
update and returns one final replay for host metadata persistence. Invalid later rows,
duplicates and out-of-order records refuse without partial application. This is integrity
and semantic validation; the host still owns authorization and durable row qualification.

Focused verification: 136 collaboration JavaScript tests, 16 Swift bridge/carrier tests,
67 native editor/recovery/store tests, and portable contract check passed. Immutable
local receipt: `/private/tmp/relay-structural-batch-checkpoint-20260914.json`. These tests
do not establish app-session activation, authenticated remote evidence delivery, or
cross-client acceptance. Publication and platform gates remain pending.

### 2026-09-14: one runtime for native and caller-owned browser documents

`createCollaborationRuntime` now runs the existing command implementation against
a supplied document, root, patched UndoManager, local origin and Awareness object.
It creates no second live owner; importing the module creates no live resources.
The native JSON entry lazily creates its normal owned context. Both paths therefore
use identical preflight, attribution, copy retention and history execution.

One runtime may attach to a document/manager at a time. Supplied pristine owners
are validated before installation, and disposal releases listeners and retention
without destroying caller resources. The same module ships with the Elixir adapter
for the browser's single patched Yjs dependency.

Verification: 139 collaboration JavaScript tests, 58 native Swift tests and the
portable contract check passed. The factory tests exercise two caller-owned contexts,
paired prose/history/format replay, duplicate ownership refusal, and cleanup/reuse.
Exact source/log hashes are in `/private/tmp/relay-shared-runtime-checkpoint-20260914.json`.
This extraction alone does not wire TipTap persistence or activate network evidence.


### 2026-09-14: restored typed identities and canonical history updates

A verified structural inverse may restore an exact retired typed or baseline
identity. Copy attribution now obtains its tokens from that retained identity;
unknown sources, ambiguous mappings, existing destinations, or mismatching
characters/attributes still refuse. Effective copies remain issued placement
ancestry, never inferred from text equality.

Structural undo also performs Yjs's existing contextless formatting cleanup on
its affected deleted text items inside the existing history transaction. Without
this, local undo retained a redundant marker that remote integration deleted,
so the emitted bytes could not replay to the strict expected cut. The pinned,
source-hash-checked Yjs hook exports that existing implementation under an internal
Relay name; no copied cleanup algorithm or relaxed cut comparison is used.
Missing cleanup support fails owner setup or history preflight.

The actual two-owner regression inserts Japanese text and a paragraph split,
applies peer bold to the inserted text, undoes and redoes the insertion, then
selectively undoes the peer formatting. Every step checks independent replay and
its exact cut. Selected baseline deletion/undo is covered too. All 142 collaboration
JavaScript tests, the hook test, 58 Swift bridge tests and the portable contract
check passed. Evidence: `/private/tmp/relay-history-contextless-js-v1-20260914.log`,
`/private/tmp/relay-history-contextless-hook-v1-20260914.log`, and
`/private/tmp/relay-history-cleanup-swift-20260914.log`. Adapter artifacts were rebuilt
through the canonical script. This remains branch-level evidence; authenticated
server transport, compaction/checkpoint migration and final publication gates are
not established by these tests.


### September 14: metadata-only inverse reconstruction

The internal attribution reducer and replay recipe now accept an additive
`format_noop` step with exactly `kind`, `event` and `operation`. The event contains
version 1, a distinct operation UUID and the mark; the operation contains undo/redo
and its reference. It contains no update bytes or fabricated format witness.
The reducer recomputes a genuinely empty inverse plan against the current
qualified cut, retains its logical scope, and advances the contribution's
active/inactive disposition without changing Yjs bytes or the cut. Replay digest
and operation identity distinguish these history transitions at an unchanged cut.

Effective and metadata-only inverses share a bounded consumed-reference set and
current-disposition validation. A reference cannot be reused after later toggles
happen to restore the same boolean disposition. The set is reconstructed from the
ordered recipe and does not add a persistence engine or external authority.

All 146 collaboration JavaScript tests, 58 Swift collaboration tests across nine
suites, and the portable contract check passed.
The new cases cover masked undo followed by peer undo without resurrection,
metadata undo/redo at one cut, redo becoming effective, same-value removal ABA,
fenced/stale/forged candidates, duplicate operations, consumed references and
fresh replay. Generated Elixir mirrors and the Swift runtime bundle are current.
Logs: `/private/tmp/relay-mark-format-noop-all-collaboration-20260914.log` and
`/private/tmp/relay-mark-format-noop-contract-20260914.log`.

This does not activate metadata-only runtime commands, advance UndoManager
stacks, change the sidecar storage codec, negotiate a wire contract, or admit
metadata-only receipts. Host operation-based journal identity, owner snapshot
persistence, server admission and cross-client acceptance remain required before
removing the existing runtime no-effect refusal.


### September 14: opt-in owner advancement and metadata codec

Attributed undo/redo now accepts explicit `allow_no_effect: true`. Existing calls
still refuse no-effect history. The new path validates the full successor replay
before advancing exactly one selected formatting item within the same isolated
UndoManager. Its inverse has empty insertion/deletion sets and preserved formatting
targets, so it remains serializable and can become an effective redo after peer
history changes. No Yjs transaction or synthetic update is emitted. Both stacks
are coherent before normal history notifications; a throwing observer cannot
lose the prepared operation result, and nested runtime history is fenced.

`packAttributionMetadata` and `unpackAttributionMetadata` preserve exact compact
record bytes using record/sidecar hashes and the operation UUID. Their strict shape
has no update or update digest and cannot be confused with the existing update
sidecar codec. Swift adds distinct metadata-sidecar APIs and additive undo/redo
opt-in overloads; the old method signatures retain their behavior. Applying a
qualified ordered metadata record advances replay without applying a raw update
or adding peer work to the local undo stack.

All 152 collaboration JavaScript tests, 59 Swift tests across ten suites, and the
portable contract check passed. Tests cover absent/false opt-in and wrong-owner
refusal, exact bytes/state-vector invariance, snapshot restoration, peer no-effect
undo followed by effective redo, metadata codec separation/tampering, stale
preparation, and observer failure/reentrancy. Receipt:
`/private/tmp/relay-noop-owner-integration-RESULT-20260914.json`.

The browser history facade also exposes explicit opt-in and freezes a metadata
sidecar, owner snapshot and replay through callback failure/retry. Production
providers still leave it disabled: operation-based durable journals, server
admission/receipts, negotiated capabilities and full cross-client acceptance are
unfinished. Library snapshot restoration and a test persistence callback are not
proof of production durable metadata delivery.


### Native host metadata candidate

`RelayMarkLocalMetadataOperation` carries the operation UUID, undo/redo intent and
existing exact attribution candidate without changing
`RelayMarkLocalTransaction.update`. Hosts can opt into a distinct metadata save
callback and retain that same candidate while persistence fails. The native host
editor's 62-test focused gate verifies failed-save/lost-return retry, pending edit
and peer-delivery guards, unchanged Yjs bytes/vector and later effective redo.
Receipt: `/private/tmp/relay-attribution-schema-v20-v1-20260914/metadata-editor-RESULT.json`.
This host candidate does not itself authorize storage, enable Session integration
or establish negotiated network delivery. The collaboration runtime bundle is
unchanged by this additive Swift type.


### Blocking acceptance: independent concurrent inverses

Run `node scripts/reproduce-concurrent-format-inverses.mjs`. This dedicated
acceptance reproduction currently exits **1**, not a passing regression claim.
Its captured fixture is `test/fixtures/concurrent-format-inverses.json`. Both
owners observed A applying bold and B clearing it, then undid independently. A
authored a metadata-only undo; B authored an effective undo restoring bold.

A-first rejects B with `Ineffective inverse attribution`; B-first rejects A with
`Effective inverse cannot be a no-effect disposition`. Rejection preserves each
receiver's bytes, but one operation remains unaccepted and the visible result
depends on arrival order. Both contributions undone must converge to plain Hello.
The existing ordered five-operation fixture does not establish this concurrency
property. This is a blocker for offline multiplayer activation.

The next protocol step must bind each immutable original candidate to its observed
receipt basis, validate intent there, then reconcile its effect against current
contribution state. Metadata history requires an operation basis in addition to a
Yjs state vector, since it advances without changing document bytes. Corrective
updates must be separately identified and linked, never substituted into the
original candidate or counted as a fresh human contribution. The strict current
replay APIs must not be silently relaxed to accept visibly inconsistent state.


### Pure inverse reconciliation preparation

`prepareFormatInverseReconciliation` validates the immutable authored inverse
against an independently supplied observed basis, then derives its effect against
current contribution state. It integrates original Yjs bytes before creating a
separate correction on a private document. Caller documents and undo managers are
not mutated. The host must authenticate the basis and persist the first prepared
correction for exact retry; this helper is not an admission or delivery API.

Internal authored-record identity is retained separately from derived effect.
This permits an accepted local undo to have a different materialized effect while
still serving as the authenticated parent of its already-authored redo. A
different authored record sharing a UUID is rejected. External receipt JSON and
original update bytes remain unchanged.

Both arrival orders of the captured independent-undo fixture converge to plain
text in the new primitive. Tests also cover a pending local undo/redo chain,
unrelated peer text and marks, original owner undo managers, and independent
original-plus-correction replay. All 159 collaboration JavaScript tests, 59 Swift
tests across ten suites, and the portable contract check passed. Receipt:
`/private/tmp/relay-format-reconciliation-RESULT-20260914.json`.

The strict runtime acceptance reproduction above still fails intentionally.
Negotiated basis capture, durable linked reconciliation receipts, and paired
runtime replay remain unfinished; these tests do not establish multiplayer
activation or server-generated correction interoperability.


### Server-generated correction interoperability

`collaboration-server-format-reconciliation.test.js` replays five synthetic
server-generated packet sequences with both garbage-collection policies. Ten
tests verify each normalized cut, unrelated text/marks, duplicate and reordered
bytes, and snapshot restoration. The checked-in fixture records the generating
server source hash and Yrs revision; it does not simulate server corrections in
JavaScript. The final gate passed:
`/private/tmp/relay-server-packets-regression-final-20260914.log`.

The same regression first failed four cases against the prior Yrs build. Decoded
structures and deletion ranges were identical; only delete-set client ordering
differed. Yrs commit `142153e734eb5a218537176e8e7bd7402e98c829` encodes those
clients in Yjs's descending order. Exact original receipt/update hashes are never
replaced with re-encoded hashes. These are pure packet interoperability tests,
not authenticated delivery, persistence, or owner acceptance replay.
