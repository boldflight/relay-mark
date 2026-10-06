# Current source identity classification

`src/document-source-identities.js` owns stateless candidate-bounded classification. It consumes the canonical bare `{runs}` selectors and the existing five-field issued reference: binding, transaction_id, text_items, proven_copies, human_destinations. It adds no persistent identity map, editable replica, history engine, transport version or authorization grant.

The host must authenticate the original transaction/update/reference bytes and hashes, exact document/incarnation/actor scope and complete normal or owned-history mutation proof before classification. A JSON object or the returned reference alone is never a credential. Native offline consumers likewise verify the retained issued envelope before folding references.

`classifyContentEditReference` preserves typed human destinations and propagates only authenticated human ancestors through independently proven copies. Tombstoned human ancestors remain usable; absent ancestors remain generated. Another text type at the same item identity is refused. `foldSourceReferences` retains only requested current candidate identities and refuses foreign bindings or unproven destinations. Selectors bound units to 131072 and runs to 4096.

This primitive does not prove the semantic consequence of a maintained binding reusing an existing identity for inserted equal text. That correspondence must be proven by the shared command witness before the host issues a reference. It must never be inferred from equal text values or silently treated as completed source support.

The packaged `document-source.js` and headless `content-edit.js` export these
same two stateless functions. `RelayMarkSourceCodec.classifyContentEditReference`
and `foldSourceReferences` accept exact JSON Data. The existing caller-owned
Elixir `RelayMark.ContentEdit` runtime exposes `classify_source_reference/5`
and `fold_source_references/4`. No additional editor replica or persistent
classification store is constructed by any adapter.

Source-only failures carry stable codes: `source_identity_mismatch` for a
claimed human item with another text type, `source_reference_mismatch` for
unproven/malformed reference or candidate evidence, and `source_identity_limit`
for bounded selection/receipt resources. Adapters translate these explicit codes,
never infer them from exception text; other command errors retain their own
existing contract.

Full source reads are distinct from authored-command admission. The existing
classifier and each operation selector retain their 131,072 UTF16-unit and
4,096-run bounds. `sourceSelectorWindows(identitySnapshot)` uses the same
canonical visible snapshot index and returns disjoint windows of at most 16,384
UTF16 units; boundaries never split a surrogate pair. Hosts authenticate and
fold the original immutable receipts separately for each window, then discard
the window's candidate map. This does not infer deleted identities or grant
source authority.

`validateSourceReadSelector(selector)` and `resolveContentEditTextItems(snapshot,
selector)` retain exact item/type, overlap, Unicode and missing-item checks for
visible read ranges. Read ranges use the existing source material budget:
12,582,912 UTF16 units, 4,096 runs, and 16 MiB of encoded selector JSON. Resolution
returns current document-order segments; callers may coalesce adjacent segments
in the same XML path without enumerating every character. These read budgets
never select a larger command proof or an alternate attribution classifier.
Host frame transport limits and authorization still apply independently.

Reviewed recovery uses the same classifier after independent full admission
proof. `classifyContentEditReference(binding, transaction, proof, humanAncestry,
regionalContext)` accepts the optional private context exactly as
`{recovery_regions, human_destinations}`. The host must authenticate that context
from the original issued outer association, actor and target namespace; JSON
fields alone confer no authority. The reviewed annotation and executed Steps
must match the retained proof, complete regional and full mutation correspondence
must both hold, and the recomputed regional destinations must exactly account
for every fresh text item/type. The reviewed splice lane requires empty ordinary
typed/copy/history lanes. Only the independently authenticated human subset is
issued in the unchanged five-field reference. Missing or mismatched context
refuses classification; an ordinary command cannot receive regional context.

`foldSourceReferences(binding, candidates, references, regionalContexts)` accepts
an optional private object keyed by the exact original transaction UUID. Each
context must match one reference's exact human subset and bounded regional union;
unused, duplicated, cross-transaction, overlapping or wrongly typed evidence
refuses. The host must require the authenticated outer association for every
reviewed receipt before calling this pure fold. A five-field empty normal
reference alone contains no reviewed annotation, and the fold issues no recovery
completion or donor grant. Normal references and absent-context behavior remain
unchanged.

`partitionReviewedRecoveryDestinations({recovery_regions, human_destinations,
generated_destinations})` validates disjoint exact subsets of the recomputed
imported item/type union and returns the canonical human, generated and unknown
selectors. The caller independently authenticates any generated fact; absence of
human ancestry leaves the remainder unknown. Every region, aggregate selector
and output retains the unchanged 131,072-unit and 4,096-run command bounds.
The issued outer association uses only `donor_cut`, independently authenticated
with the archive/command/update hashes and target scope; request annotations and
normal nested five-field references are never reinterpreted as credentials.

Swift exposes optional `regionalContext`/`regionalContexts` JSON Data arguments
on the existing source codec methods and `partitionReviewedRecoveryDestinations`.
Elixir exposes optional sixth/fifth arguments on the existing
`classify_source_reference`/`fold_source_references` facades plus
`partition_reviewed_recovery_destinations`. The same caller-owned runtime and
stable source failure codes are used by all adapters.

Reviewed splice correspondence accepts only complete closed blocks placed by the
first original `ReplaceStep`: root-end append, or complete root-content replacement
from zero through the exact sender-before content size. Partial root replacement
and open Slices remain unsupported. The existing schema, Step replay, source
ordinal regions, fresh text item/type union and independent complete mutation
proof apply to both. Replacement may carry one actual `DocAttrStep` for
`relaymark`; its final value must equal the exact original reviewed document
metadata, including explicit null/empty values and removed target keys. Append
preserves target metadata. The retained accepted path authenticates the original
issued command and association at the host; it does not reread or grant donor
content. Old target deletions and all field/format/struct allocations remain part
of the separate mandatory whole-update proof.

Only exact maintained structural-ID or heading-anchor repair Steps are permitted
inside imported nodes. Valid unique authored heading anchors remain unchanged.
Absent anchors, later duplicate headings and collisions with explicit anchors
may receive the existing allocator's fresh `h-UUID`, with all other fields, marks,
content and geometry exact. Native AttrSteps and browser setNodeMarkup Steps are
checked against that same maintained operation. A repair that would redirect an
imported local link or anchor button refuses while retaining the original proposal.
Correctly preserving relative-link correspondence through a conflicting heading
repair remains unfinished supported-operation work; this refusal is not a second
import path or a claim of complete heading-link parity.
