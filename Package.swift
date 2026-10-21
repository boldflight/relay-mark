// swift-tools-version: 6.4

import Foundation
import PackageDescription

// The package's one Rust library, the crates/relaymark-apple megazord
// (relaymark-ffi and yniffi under one C module, RelayMarkFFI), built and
// published by scripts/build-swift-engine.zsh as a release asset.
// RELAYMARK_LOCAL_ENGINE=1 uses the script's local build instead.
let engineURL = "https://github.com/boldflight/relay-mark/releases/download/engine-98b442011a3e/RelayMarkFFI.xcframework.zip"
let engineChecksum = "51290afae048dfffc668a55908d7e151ceb24976d43ed3f738d1ffdba7f5c62a"
let engine: Target = ProcessInfo.processInfo.environment["RELAYMARK_LOCAL_ENGINE"] == nil
    ? .binaryTarget(name: "RelayMarkFFI", url: engineURL, checksum: engineChecksum)
    : .binaryTarget(name: "RelayMarkFFI", path: "target/swift-engine/RelayMarkFFI.xcframework")

let package = Package(
    name: "RelayMark",
    defaultLocalization: "en",
    platforms: [
        .macOS("27.0"),
        .iOS("27.0"),
        .visionOS("27.0")
    ],
    products: [
        .library(name: "RelayMarkSwift", targets: ["RelayMarkSwift"]),
        .library(name: "RelayMarkCollaboration", targets: ["RelayMarkCollaboration"]),
        .library(name: "RelayMarkProseProjection", targets: ["RelayMarkProseProjection"]),
        .library(name: "RelayMarkModel", targets: ["RelayMarkModel"]),
        .library(name: "RelayMarkNativeCollaboration", targets: ["RelayMarkNativeCollaboration"]),
        .library(name: "RelayMarkEditor", targets: ["RelayMarkEditor"])
    ],
    targets: [
        .target(
            name: "RelayMarkCollaboration",
            dependencies: ["RelayMarkProseProjection"],
            path: "adapters/swift/Sources/RelayMarkCollaboration"
        ),
        .target(
            name: "RelayMarkModel",
            path: "adapters/swift/Sources/RelayMarkModel"
        ),
        .testTarget(
            name: "RelayMarkModelTests",
            dependencies: ["RelayMarkModel"],
            path: "adapters/swift/Tests/RelayMarkModelTests"
        ),
        .target(
            name: "RelayMarkNativeCollaboration",
            dependencies: ["RelayMarkModel", "RelayMarkProseProjection", "RelayMarkSwift", "YSwift"],
            path: "adapters/swift/Sources/RelayMarkNativeCollaboration"
        ),
        .target(
            name: "RelayMarkEditor",
            dependencies: ["RelayMarkCollaboration", "RelayMarkNativeCollaboration", "RelayMarkProseProjection", "RelayMarkSwift"],
            path: "adapters/swift/Sources/RelayMarkEditor",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RelayMarkEditorTests",
            dependencies: ["RelayMarkEditor", "RelayMarkNativeCollaboration", "RelayMarkCollaboration", "RelayMarkProseProjection", "RelayMarkSwift"],
            path: "adapters/swift/Tests/RelayMarkEditorTests",
            resources: [.copy("Fixtures")]
        ),

        .target(
            name: "RelayMarkProseProjection",
            dependencies: ["RelayMarkSwift"],
            path: "adapters/swift/Sources/RelayMarkProseProjection"
        ),
        .testTarget(
            name: "RelayMarkNativeCollaborationTests",
            dependencies: ["RelayMarkModel", "RelayMarkNativeCollaboration", "RelayMarkCollaboration"],
            path: "adapters/swift/Tests/RelayMarkNativeCollaborationTests",
            resources: [.process("Fixtures")]
        ),
        engine,
        .target(
            name: "RelayMarkEngine",
            dependencies: ["RelayMarkFFI"],
            path: "adapters/swift/Sources/RelayMarkEngine"
        ),
        // YSwift, vendored from boldflight/yswift, over the yrs binding in the engine.
        .target(
            name: "Yniffi",
            dependencies: ["RelayMarkFFI"],
            path: "adapters/swift/Sources/Yniffi",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "YSwift",
            dependencies: ["Yniffi"],
            path: "adapters/swift/Sources/YSwift",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "YSwiftTests",
            dependencies: ["YSwift"],
            path: "adapters/swift/Tests/YSwiftTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "RelayMarkSwift",
            dependencies: ["RelayMarkEngine"],
            path: "adapters/swift/Sources/RelayMarkSwift"
        ),
        .testTarget(
            name: "RelayMarkSwiftTests",
            dependencies: ["RelayMarkSwift"],
            path: "adapters/swift/Tests/RelayMarkSwiftTests"
        )
    ]
)
