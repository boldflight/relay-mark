# RelayMark

Portable document grammar, reference runtime and generic Swift/Elixir adapters. The specification and conformance fixtures under `spec/relaymark/` own cross-runtime meaning; keep hosts and product authorization outside that grammar.

## Document and host boundaries

Agent Paper is the editable RelayMark surface: authored prose, semantic entity references, governed layers, inline AI suggestions, action reviews and activity states. Web uses TipTap; native clients use an equivalent native editor. Headers, publish/info controls, navigation, containers, footers, previews and collection engines belong to hosts and must not enter the portable grammar.

## Compatibility and distribution

- `spec/relaymark/contract.json` owns the single canonical editor/sync compatibility identity. Conformance envelopes and generated/read JS, Elixir, Swift and RelayKit bindings use that same contract. The AST carries no separate version. Distribution/package versions retain their ecosystem meaning.
- Strict semantic-version tags release the reference runtime/root Swift package. `elixir-<version>` tags identify the independently versioned `relay_mark_elixir` source for Hex. A Git tag never publishes Hex; the release operator runs `mix hex.publish` with their own credentials.
- Douglas approved the canonical contract 1 cutover on October 4. Preserve document meaning and retained work through explicit conversion from the prerelease lineage; no old editor or schema is admitted as a fallback. Package release numbering does not select document behavior.
- First-party Elixir consumers use published Hex with an open lower-bound requirement and a committed lockfile, not a private Git dependency in production Docker. Swift consumers may follow `main` when their build service has access; respect explicitly stabilized consumers' own tagged policy. Narrow constraints need a demonstrated compatibility/release reason. Do not duplicate resolved pins in policy files.

## Work and checks

Use primary `main` for routine work/releases and registered sibling `relay-mark-worktrees/<purpose>` worktrees for isolation, with absolute paths and unrelated work preserved. A PR is optional, not a release prerequisite.

`package.json` defines `npm test`, `npm run conformance`, `npm run check:contract`, Swift/Elixir adapter tests and the combined `npm run check`. Use focused checks during implementation; release requires the relevant JavaScript, conformance, Swift, Elixir and package-consumer checks with current metadata. Documentation-only changes need source/link and diff validation. Tag only a verified main commit and inspect CI after an authorized push; publication remains a separate action.


## Offline multiplayer branch scope

For offline collaboration work on this branch, start with [docs/OFFLINE_MULTIPLAYER.md](docs/OFFLINE_MULTIPLAYER.md). The September 14 user-approved community-first direction supersedes historical custom-history implementation plans. Research and integrate maintained community components before adding custom infrastructure. Preserve authorization and stored work; do not make experimental provenance or persistent-undo machinery a prerequisite for ordinary collaborative prose.

## Agent commits and pushes

- Agents may push their own reviewed work without asking for routine push approval. Batch coherent changes at natural checkpoints rather than pushing every commit. Before pushing, inspect the outgoing diff and intended remote/branch, run `git diff --check` and the basic checks relevant to the changes, and preserve repository release gates and other contributors' work.
- Correct mistakes locally before pushing; amending an unpublished commit is fine. Once a commit has been pushed, do not amend, rebase or force-push it. Make a new corrective commit instead.
- Push permission does not replace required release, deployment or package-publication checks or any explicit task-specific restriction.
