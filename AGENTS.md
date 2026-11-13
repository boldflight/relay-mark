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
- Releases follow [the release runbook](docs/engineering/release.md). Before
  anyone is asked to publish, `scripts/check-elixir-package.sh` must pass from
  a clean state: docs build with zero warnings, and the built package compiles
  as a dependency. Publish from a fresh worktree at the release commit, never
  from a checkout with old build output.
- Form question settings are one aggregate `settings` attribute; never reintroduce per-key `settings:<key>` storage (it killed performance; Douglas, 2026-11-02). See [docs/engineering/settings-encoding-decision.md](docs/engineering/settings-encoding-decision.md).
- For collaborative editing, start with
  [docs/OFFLINE_MULTIPLAYER.md](docs/OFFLINE_MULTIPLAYER.md). Prefer maintained
  community components (Yjs, ProseMirror, TipTap) over custom infrastructure.
- Ported third-party code keeps its upstream copyright and license notice and
  an entry in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- Use focused checks during implementation. Documentation-only changes need
  link and diff validation. Once a commit is pushed, don't amend, rebase or
  force-push it; make a corrective commit.

- Apple builds use the latest stable Xcode and its bundled Swift toolchain. Never
  pin an exact Xcode version in policy or automation; newer stable releases are
  adopted without a policy edit (Douglas, November 6, 2026).

## Native text editing primitives — standing rule (Douglas, 2026-11-13)

This rule supersedes earlier feature-parity directions or examples that encourage
custom native text layout. Apply it to the entire Apple editor stack, including
app hosts, RelayMark adapters, read-only projections and auxiliary editors.

- Text rendering, shaping, wrapping, line/paragraph layout, caret placement,
  selection, hit testing, list-marker placement and scrolling primitives must
  come from Apple's documented text system or a deliberately selected,
  established, maintained library. Keep the surrounding paper on TextKit 2.
  Douglas approved one explicitly initialized Apple TextKit 1 text view per
  table on November 13, 2026. Use `NSTextTable`/`NSTextTableBlock` and native
  controls and measurements there; never let a table downgrade the paper view.
  Cell edits, structural commands and undo still use the shared canonical engine
  and collaboration history. This exception does not permit custom geometry.
- ZERO bespoke text geometry or layout algorithms: no guessed line heights,
  reconstructed glyph/character rectangles, nearest-character loops, manually
  positioned bullets/numbers/carets, click-offset corrections, parallel layout
  caches, or layout-forcing work inside drawing to imitate web features. Do not
  move that code into another helper, package, or an agent-authored framework.
- Thin adapters may map canonical document ranges to native ranges, set supported
  attributes, consume framework-provided geometry and use standard coordinate
  conversion APIs at view boundaries. That is integration, not permission to
  synthesize replacement geometry or build a second selection/layout engine.
- Keep the universal Rust engine, canonical RelayMark/ProseMirror/Yjs meaning,
  web compatibility, authorization and durable edits. Audit custom code; do not
  discard domain adapters merely because they are ours. Native presentation
  need not replicate every web feature. Prefer a supported simpler presentation,
  preserved noneditable content or an explicitly deferred capability to a hack.
  Never flatten or lose unsupported nodes during editing or save.
- Evaluate Apple primitives first, then maintained libraries against actual
  platform coverage, integration fit, maintenance and licensing. Cite the owning
  API or upstream implementation for the chosen primitive. Inspiration from a
  project is not permission to copy its custom geometry or maintain a local fork.
  No new geometry workaround or fallback engine without Douglas's explicit
  decision; surface the unsupported feature or upstream defect instead.
- Correct foundations take priority over elaborate regression infrastructure.
  Do not add a custom layout engine and try to legitimize it with more tests.
  Retain proportionate integration/conformance checks for our document bridge,
  composition, undo, synchronization and data preservation, plus a small real
  editing check for changed behavior. Using a library reduces risk; it does not
  prove our integration correct. Existing release gates remain applicable.
- Douglas accepted TextKit 2's roughly 200 ms edit cost for 1 MB native lists on
  November 13, 2026. Keep native list grouping and the documented limitation;
  the native-list test checks correctness/convergence and records timing rather
  than asserting constant-time system layout. Engine/bridge and all other
  performance gates remain in force. Do not reintroduce custom geometry or
  fragment lists to evade this accepted platform limit.

See [the editor foundation plan](docs/plans/2026-11-13-native-editor-foundation.md) for the audit, candidate evaluation and proposed implementation sequence.
