# RelayMark repository guidance

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

Swift consumers should use an explicit `"0.5.3"..<"1.0.0"` range and commit
`Package.resolved` so the promised compatibility line is visible at the
declaration site. Elixir consumers should use an explicit compatible
`>= 0.5.3 and < 1.0.0` range and commit `mix.lock`. Lockfiles record the exact
reproducible build; policy files must not duplicate those resolved versions or
revisions.
