# One Rust library on Apple platforms

The Swift package links exactly one Rust library: `crates/relaymark-apple`,
built as a static library and shipped as `RelayMarkFFI.xcframework` by
`scripts/build-swift-engine.zsh`. Every Rust binding the Apple platforms need
joins this library. No Swift package in Relay's apps ships a second Rust
binary.

## Why one library

A Rust staticlib carries its own copy of the Rust standard library. An app
that links two of them has two runtimes, and the link fails on duplicate
unmangled symbols such as `rust_eh_personality`. Until October 2026 the
package linked relaymark-ffi's static library and yswift's static `yniffi`,
and every macOS test bundle failed to link. Wrapping one of them in a dynamic
framework links, but still ships two standard libraries and repeats the
problem for every later Rust library.

## Structure

| Crate | Kind | Swift module |
| --- | --- | --- |
| `crates/relaymark-core` | Rust library: the format engine, also used by the Elixir NIF and WebAssembly | none |
| `crates/relaymark-ffi` | uniffi binding of relaymark-core (library crate) | `RelayMarkEngine` over C module `relaymark_ffiFFI` |
| `crates/yniffi` | uniffi binding of yrs, vendored from [boldflight/yswift](https://github.com/boldflight/yswift) (library crate) | `Yniffi` over C module `yniffiFFI`, wrapped by `YSwift` |
| `crates/relaymark-apple` | `staticlib` that re-exports every binding crate | binary target `RelayMarkFFI` |

Only `relaymark-apple` is a staticlib. The binding crates are plain Rust
libraries, so they share one standard library, one uniffi runtime and one
copy of every common dependency. The build script runs uniffi's bindgen in
library mode over the combined static library, which writes one Swift file and
one C module per binding crate. Each C module's header and module map go in a
folder named after the module inside the xcframework's single include
directory.

`crates/yniffi` keeps yrs at the exact revision yswift used
(`boldflight/y-crdt`, Yrs 0.28.0 with Relay's patches), the one the Apple
clients collaborate with the server's Yex on. Change it only with a check
against the server, since yrs produces the Yjs updates both sides exchange. The YSwift Swift sources live in `adapters/swift/Sources/YSwift`, with
their tests in `adapters/swift/Tests/YSwiftTests`; both compile in the Swift 5
language mode they were written for.

## Adding a Rust library

1. Add a library crate under `crates/` with `uniffi::setup_scaffolding!()` (or
   a UDL file). Do not give it a `staticlib` or `cdylib` crate type, and use
   the workspace's uniffi version.
2. Depend on it from `crates/relaymark-apple/Cargo.toml` and re-export it in
   `crates/relaymark-apple/src/lib.rs` (`pub use new_crate;`).
3. Add its module to the binding loop in `scripts/build-swift-engine.zsh`,
   which fails while any generated binding is unplaced, and add a Swift target
   over `RelayMarkFFI` for the generated file in `Package.swift`.
4. Rebuild with `scripts/build-swift-engine.zsh`, test with
   `RELAYMARK_LOCAL_ENGINE=1`, and publish once.

## Checking for a single runtime

After a build, the static library and anything linked against it should
define `rust_eh_personality` exactly once:

```sh
nm -gU target/swift-engine/RelayMarkFFI.xcframework/macos-arm64/librelaymark_apple.a | grep -c ' T _rust_eh_personality'
```

A second definition, in the archive or in a linked app or test bundle, means
another Rust staticlib entered the link.
