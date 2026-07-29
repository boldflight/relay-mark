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

Validate the exact transported Agent Answer document and manifest together:

```elixir
case RelayMark.validate_transported_agent_answer_pair(
       document_json,
       manifest_json,
       %{"surface" => "scripture_ask"}
     ) do
  {:ok, pair} ->
    persist(pair.document, pair.manifest, pair.document_digest, pair.manifest_digest)

  {:error, diagnostics} ->
    reject(diagnostics)
end
```

Structural validation is compiled at build time from the package's bundled copy
of the canonical JSON Schema 2020-12 document schema. Semantic validation uses
the bundled canonical directive registry and matches the reference runtime's
evidence, lifecycle, comparison, identity, Agent Answer, and canonical
manifest-pair rules. Release tests require those bundled files to remain
byte-for-byte identical to the repository source of truth. Diagnostics conform
to `relaymark-diagnostic.schema.json`.

Consume the released adapter from Hex:

```elixir
{:relay_mark_elixir, ">= 0.5.3 and < 1.0.0"}
```

The exact selected release belongs in the application's committed `mix.lock`.
The compatible range allows an intentional `mix deps.update
relay_mark_elixir` to select the newest pre-1.0 adapter release.

```sh
cd adapters/elixir
mix test
mix hex.build --unpack
```

This package is intentionally product-neutral. It does not execute Relay actions
or know about Relay app persistence, authorization, LiveView, routes, or theme
details.
