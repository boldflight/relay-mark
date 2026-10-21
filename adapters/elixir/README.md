# RelayMark Elixir Adapter

Generic Elixir value models and document validation for RelayMark AST and
manifest JSON.

This adapter validates and maps the Agent Paper RelayMark document. LiveView
routes, headers, navigation, modals, footers, previews, and collection engines
remain host UI outside Agent Paper.

The adapter preserves generic evidence selectors and action-proposal lifecycle
identifiers without executing actions or resolving host authorization.
For durable action rows, `proposal_id` is the generator/client identity and
`proposal_record_id` is the distinct host record address; neither grants
authorization by itself.

The `0.6.0-draft` adapter also decodes Agent Paper property/data bindings and
portable semantic layer contribution metadata. Bindings contain approved host
addresses and field keys, never resolved private values. Layer values describe
already-authorized roles, anchors, placement, and fallback; Relay applications
remain responsible for grants, view profiles, revocation, retention, and sync.

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
{:relay_mark_elixir, ">= 0.6.1"}
```

The exact selected release belongs in the application's committed `mix.lock`.
The lower-bound range lets an intentional `mix deps.update relay_mark_elixir`
select the newest stable adapter release without pinning a single version in
the manifest. Until the deliberate 1.0 boundary, compatible adapter releases
stay on the `0.6.x` line and advance only the patch component. The committed
lockfile keeps ordinary builds on the exact tested graph.

```sh
cd adapters/elixir
mix test
mix hex.build --unpack
```

This package is intentionally product-neutral. It does not execute Relay actions
or know about Relay app persistence, authorization, LiveView, routes, or theme
details.

## License

Licensed under either of the Apache License, Version 2.0
([LICENSE-APACHE](LICENSE-APACHE)) or the MIT license
([LICENSE-MIT](LICENSE-MIT)), at your option. Portions are derived from or
bundle third-party software under their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
