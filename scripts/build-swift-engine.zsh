#!/bin/zsh
# Builds the Swift package's one Rust library, crates/relaymark-apple: a static
# library for every Apple platform the package supports (Apple silicon only),
# the uniffi Swift bindings of every crate it re-exports (relaymark-ffi and
# yniffi), and target/swift-engine/RelayMarkFFI.xcframework with its zip and
# checksum. One staticlib means one Rust standard library in every app; see
# docs/engineering/apple-rust-library.md.
#
#   scripts/build-swift-engine.zsh            build only; RELAYMARK_LOCAL_ENGINE=1
#                                             makes the package use this build
#   scripts/build-swift-engine.zsh --publish  also upload the zip as release
#                                             engine-<commit> and point
#                                             Package.swift at it
#
# The framework is never committed: Package.swift names the release asset by
# URL and checksum. Publish from a commit whose engine is committed, then
# commit Package.swift with the generated bindings.
set -euo pipefail

root=${0:A:h:h}
cd $root

publish=false
[[ ${1:-} == --publish ]] && publish=true
repository=boldflight/relay-mark
if $publish && [[ -n $(git status --porcelain -- crates Cargo.toml Cargo.lock) ]]; then
  print -u2 "Commit the engine before publishing it."
  exit 1
fi

targets=(aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin aarch64-apple-visionos aarch64-apple-visionos-sim)
out=target/swift-engine
work=$out/work
framework=$out/RelayMarkFFI.xcframework
archive=$out/RelayMarkFFI.xcframework.zip
sources=adapters/swift/Sources

rustup target add $targets >/dev/null
for target in $targets; do
  cargo build --locked --release -p relaymark-apple --target $target
done

rm -rf $out
cargo run --locked --release -p relaymark-apple --features bindgen --bin uniffi-bindgen -- \
  generate --library target/aarch64-apple-darwin/release/librelaymark_apple.a --language swift --out-dir $work/generated
# Each binding's C module in a folder of its own name, where the Swift
# compiler finds its module map: one include directory serves them all.
for module source in relaymark_ffi $sources/RelayMarkEngine/RelayMarkFFI.swift yniffi $sources/Yniffi/Yniffi.swift; do
  mkdir -p $work/headers/${module}FFI ${source:h}
  mv $work/generated/${module}FFI.h $work/headers/${module}FFI/
  mv $work/generated/${module}FFI.modulemap $work/headers/${module}FFI/module.modulemap
  mv $work/generated/$module.swift $source
done
if [[ -n $(ls $work/generated) ]]; then
  print -u2 "Unplaced bindings: $(ls $work/generated). Add each new binding to the loop above."
  exit 1
fi

libraries=()
for target in $targets; do
  mkdir -p $work/$target
  # Debug symbols are most of each archive and no app ships them.
  strip -S -o $work/$target/librelaymark_apple.a target/$target/release/librelaymark_apple.a
  libraries+=(-library $work/$target/librelaymark_apple.a -headers $work/headers)
done

xcodebuild -create-xcframework $libraries -output $framework
rm -rf $work
ditto -c -k --norsrc --keepParent $framework $archive
checksum=$(xcrun swift package compute-checksum $archive)

if $publish; then
  tag=engine-$(git rev-parse --short=12 HEAD)
  gh release create $tag $archive -R $repository --target $(git rev-parse HEAD) --prerelease \
    --title "Swift engine $tag" --notes "relaymark-core for the Swift package, built by scripts/build-swift-engine.zsh."
  url=https://github.com/$repository/releases/download/$tag/RelayMarkFFI.xcframework.zip
  sed -i '' -E \
    -e "s#^let engineURL = \".*\"#let engineURL = \"$url\"#" \
    -e "s#^let engineChecksum = \".*\"#let engineChecksum = \"$checksum\"#" Package.swift
  print "url: $url"
fi
print "checksum: $checksum"
