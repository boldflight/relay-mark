# One Rust library on Apple platforms

The Swift package links exactly one Rust library. It follows the "megazord"
pattern of Mozilla's application-services (`megazords/ios-rust`): Rust
components stay separate crates, and they are combined only when packaged.
`crates/relaymark-apple` is built once as a static library and shipped as
`RelayMarkFFI.xcframework` by `scripts/build-swift-engine.zsh`.

**Rule:** a new Rust library for the Apple platforms joins this megazord as
its own crate. Never ship a second Rust staticlib, xcframework or dynamic
framework in the package or the apps.

## Why one library

A Rust staticlib carries its own copy of the Rust standard library. An app
that links two of them has two runtimes, and the link fails on duplicate
unmangled symbols such as `rust_eh_personality`. Until October 2026 the
package linked relaymark-ffi's static library and yswift's static `yniffi`,
so every macOS test bundle failed to link. A dynamic framework links but
still ships two standard libraries. Symbol renaming, `panic = "abort"` and
`-Zstaticlib-rename-internal-symbols` are nightly-only or fragile, so we
don't use them. Building one staticlib from every crate gives one standard
library, one uniffi runtime and one copy of each shared dependency.

## Structure

| Crate | Role | Swift module on top |
| --- | --- | --- |
| `crates/relaymark-core` | The format engine; also used by the Elixir NIF and WebAssembly. It doesn't depend on yrs. | none |
| `crates/relaymark-ffi` | uniffi binding of relaymark-core | `RelayMarkEngine`, wrapped by `RelayMarkSwift` |
| `crates/yniffi` | uniffi binding of yrs, vendored from [boldflight/yswift](https://github.com/boldflight/yswift) | `Yniffi`, wrapped by `YSwift` |
| `crates/relaymark-apple` | The megazord: depends on and re-exports the binding crates, with no logic of its own | binary target `RelayMarkFFI` |

- **Separate crates.** relaymark-core, relaymark-ffi and yniffi keep their own
  APIs and tests. Only `relaymark-apple` has `crate-type = ["staticlib"]`.
  Release builds use the workspace's `lto = true` and `codegen-units = 1`,
  so the combined library is optimized and dead-stripped across crates.
- **Shared dependencies.** All bindings use one uniffi version, the
  workspace's. `cargo tree -d -p relaymark-apple -e normal --target
  aarch64-apple-ios` should list no runtime crate twice, except where an
  upstream crate pins its own (yrs's `dashmap` uses an older `hashbrown`).
- **One C module.** A uniffi component can name only one framework module,
  so every binding's `uniffi.toml` sets `ffi_module_name = "RelayMarkFFI"`
  and varies only `ffi_module_filename`. The xcframework has one static
  library per slice (macOS, iOS, iOS simulator, visionOS, visionOS
  simulator) and one header folder, `Headers/RelayMarkFFI/`. That folder
  holds each binding's header, the umbrella header `RelayMarkFFI.h` and one
  `module.modulemap`.
- **Separate Swift modules.** Each binding's generated Swift file is its own
  target (`RelayMarkEngine`, `Yniffi`) importing `RelayMarkFFI`. Neither
  Swift layer imports the other's. YSwift's sources and tests compile in the
  Swift 5 language mode they were written for.

`crates/yniffi` keeps yrs at the exact revision yswift used
(`boldflight/y-crdt`, Yrs 0.28.0 with Relay's patches), the one the Apple
clients collaborate with the server's Yex on. Change it only with a check
against the server, since yrs produces the Yjs updates both sides exchange.

## Adding a Rust library

1. Add a library crate under `crates/` with its own tests and
   `uniffi::setup_scaffolding!()` (or a UDL file). Don't give it a
   `staticlib` or `cdylib` crate type, and use the workspace's uniffi
   version.
2. Give it a `uniffi.toml` with `ffi_module_name = "RelayMarkFFI"` and its own
   `ffi_module_filename`.
3. Depend on it from `crates/relaymark-apple/Cargo.toml` and re-export it in
   `crates/relaymark-apple/src/lib.rs` (`pub use new_crate;`).
4. Add it to the binding loop in `scripts/build-swift-engine.zsh`. The script
   fails while any generated binding is unplaced or imports another module.
   Then add a Swift target over `RelayMarkFFI` for the generated file in
   `Package.swift`.
5. Rebuild with `scripts/build-swift-engine.zsh`, test with
   `RELAYMARK_LOCAL_ENGINE=1`, and publish once.

## Checking for a single runtime

After a build, the library and anything linked against it should define
`rust_eh_personality` exactly once and carry one `std` crate id:

```sh
lib=target/swift-engine/RelayMarkFFI.xcframework/macos-arm64/librelaymark_apple.a
nm -gU $lib | grep -c ' T _rust_eh_personality'
nm $lib | grep -oE 'Cs[0-9A-Za-z]+_3std' | sort -u
```

Run the same checks on an app or test bundle binary. A second definition or
a second `std` id means another Rust staticlib entered the link.
