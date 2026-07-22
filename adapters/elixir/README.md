# RelayMark Elixir Adapter

Generic Elixir value models for RelayMark AST and manifest JSON.

The adapter preserves generic evidence selectors and action-proposal lifecycle
identifiers without executing actions or resolving host authorization.
For durable action rows, `proposal_id` is the generator/client identity and
`proposal_record_id` is the distinct host record address; neither grants
authorization by itself.

```sh
cd adapters/elixir
mix test
```

This package is intentionally product-neutral. It does not execute Relay actions
or know about Relay app persistence, authorization, LiveView, routes, or theme
details.
