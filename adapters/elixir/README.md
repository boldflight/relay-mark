# RelayMark Elixir Adapter

Generic Elixir value models and document validation for RelayMark AST and
manifest JSON.

The adapter preserves generic evidence selectors and action-proposal lifecycle
identifiers without executing actions or resolving host authorization.
For durable action rows, `proposal_id` is the generator/client identity and
`proposal_record_id` is the distinct host record address; neither grants
authorization by itself.

Validate canonical JSON-keyed AST maps before a host persists or projects them:

```elixir
case RelayMark.validate_document(document) do
  :ok -> persist(document)
  {:error, diagnostics} -> reject(diagnostics)
end

document = RelayMark.validate_document!(document)
```

Structural validation is compiled at build time from the repository's canonical
JSON Schema 2020-12 document schema. Semantic validation uses the canonical
directive registry and matches the reference runtime's evidence, lifecycle,
comparison, and identity rules. Diagnostics conform to
`relaymark-diagnostic.schema.json`.

Consume the tagged adapter from the repository with a full checkout so its
compile-time canonical schema and directive registry remain available:

```elixir
{:relay_mark_elixir,
 github: "boldflight/relay-mark",
 tag: "0.5.0",
 subdir: "adapters/elixir"}
```

Do not use Mix's `sparse` Git option for this adapter.

```sh
cd adapters/elixir
mix test
```

This package is intentionally product-neutral. It does not execute Relay actions
or know about Relay app persistence, authorization, LiveView, routes, or theme
details.
