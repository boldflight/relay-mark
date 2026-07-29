# RelayMark repository guidance

RelayMark is maintained directly on `main` while the team has one maintainer.
Branches and pull requests are optional tools for work that needs isolation or
outside review; do not create them solely to manufacture a release merge.

Any commit on `main` is a valid semantic-version tag target once release
metadata is current and the relevant JavaScript, conformance, Swift, Elixir,
and package-consumer checks pass. Keep CI healthy where configured and inspect
it after pushing, but CI does not require a ceremonial pull request. Create
annotated tags directly on the verified `main` commit.

Swift consumers use the repository tag. Elixir consumers use the separately
published `relay_mark_elixir` Hex package. A Git tag does not publish Hex;
prepare the matching adapter version and package contents, then let the release
operator run `mix hex.publish` with their own Hex credentials.
