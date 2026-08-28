# ADR 0001: Safe Agent Paper composition profile

- Status: accepted for portable contract `0.6.0-draft`
- Date: 2026-08-14

## Context

Relay presents typed relational work through malleable Agent Papers. A Person,
Task, Collection, or Meeting keeps its domain meaning while sharing one paper
surface. RelayMark must let humans and agents compose that surface without
becoming a database, authorization system, renderer-specific UI language, or
general-purpose programming runtime.

The host owns entity schemas, resolved values, authorization, registered
actions, read models, retention, revocation, sync, and mutation receipts.
RelayMark owns human-readable source, a portable AST, semantic directives,
validation, deterministic manifests, and portable composition metadata.
Renderers own presentation and transient interaction state but execute no
actions while parsing or rendering.

## Decision

### Orthogonal directives

The first Agent Paper composition profile adds only:

- `relay.entity_reference` through `@EntityRef`;
- `relay.property_sheet` through `@PropertySheet`;
- `relay.data_view` through `@DataView`;
- `relay.layout` through `@Layout`;
- the existing `relay.action_row` for registered action references.

No entity-type-specific directive is introduced. Property sheets and data
views carry binding addresses, field keys, and presentation intent. They never
carry resolved host records, edit permissions, credentials, SQL, callbacks, or
network instructions. Removing a binding block changes composition only; it
does not express deletion of its bound data.

### Capability negotiation

Renderer capabilities are declared by the directive registry rather than by
authored source. Each capability-bearing directive has one deterministic
fallback: render children, plain text, a visible summary, or explicit omission.
The reference runtime reports a per-block resolution. Unsupported content is
never silently treated as supported and never crashes the renderer.

### Layer roles and anchors

RelayMark standardizes five portable semantic roles: `authored`, `source`,
`generated`, `discussion`, and `ink`. These are provenance and composition
roles, not storage formats or access levels.

The portable layer-composition input contains only contributions the host has
already authorized. Items use stable block anchors, `before`/`after`/approved
slot placement, deterministic rank, and one explicit fallback:
`append_to_layer`, `omit`, or `unresolved`. Anchor state is `present`, `absent`,
`stale`, or `undisclosed`. Diagnostics for an undisclosed anchor never include
the hidden anchor identity.

The composer returns a linear sequence with layer provenance. It does not
create a z-stack, perform authorization, mutate source, or create a persisted
whole-paper document. Source mode edits one selected textual layer. A composed
audience projection must not be serialized back as if it were authored source.

### Unknown and unsafe input

Trusted documents reject unknown directives, undeclared directive attributes,
invalid binding addresses, malformed registered-action IDs, and invalid
composition metadata with stable diagnostics. Import and recovery tools may
preserve unknown source inertly, but rendering remains side-effect free.

## Dependency direction

```text
Relay domain host
  resolves authorized schemas, values, read models, and action availability
          |
          v
RelayMark source and validated portable AST
          |
          v
Relay Kit or another deterministic renderer
```

`RelayMarkSwift` remains a standalone portable value/validation package. A
Swift UI renderer may depend on both RelayMarkSwift and Relay Kit. RelayMark
must not depend on or re-export the UI package, and Relay Kit must not become a
Relay database client.

## Consequences

- Task, Person, and Collection papers can share one safe composition grammar.
- Bound data stays authoritative and private in the host.
- Renderers can degrade predictably across platforms and versions.
- Meeting layers can preserve provenance and independent governance without
  placing the whole paper or its structured state in one CRDT.
- A later host may add grants, view profiles, per-layer collaboration, and sync
  without changing RelayMark into an ACL format.
- New layout or data projections require additive registry capabilities and
  fixtures rather than arbitrary CSS, code, or queries.

## Rejected alternatives

- Raw JSON as the user interface: portable but not humane and too easy to
  confuse with domain storage.
- HTML/CSS/JavaScript/SwiftUI in source: renderer-specific and executable.
- One directive per entity type: duplicates the host type system.
- Private values embedded in property blocks: leaks data and creates stale
  copies.
- Layer grants in RelayMark: moves authorization into a portable document.
- One composed multi-layer source document: destroys provenance and audience
  boundaries.
