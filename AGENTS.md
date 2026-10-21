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
- Editor behavior has one platform-neutral owner. Input rules, slash and
  editing commands, marks and their shortcuts live in relaymark-core and the
  shared Swift editor model, and the UIKit (iOS, iPadOS, visionOS) and AppKit
  (macOS) text views are thin adapters that map events into it. Never define a
  command, input rule or menu item in only one adapter. A test runs the shared
  catalog through every adapter, so a behavior missing on one Apple platform
  fails the build instead of shipping.
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
