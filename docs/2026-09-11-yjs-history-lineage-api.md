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
`scope_token`, `client_id` (exporter session identity), `state_update` (complete standard Yjs update bytes),
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
preserve peer text, marks and historical item identities across two restores.
Each restored runtime keeps its freshly allocated client/awareness identity; the
snapshot client_id records the exporter and is never assigned to the new owner.

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
and either prose lineage or formatting mark evidence. The shared scratch UndoManager performs its normal skipping and identifies the
actual actionable item before live execution. Dispatch does not retry a second
history route after an error. Evidence references the performed item, including
when its kind differs from an obsolete top entry. An actionable untracked item
still refuses before live mutation; no effective item remains a no-evidence
refusal. Legacy unqualified history APIs retain their prior behavior.

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


Formatting snapshot metadata additionally retains `formatting_text_items`, the
exact selected identities captured before the forward operation. The same inverse
hook preserves current peer marks outside that set and allows the intended mark
reversal only on selected identities; unrelated marks remain current. Old
formatting snapshots lacking this field refuse rather than authorizing a broad
mark reversal. Older prose-only entries may omit it.

Uniform bold/italic insertion attributes are explicit in the existing
`inserted_attributes` operation field. The native caller passes the same exact
inserted marks to preflight and live execution. Empty attributes retain the old
API behavior; mixed runs, links and other rich formatting remain unsupported by
this narrow insertion contract. The canonical operation copies caller attributes
before passing them to Yjs, whose insert implementation may mutate its input.


Stable scene history ownership is distinct from ephemeral Yjs client identity.
[Yjs documents clientID as session-specific](https://docs.yjs.dev/api/y.doc), and
[its FAQ warns against concurrent reuse](https://docs.yjs.dev/api/faq). Restoration
therefore reinstates only historical structs, stack intervals and redone metadata,
never the exporting runtime's active client ID. This also gives restarted
awareness a fresh clock namespace rather than competing with old tombstones.

The final fresh-identity/skip/styled runtime passed 31 focused tests and all 91
JavaScript tests. Matched native fixture
`/private/tmp/relay-owned-session-v1-20260913` passed 44 tests, including all seven
editor lineage tests (styled Unicode typing, final IME, formatting history and
structural failed-save peer arrivals). Concurrent restores use distinct active
client IDs, converge after independent edits/undo, and publish fresh awareness
despite an old session's higher-clock tombstone. These focused package checks do
not claim a browser or live-server acceptance gate.


`nativeFormatting` also accepts `ranges: [{path, index, length}]` instead of the
legacy single range fields. It validates every selected text identity before
mutation and formats all ranges in one Yjs transaction and one host operation
identity. Paragraph separators have no text identity or stored inline mark.
Formatting undo uses the same selected-identity preservation rules across leaves.
The focused runtime checks passed 37 tests; all 92 JavaScript tests passed. The
actual emitted two-paragraph Unicode update and formatting undo/redo are retained
in `/private/tmp/relay-mark-multiline-format-interoperability-v1-20260913.json`;
native host acceptance is recorded separately after the matched package check.

The additive read-only `supportsProseLineage()` Swift query shares the operation's
structural traversal and returns a conservative host routing decision. It accepts
nonempty collections of attribute-free top-level paragraphs with text leaves and
only existing bold/italic marks, within the same scalar and resource bounds. An
empty paragraph is eligible; a pristine zero-block document is not. Unsupported
existing marks return false here without narrowing the older mutation API. This
query is neither authorization nor per-operation preflight. Hosts must not discard
a retained history stack when a later remote shape becomes ineligible.

Eligibility verification: 29 focused JavaScript tests and all eight Swift prose
lineage bridge tests passed with the matching bundle on September 13, 2026.

## Proposed trusted placement receipt input (September 13)

This is a generic edit-history boundary, not human-source classification. The host
must authenticate the receipt and atomically pair its retention with the exact
update and history snapshot. Mark validates shape, identity and graph consistency;
it does not turn a caller assertion into server authorization.

```json
{
  "version": 1,
  "document_id": "canonical-lowercase-uuid",
  "incarnation": "opaque-nonempty-string",
  "update_sha256": "64-lowercase-hex",
  "operation_id": "canonical-lowercase-uuid",
  "operation": {"kind": "replace_prose", "reference": null},
  "copies": [{"source": {"version": 1, "runs": []}, "destination": {"version": 1, "runs": []}}]
}
```

`kind` is `replace_prose`, `format`, `undo`, or `redo`. Forward kinds require a
null reference; inverse kinds require the exact prior operation UUID. Format
receipts have no copies. Copy selections use the existing version-one item/type
identity runs, with equal ordered unit counts and no overlap or text inference.
The host passes expected document/incarnation separately. Local receipts use the
same shape after a successful exact operation; this initial API records evidence
only and does not send or authorize it.

The core keeps immutable receipts keyed by operation UUID. Identical replay is a
no-op; a changed payload/hash, unknown inverse reference, mismatched binding,
cycle, or competing successor refuses before changing graph state. A forward
copy records source-to-destination succession. An inverse's actual source-to-new
copy is paired through its referenced receipt to derive prior-placement-to-new
placement edges; it must not form an undirected equivalence class. Old simple
history remains unchanged and no formatting target remapping is activated here.

Bounds: 16,384 receipts, 4,096 copy pairs/runs per receipt, 131,072 total retained
unit edges, 256 UTF-8 bytes for incarnation, and the existing 64 MiB snapshot
ceiling. No automatic eviction. Snapshot retention includes the exact binding and
receipt list; restore recomputes and validates the graph and checks the host's
receipt allowlist before installing it. Legacy snapshots without this optional
extension retain their previous meaning. A separate trusted evidence allowlist is
required for peer receipts; it must not widen the owner's local undo whitelist.

The provisional JavaScript implementation uses immutable
`preparePlacementReceipt(state, {expected_binding, trust, update, receipt})` and
`restorePlacementState(snapshot, expected_binding, receiptIDs)`. Exact update
bytes are SHA-256 checked with lib0. `trust` is explicitly `local` or `server`;
this value is an assertion by the authenticated host, not network verification.
At the bundled runtime boundary, `local` must additionally match the last actual
operation's UUID, kind/reference, copies and merged update hash. Server receipts
remain subject to caller authorization. Receipt replay retains its original
trust label and never silently upgrades local evidence to server acceptance.

The runtime's `preparePlacementReceipt` returns
`{version:1, base_sha256, state}` and holds it as an uncommitted candidate.
`exportHistorySnapshot({scope_token, placement_candidate})` can include that
candidate for the host's atomic store append. Only after the save succeeds does
`commitPlacementReceipt(candidate)` advance the graph, checking the exact held
candidate and unchanged graph base. A failed append therefore does not advance
live graph state. The host must also enforce its existing document cut/ownership
fence; the graph CAS is not a replacement for database transaction ownership.

Snapshots with graph state add optional `placement`. Their restore additionally
requires `expected_placement_binding` and `placement_receipt_ids`; graph validation
finishes before the existing pristine document restore begins. Old snapshots and
restore calls remain unchanged. Graph units are bounded across all retained
receipts, and conflicting item/type identity declarations refuse. This core does
not yet supply remote receipt transport, marker attribution, or format remapping.

Checkpoint/compaction admission is a separate pending pathway. The exact-live
API deliberately rejects absent update bytes, including for server trust. Existing
graph snapshot restoration needs no original update bytes, but only restores
already retained receipts; it is not authenticated server backfill admission.
A future `prepareCheckpointPlacement` must take expected document/incarnation,
the exact checkpoint bytes and independently host-verified checkpoint digest,
and a host-verified operation-ID-to-canonical-receipt-hash allowlist covering the
server sidecars. It may then validate/rebuild a candidate graph without expired
raw updates. Mere receipt IDs or caller-provided update hashes do not establish
checkpoint coverage. This must not reuse or weaken the runtime-proven local path.

Current placement succession deliberately refuses concurrent competing successors
from the same source; it does not claim general concurrent structural acceptance.
Identity clients use the shared JavaScript-safe integer bound; clocks remain
UInt32. The 4,096-run cap applies in aggregate across all copies on each side.

The additive Swift bridge exposes `PlacementBinding` and opaque
`PlacementCandidate(bytes, receiptIDs)`. `prepareLocalPlacementReceipt(update:binding:)`
derives the last exact runtime operation, including a formatting inverse's actual
reference. `prepareTrustedPlacementReceipt(_:update:binding:)` is explicitly the
authenticated-host server path. Export accepts an optional candidate through an
overload; `commitPlacementReceipt` follows the successful atomic host save.
`SnapshotExport.placementReceiptIDs` stays separate from local `transactionIDs`.
The restore overload takes both the expected placement binding and independent
placement receipt whitelist. Existing no-graph calls remain source compatible.
None of these bridges enables graph remapping or changes source admission.

`PlacementCandidate.receipt` exposes only the exact canonical derived receipt for
the update row, while `bytes` remains the opaque graph candidate. Receipt copies
coalesce ordered contiguous source/destination unit pairs independently of the
original run/copy partition; the operation request JSON is never rewritten. Exact
original Mark endpoint fixtures and their matching accepted server exports prove
local-to-server duplicate acceptance despite that partition difference.

## Formatting attribution investigation

An effective ContentFormat identity distinguishes ordinary mark addition and many
peer changes. It is insufficient for removal: actual Yjs cleanup leaves
`{marker:null, enabled:false}` both after local removal and after a peer add/remove
ABA. A regression retains this counterexample. No remapping is activated from
null-marker equality. Exact removal attribution must retain the real removed
marker identity and immutable operation identity while that event is observed.
Per-operation paired updates can maintain this witness; a later merged/compacted
raw update cannot recover a garbage-collected marker's former meaning.

Current server ReferenceCodec trees retain text item IDs and mark values only;
they do not retain ContentFormat event/deletion identities. Acceptance-time
formatting sidecars or an additive Yrs/Yex observation API are required for
authenticated compacted bootstrap. This remains an implementation dependency,
not a reason to infer marker identity from text, values, offsets or timestamps.

### Pure format-event prototype

`captureHistoryFormatEvent(beforeDoc, exactUpdate, {operation_id, mark, text_items})`
returns a provisional sidecar:

```json
{
  "version": 1,
  "operation_id": "immutable-operation-uuid",
  "update_sha256": "exact-update-digest",
  "mark": "bold",
  "text_items": {"version": 1, "runs": []},
  "inserted_markers": [{"client": 1, "clock": 2}],
  "deleted_markers": [{"client": 1, "clock": 3}],
  "changes": [{
    "unit": {"item": {"client": 1, "clock": 4}, "type": {"client": 1, "clock": 0}},
    "before": {"marker": {"client": 1, "clock": 3}, "enabled": true},
    "after": {"marker": null, "enabled": false}
  }]
}
```

It rejects text/other-mark allocation or deletion, unresolved integration,
unavailable/previously deleted format markers, untargeted mark changes and
ineffective or garbage-collected events. It replays the exact update against a
scratch copy of the supplied prestate. `validateHistoryFormatEvent` re-captures
and requires exact canonical equality. The prestate is not mutated. Selected
units are capped at 131,072 and marker arrays at 4,096. This is evidence capture,
not authorization: the host binds document/incarnation and authenticates receipt
identity. A removed marker ID plus immutable operation identity distinguishes the
event from a later peer removal even when both poststates show no marker.

The tested live per-operation pathway does not validate a merged add/remove
history after its marker content has been garbage-collected. That case refuses.
Compacted bootstrap needs a previously authenticated retained event sidecar, not
re-capture from expired updates or mark values. Yrs currently exposes update
insertion/deletion sets but keeps block content traversal crate-private. A bounded
read-only format-event API in Yrs/Yex is needed to validate and retain this exact
sidecar at acceptance. No format remapping or transport activation is included.

## 2026-09-14 generic format witness checkpoint

The isolated Yrs worktree `/Users/douglas/Developer/y-crdt-worktrees/format-event-witness`
contains tested commit `cf0c57f75f8591f33450f67ef21cae7fdb9cc36c`.
`FormatEvent::inspect` observes an exact format-only update against settled UTF-16
prestate without mutating the caller. Four focused Rust tests pass, including
actual Yjs 13.6.32 `{}`/null add/remove/ABA parity for inserted, deleted and
effective marker identities, and refusal beneath deleted XML ancestors.

The Yex wrapper and two passing focused tests remain **uncommitted** in
`/Users/douglas/Developer/y-ex-worktrees/format-event-witness` at base `a312e0c`.
Its committed dependency pin is unchanged. Only the isolated verification fixture
`/private/tmp/relay-format-witness-yex-v1-20260913` points to local tested Yrs source.
Before a reproducible Yex checkpoint, make the exact Yrs commit remotely available
under separately authorized publishing, update the dependency pin, and verify
normal resolution. Nothing was pushed during this checkpoint.

The exact source hashes and logs are recorded in
`/private/tmp/relay-format-witness-checkpoint-20260914.json`.
Rust log: `/private/tmp/relay-format-witness-rust-v2-20260913.log`.
Yex log: `/private/tmp/relay-format-witness-yex-v3-20260913.log`.
The shared actual-JS fixture is tracked in Yrs and prepared in Yex; no human-source
classification or server authorization is inferred by the generic API.

Limits remain explicit: checkpoint size is checked after encoding, and encoding
and scratch replay cost scale with document size outside the traversal budget.
Merged/GC events with lost marker content and updates that also clean up a different
attribute refuse. A format boundary reset can change an outside unit's effective
marker identity without changing its value; selected target IDs remain the intent
scope, so an outside reset alone must not invalidate another user's formatting.
The focused boundary-reset regression below verifies this distinction; remapping
remains disabled.
A future domain format-event capability/version must be negotiated separately;
this does not broaden `prose_lineage_v1`. Trusted acceptance/compaction witnesses,
paired host persistence and selective remapping are still unactivated.


### Selected format scope proof (2026-09-14)

Actual Yjs formatting of the first two units of `Hello 🌍` inserts a bold marker
for those units and a null reset marker for the remaining suffix. Every suffix
unit stays unbolded despite its effective marker changing from absent to the new
reset ID. The event records that reset in `inserted_markers` for exact-update
validation but excludes all suffix units from `changes`. A forged witness adding
an outside unit refuses; a claimed selection omitting an actually bolded unit
also refuses. Thus marker allocation is structural evidence, while selected text
identities bound the formatting intent. No generic marker-ID change grants
permission to invalidate another user's format operation.

A second actual transaction removes italic and adds bold over the same text.
It is valid Yjs formatting but refuses both single-bold and single-italic event
witnesses. This proves the conservative combined-mark limit; it is not evidence
that an ordinary bold-only operation necessarily deletes italic markers.
Supporting multiple mark events requires an explicit contract, not silent widening.

All six pure witness tests passed in
`/private/tmp/relay-format-boundary-targets-v1-20260914.log`. Only tests and this
plan changed; the existing helper already enforced the required selected-ID
scope, so no bundle rebuild or remapping activation was needed.

## 2026-09-14 reproducible contribution publication

The earlier fixture-only dependency limitation is resolved. Consumer Yrs commit `524fc72da468d1d930a083fc8a573487289c3b63` and Yex commit `7a23c1ff79cb50cfa3d4ce9d20d082bd7e22ee6b` are pushed to the respective `boldflight` forks on `codex/format-event-witness`; both exact remote SHAs were verified. Yex's manifest and lockfile use that remote Yrs commit, with no committed local override. Its full suite passed against normal remote resolution: 558 tests and 63 doctests. Rust formatting, strict Clippy, Elixir formatting and Credo also passed. Consumer Yrs passed 346 unit tests and 40 doctests, with two existing ignored tests.

The standalone [Yrs draft PR657](https://github.com/y-crdt/y-crdt/pull/657) is based on current upstream and excludes the prior resolver contribution. Its verified head `2168672d6c38651270c990cfb15495cfe8432f2d` passed 413 unit tests and39 doctests, with one ignored test; `cargo check -p ywasm` also passed. That check compiles the host crate, not browser WebAssembly runtime acceptance. Upstream internal block/client representations differ from the consumer backport; the two verified commits must not be treated as interchangeable dependency pins.

Exact source hashes, logs and boundaries are recorded in `/private/tmp/relay-format-witness-publication-20260914.json`. A separate upstream-only Yex wrapper patch is being verified against its own base; the consumer suite does not prove it. Relay's internal witness validator and later immutable receipt/undo integration remain separate work. No format capability, paired client output, or undo remapping is activated by these library contributions. The previously requested backend history/placement output edit remains paused for direct payload/destination confirmation after automatic approval review rejected it.

## Executable completion blocker

The [peer-formatting-after-split-undo regression](peer-format-split-undo-regression.md) records the runnable two-owner blocker: after A splits `Hello`, B bolds both paragraphs, and A undoes the split, B's formatting undo still leaves the restored `llo` bold. The probe asserts the required entirely plain `Hello` result and currently exits nonzero. Library witness checks and publication receipts above do not establish this end-to-end undo behavior; remapping remains unactivated.

## September 14 internal attributed undo checkpoint

[Internal attribution and undo](format-attribution-internal.md) records the verified
mechanism and its activation limits. The existing UndoManager now has an internal
exact-plan path for restored placements and masked contributions; public command
activation, durable receipt replay and native disjoint-intent acceptance remain
open. The standalone public regression is still an integration gate.

The generic dependency contributions are now published as draft
[Yrs PR #657](https://github.com/y-crdt/y-crdt/pull/657), corrected head `c992eac30e5bf25a375db05987c397ad25b0e51b`,
and [Yex PR #247](https://github.com/satoren/y_ex/pull/247), head `c8005e6d23a8403f0c411ba234bf826378534e17`.
The latter's own upstream-based suite passed 614 tests/doctests and its formatting,
Credo, Clippy and Rust test checks; its temporary compatible Yrs backport pin and
upstream dependency remain explicit. Hosted CI was not yet reported at publication.


## September 14 replay and native retention checkpoint

The [internal attribution checkpoint](format-attribution-internal.md#september-14-restart-verification)
now includes bounded, hash-bound ordered recipe replay and a fixed native snapshot
retention defect found by actual restarted-owner tests. Verification passed 115
collaboration JavaScript tests and 47 Swift adapter tests. The next slice is atomic
existing-row attribution evidence plus ordered local sibling delivery and a native
replay bridge; current native restore returns unordered raw hydration rows, which
cannot establish contribution order. Unknown remote suffixes remain fenced.

Server channel output remains unchanged pending the already-requested direct
confirmation. Native/app host activation and cross-client acceptance are still
required before the working-branch goal is complete; no deployment is required.


## September 14 native replay bridge checkpoint

The [attributed-history API](format-attribution-internal.md#september-14-native-attributed-history-api)
is now available in the production runtime and Swift adapter. Verified exact
replay drives the existing UndoManager and returns a validated successor recipe
for atomic host persistence. Its recorded peer-formatting sequence passes native
undo, owner restart and redo. Verification: 118 collaboration JavaScript tests,
49 Swift adapter tests in nine suites, and contract-version consistency.

The next app integration requires forward witness capture and exact, ordered
receipt metadata on existing journal rows. Swift's current raw hydration accessor
is still insufficient for that ordered evidence. Session/provider activation,
server receipts/backfill, no-effect history acceptance and cross-client gates
remain open. The previously rejected backend channel-output edit is unchanged.


## September 14 native forward evidence checkpoint

The [forward-record API](format-attribution-internal.md#september-14-native-forward-record-checkpoint)
now creates a local baseline and generates exact forward formatting witnesses in
production Swift/JavaScriptCore. Forward and inverse results carry exact single-step
record JSON for the existing journal. Verification passed 121 collaboration
JavaScript tests, 51 Swift adapter tests and contract consistency.

Next: Mark-owned sidecar codec, then additive V20 immutable row metadata and mixed
append order, owner replay CAS in the existing snapshot envelope, and paired
post-save sibling delivery. Do not derive ordering from remoteEpoch or timestamps,
or move the update journal into the owner envelope. Structural record integration,
server receipts/backfill, no-effect history acceptance and cross-client offline
acceptance remain required. The blocked channel-output edit remains unchanged.
