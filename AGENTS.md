# RelayMark repository guidance

## Git worktree layout

- Keep the primary checkout at `<parent>/relay-mark` on `main` for routine work and releases.
- Put substantial or isolated branch work in `<parent>/relay-mark-worktrees/<branch-purpose>`; keep the directory purpose aligned with its branch and remove the worktree after verified integration.
- Never create persistent worktrees inside this repository or under hidden, generated, cache, or tool-owned directories such as `.firecrawl`, `.codex`, `.claude`, `.worktrees`, build output, or `/tmp`.
- Use registered `git worktree` commands and absolute paths. Commit coherent checkpoints before interruption risks and push branches that must survive local disk loss.

RelayMark is maintained directly on `main` while the team has one maintainer.
Branches and pull requests are optional tools for work that needs isolation or
outside review; do not create them solely to manufacture a release merge.

Any commit on `main` is a valid release-tag target once release metadata is
current and the relevant JavaScript, conformance, Swift, Elixir, and
package-consumer checks pass. Keep CI healthy and inspect it after pushing, but
CI does not require a ceremonial pull request.

The portable conformance-suite version is the cross-runtime compatibility
identity. Distribution versions are independent:

- Strict semantic-version tags such as `0.5.3` release the repository reference
  runtime and root `RelayMarkSwift` package.
- Tags such as `elixir-0.5.3` identify the independently versioned
  `relay_mark_elixir` source released to Hex.

Those versions may coincide, but no gate should require them to match. Every
release must state which portable conformance version it implements. A Git tag
does not publish Hex; prepare and tag the Elixir adapter, then let the release
operator run `mix hex.publish` with their own Hex credentials.

From the current 0.5 contract baseline through the rest of the pre-1.0 line,
RelayMark preserves valid document meaning and public adapter source
compatibility. Additive contract features and deprecations may ship in 0.x;
breaking changes are reserved for 1.0.

Active first-party Relay consumers follow this repository's `main` branch
during fast-moving pre-1.0 development and must not commit a first-party lock
snapshot that silently holds them behind it. Tags and ecosystem lockfiles remain
appropriate for external or intentionally stabilized consumers. Introduce a
minimum version, exact revision, or narrower range only for a demonstrated
incompatibility or release boundary; policy files must not duplicate resolved
versions or revisions.
