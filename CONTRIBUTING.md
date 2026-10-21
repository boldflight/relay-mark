# Contributing to RelayMark

RelayMark is a portable document grammar with a JavaScript reference runtime,
a Rust engine (`relaymark-core`) and Swift and Elixir adapters. The
specification and conformance fixtures under `spec/relaymark/` define
cross-runtime meaning; every runtime must agree with them.

## Requirements

- Node.js 20 or newer
- Rust, at the version pinned in `rust-toolchain.toml`
- Elixir 1.18 or newer with Erlang/OTP 27, for the Elixir adapter
- Xcode 27.1 (Swift 6.4) on macOS, for the Swift package

## Build and test

```sh
npm install
npm test                      # reference runtime
npm run conformance           # portable conformance suite
npm run check:contract        # contract identity across bindings
cargo test                    # Rust engine: fixtures and reference oracle
swift test                    # Swift package
(cd adapters/elixir && mix deps.get && mix test)
npm run check                 # contract, runtime, conformance and both adapters
```

`npm run build:collaboration` regenerates the bundled JavaScript runtimes under
`adapters/swift/Sources/RelayMarkSwift/Resources/` and
`adapters/elixir/priv/collaboration/`. Commit the regenerated files together
with the source change that produced them.

## Conformance fixtures

`spec/relaymark/conformance/suite.json` indexes the fixtures every runtime
executes. Examples in `spec/relaymark/examples/` pair RelayMark source with
its expected AST and manifest. Collaboration fixtures live under
`spec/relaymark/collaboration/`.

A change to document meaning starts in the specification: update the spec and
its fixtures, then make every runtime pass them. The Rust engine must stay
byte-identical to the reference runtime; `crates/relaymark-core/tests/differential.rs`
replays recorded reference calls to check this. Documented, intentional
differences are listed in the README.

Keep host concerns out of the grammar. Authorization, persistence, routes,
navigation and application UI belong to the applications that embed RelayMark.

## Pull requests

- Keep each change focused, with tests that would fail without it.
- Run `git diff --check` and the checks relevant to your change.
- Describe what changed in document behavior, if anything, and which runtimes
  you verified.

## Licensing of contributions

RelayMark is licensed under either of the [MIT License](LICENSE-MIT) or the
[Apache License, Version 2.0](LICENSE-APACHE), at your option.

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall
be dual licensed as above, without any additional terms or conditions.

Sign off each commit (`git commit -s`) to certify the
[Developer Certificate of Origin 1.1](https://developercertificate.org/): that
you wrote the change, or otherwise have the right to submit it under these
licenses. Code ported from other projects must keep its original copyright
and license notices, and needs an entry in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
