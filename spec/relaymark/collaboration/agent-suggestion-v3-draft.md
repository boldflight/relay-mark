# Authored AgentSuggestion atom in the optional v3 profile

The draft `relaymark-prosemirror-v3` block mapper accepts one root TipTap
`agentSuggestion` atom with a stable `relaymarkId` and exactly five authored
attributes: `review`, `kind`, `confidence`, `evidence`, and `content`. Its
portable block is `relay.agent_suggestion` with `review`, `kind`, `evidence`,
optional `confidence`, and one text child holding the Markdown `content`.
The atom has no XML children or second text CRDT.

Only `draft` and `ready` are admitted as authored presentation values.
`accepted` and `rejected` are review decisions, not shared document authority.
Proposal IDs, proposal status, undoability, host title, and cached source are
absent from the v3 schema and rejected by the strict mapper if supplied.
Legacy source-bearing suggestions need deliberate normalization before any
v3 enrollment. The ordinary portable directive still supports its broader
version 1 contract; this subset does not change it.

`content` is a nonempty, trimmed Markdown string of at most 32,768 UTF-16
units with no carriage return or NUL. `confidence` is null or a finite number
from 0 to 1. `evidence` is a unique list of at most 64 nonempty strings, each
at most 128 UTF-16 units and free of control characters. Source export uses
the existing deterministic directive serializer. The round-trip fixture uses
empty evidence. A separate mapper test preserves a same-document block ID in
evidence, but such IDs may not resolve after reparsing exported Markdown
because the portable source format does not carry them. An ID-preserving
export or migration contract is required before live admission of such refs;
no implicit remapping is performed.

Concurrent edits to `content` replace the entire attribute value; they do not
merge characters. Live v3 admission remains closed. Host proposal review,
accept/dismiss, authorization, and execution stay outside the document.
