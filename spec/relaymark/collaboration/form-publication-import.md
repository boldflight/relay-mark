# Finite saved form publication import

`RelayMark.import_form_publication(publication, namespace: retained_namespace,
source: optional_same_release_body)` and JS `importFormPublication(publication,
{namespace, source})` return the canonical `document`, `identity_mapping` and
explicit `normalizations`. Elixir wraps success in `{:ok, result}` and returns
content-free diagnostics on refusal. This is a finite migration input decoder;
normal editors and respondent renderers consume the canonical document only.

The host retains the complete original publication and its domain fields,
including publication identity/time, approval rules, logic and actions. This
adapter does not publish, authorize or use a current draft. It converts the
historical block list: prose `label` is complete authored source; question and
option labels are rich inline source. The existing canonical importer parses
marks, references, callouts, tables, media and other supported prose. Canonical
block identities are deterministic from the retained namespace; stable question
and option IDs remain exact authored props. Extra question/option settings and
answer keys remain portable JSON. Contradictory correctness/answer keys, duplicate
identities and ambiguous label/text representations refuse conversion.

When a Course release retained its original body, only that immutable body may
be supplied as `source`. Its prose, question/option identity and rich labels must
agree with the saved publication independently of newly allocated block IDs.
Missing settings may be recovered from that source with an explicit
`recover_retained_source_setting` normalization. Conflicting known settings or a
changed draft label refuse. The publication's grading answer key remains exact.
The original publication and exact retained body are both recovery evidence for
the host's existing fenced migration receipt.

An absent original body cannot recover information already omitted by a
historical parser. Unknown block shapes, unsupported prose or metadata in a
fragment refuse loudly. The current canonical questionLabel/option grammar is
rich inline: a historical label containing several paragraphs/blocks is an
explicit unresolved grammar capability and refuses, rather than flattening it.
Normalizations are reviewable evidence, not a claim of publication authorization.

Already canonical publications with a `document` validate that exact document and return only retained identities with no normalizations. Projected domain `blocks` are not decoded as historical source; the publication host verifies its own derived block projection against the canonical document. An optional retained source must reconcile to the same semantics without changing canonical identities or recovering new settings on rerun. Invalid current documents fail rather than taking the historical input branch.
