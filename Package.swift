// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "RelayMark",
    platforms: [
        .macOS("26.5"),
        .iOS("26.5"),
        .visionOS("26.5")
    ],
    products: [
        .library(name: "RelayMarkSwift", targets: ["RelayMarkSwift"]),
        .library(name: "RelayMarkCollaboration", targets: ["RelayMarkCollaboration"]),
        .library(name: "RelayMarkProseProjection", targets: ["RelayMarkProseProjection"]),
        .library(name: "RelayMarkNativeCollaboration", targets: ["RelayMarkNativeCollaboration"])
    ],
    dependencies: [
        .package(url: "https://github.com/boldflight/yswift.git", revision: "6c8f3baa6fbd8706a9cdd0ea989dd6df34590789")
    ],
    targets: [
        .target(
            name: "RelayMarkCollaboration",
            dependencies: ["RelayMarkProseProjection"],
            path: "adapters/swift/Sources/RelayMarkCollaboration"
        ),
        .target(
            name: "RelayMarkNativeCollaboration",
            dependencies: ["RelayMarkProseProjection", "RelayMarkSwift", .product(name: "YSwift", package: "yswift")],
            path: "adapters/swift/Sources/RelayMarkNativeCollaboration"
        ),
        .target(
            name: "RelayMarkProseProjection",
            dependencies: ["RelayMarkSwift"],
            path: "adapters/swift/Sources/RelayMarkProseProjection"
        ),
        .testTarget(
            name: "RelayMarkNativeCollaborationTests",
            dependencies: ["RelayMarkNativeCollaboration", "RelayMarkCollaboration"],
            path: "adapters/swift/Tests/RelayMarkNativeCollaborationTests",
            resources: [.process("Fixtures")]
        ),
        .target(
            name: "RelayMarkSwift",
            path: "adapters/swift/Sources/RelayMarkSwift",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RelayMarkSwiftTests",
            dependencies: ["RelayMarkSwift"],
            path: "adapters/swift/Tests/RelayMarkSwiftTests"
        )
    ]
)
