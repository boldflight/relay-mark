# RelayMark

Portable document grammar, reference runtime and generic Swift/Elixir adapters. The specification and conformance fixtures under `spec/relaymark/` own cross-runtime meaning; keep hosts and product authorization outside that grammar.

## Document and host boundaries

Agent Paper is the editable RelayMark surface: authored prose, semantic entity references, governed layers, inline AI suggestions, action reviews and activity states. Web uses TipTap; native clients use an equivalent native editor. Headers, publish/info controls, navigation, containers, footers, previews and collection engines belong to hosts and must not enter the portable grammar.

## Compatibility and distribution

- The portable conformance-suite version is the compatibility identity. Every release states the version it implements; distribution versions are independent and need not match each other.
- Strict semantic-version tags release the reference runtime/root Swift package. `elixir-<version>` tags identify the independently versioned `relay_mark_elixir` source for Hex. A Git tag never publishes Hex; the release operator runs `mix hex.publish` with their own credentials.
- Preserve valid document meaning and public adapter source compatibility throughout pre-1.0. Compatible releases stay on `0.6.x` with patch increments; reserve the next minor/major change for the deliberate 1.0 boundary. Breaking changes wait for 1.0.
- First-party Elixir consumers use published Hex with an open lower-bound requirement and a committed lockfile, not a private Git dependency in production Docker. Swift consumers may follow `main` when their build service has access; respect explicitly stabilized consumers' own tagged policy. Narrow constraints need a demonstrated compatibility/release reason. Do not duplicate resolved pins in policy files.

## Work and checks

Use primary `main` for routine work/releases and registered sibling `relay-mark-worktrees/<purpose>` worktrees for isolation, with absolute paths and unrelated work preserved. A PR is optional, not a release prerequisite.

`package.json` defines `npm test`, `npm run conformance`, `npm run check:contract`, Swift/Elixir adapter tests and the combined `npm run check`. Use focused checks during implementation; release requires the relevant JavaScript, conformance, Swift, Elixir and package-consumer checks with current metadata. Documentation-only changes need source/link and diff validation. Tag only a verified main commit and inspect CI after an authorized push; publication remains a separate action.


## Offline multiplayer branch scope

For offline collaboration work on this branch, start with [docs/OFFLINE_MULTIPLAYER.md](docs/OFFLINE_MULTIPLAYER.md). The September 14 user-approved community-first direction supersedes historical custom-history implementation plans. Research and integrate maintained community components before adding custom infrastructure. Preserve authorization and stored work; do not make experimental provenance or persistent-undo machinery a prerequisite for ordinary collaborative prose.
