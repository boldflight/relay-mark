# RelayMark agent guidance

Follow [CONTRIBUTING.md](CONTRIBUTING.md) for building, testing, conformance
and licensing.

- The specification and conformance fixtures under `spec/relaymark/` own
  cross-runtime meaning. Keep hosts and product authorization outside the
  grammar: headers, navigation, containers, previews and collection engines
  belong to hosts.
- `spec/relaymark/contract.json` owns the single canonical editor/sync
  compatibility identity. Conformance envelopes and the generated JavaScript,
  Elixir and Swift bindings use that same contract; the AST carries no separate
  version. Package versions keep their ecosystem meaning.
- Packages stay on 0.x and bump only the patch digit, even for breaking
  changes.
- Strict semantic-version tags release the reference runtime and root Swift
  package. `elixir-<version>` tags identify the Hex source for
  `relay_mark_elixir`; a tag never publishes to Hex.
- For collaborative editing, start with
  [docs/OFFLINE_MULTIPLAYER.md](docs/OFFLINE_MULTIPLAYER.md). Prefer maintained
  community components (Yjs, ProseMirror, TipTap) over custom infrastructure.
- Ported third-party code keeps its upstream copyright and license notice and
  an entry in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- Use focused checks during implementation. Documentation-only changes need
  link and diff validation. Once a commit is pushed, don't amend, rebase or
  force-push it; make a corrective commit.
