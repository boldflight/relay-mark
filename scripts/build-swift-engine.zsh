#!/bin/zsh
# Builds relaymark-core for the Swift package: static libraries for every Apple
# platform the package supports (Apple silicon only), the uniffi Swift binding,
# and adapters/swift/RelayMarkFFI.xcframework. Run after changing the engine;
# commit the framework and the generated binding together.
set -euo pipefail

root=${0:A:h:h}
cd $root

targets=(aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin aarch64-apple-visionos aarch64-apple-visionos-sim)
work=target/swift-engine
framework=adapters/swift/RelayMarkFFI.xcframework
binding=adapters/swift/Sources/RelayMarkEngine

rustup target add $targets >/dev/null
for target in $targets; do
  cargo build --locked --release -p relaymark-ffi --target $target
done

rm -rf $work
# Headers in their own folder: a package's xcframeworks share one include
# directory, and yswift's module.modulemap is already at its root.
mkdir -p $work/headers/relaymark_ffiFFI
cargo run --locked --release -p relaymark-ffi --features bindgen --bin uniffi-bindgen -- \
  generate --library target/aarch64-apple-darwin/release/librelaymark_ffi.a --language swift --out-dir $work/generated
mv $work/generated/relaymark_ffiFFI.h $work/headers/relaymark_ffiFFI/
mv $work/generated/relaymark_ffiFFI.modulemap $work/headers/relaymark_ffiFFI/module.modulemap
mkdir -p $binding
mv $work/generated/relaymark_ffi.swift $binding/RelayMarkFFI.swift

libraries=()
for target in $targets; do
  mkdir -p $work/$target
  # Debug symbols are most of each archive and no app ships them.
  strip -S -o $work/$target/librelaymark_ffi.a target/$target/release/librelaymark_ffi.a
  libraries+=(-library $work/$target/librelaymark_ffi.a -headers $work/headers)
done

rm -rf $framework
xcodebuild -create-xcframework $libraries -output $framework
rm -rf $work
