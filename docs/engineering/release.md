# Releasing RelayMark

RelayMark ships two artifacts from one commit:

- **A.** `relay_mark_elixir` on Hex, tagged `elixir-<version>`. The server depends on it.
- **B.** The Swift engine (`RelayMarkFFI.xcframework`) as GitHub release `engine-<short commit>`, which `Package.swift` pins. The Apple apps follow `main`.

Versions stay 0.x and bump only the patch digit. A tag never publishes anything by itself.

## 0. Release gate

Run this first, from a fresh worktree at the release commit. Never run it from a checkout that holds old build output.

```sh
git worktree add ../relay-mark-worktrees/release-<version> <release-commit>
cd ../relay-mark-worktrees/release-<version>
npm ci
scripts/check-elixir-package.sh
```

The script starts clean: it deletes `native/relaymark`, `_build`, `deps` and `doc`. Then it checks two things.

- **Docs:** they must build with zero warnings (`MIX_ENV=dev mix docs --warnings-as-errors`).
- **Package:** it runs `mix hex.build --unpack`, then compiles the unpacked package as a path dependency of a scratch Mix project and calls the engine.

It must pass before anyone is asked to publish. CI runs the same script on every push.

Why it exists: relay_mark_elixir 0.7.5 was published from a primary checkout whose gitignored engine copy (`adapters/elixir/native/relaymark`) was stale. The package lacked three engine modules, and the NIF failed to compile for everyone. Since 0.7.6, `adapters/elixir/native_mirror.exs` rebuilds that copy from scratch on every `mix hex.build` and `mix hex.publish`, and fails if a declared module or included file is missing. The gate proves the built package compiles.

Also run the full checks once on the release commit: `npm test`, `npm run conformance`, `npm run check:contract`, `cargo test -j 4 --workspace`, `cd adapters/elixir && mix test`, and `RELAYMARK_LOCAL_ENGINE=1 xcrun swift test -j 4` after `scripts/build-swift-engine.zsh`.

## A. relay_mark_elixir to Hex

The release commit bumps `@version` in `adapters/elixir/mix.exs` and adds its `adapters/elixir/CHANGELOG.md` entry. From the same fresh worktree:

```sh
cd adapters/elixir
mix hex.build --unpack        # the alias rebuilds native/relaymark; inspect the file list
mix hex.publish               # shows the file list, asks to confirm, then Hex auth
cd ../..
git tag -a elixir-<version> -m "relay_mark_elixir <version>" <release-commit>
git push origin elixir-<version>
```

## B. Swift engine release

```sh
scripts/build-swift-engine.zsh --publish
```

This refuses to run if `crates/`, `Cargo.toml` or `Cargo.lock` are dirty. It builds `RelayMarkFFI.xcframework` directly from `crates/`, uploads it as GitHub release `engine-<short commit>`, and rewrites the URL and checksum in `Package.swift`. Commit that, with any generated bindings it reports:

```sh
git add Package.swift adapters/swift/Sources/<generated bindings it reports>
git commit -m "Point the Swift package at the engine-<sha> release"
git push origin main
```

The engine does not use `native/relaymark`, so the Elixir mirror problem cannot affect it.

## C. Consumers

- **relay-elixir:** raise `{:relay_mark_elixir, ">= <version>"}` and update `mix.lock`.
- **relay-swift:** follows relay-mark `main`, so it only needs a fresh package resolve.
