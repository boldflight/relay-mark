#!/bin/zsh
# Builds relaymark-core for the Swift package: static libraries for every Apple
# platform the package supports (Apple silicon only), the uniffi Swift binding,
# and target/swift-engine/RelayMarkFFI.xcframework with its zip and checksum.
#
#   scripts/build-swift-engine.zsh            build only; RELAYMARK_LOCAL_ENGINE=1
#                                             makes the package use this build
#   scripts/build-swift-engine.zsh --publish  also upload the zip as release
#                                             engine-<commit> and point
#                                             Package.swift at it
#
# The framework is never committed: Package.swift names the release asset by
# URL and checksum. Publish from a commit whose engine is committed, then
# commit Package.swift with the generated binding.
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
binding=adapters/swift/Sources/RelayMarkEngine

rustup target add $targets >/dev/null
for target in $targets; do
  cargo build --locked --release -p relaymark-ffi --target $target
done

rm -rf $out
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
