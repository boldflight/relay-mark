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
        .package(url: "https://github.com/boldflight/yswift.git", revision: "bc3f4cf08336cd2f0cf6e1ae6d53d03c4a88f5ca")
    ],
    targets: [
        .target(
            name: "RelayMarkCollaboration",
            dependencies: ["RelayMarkProseProjection"],
            path: "adapters/swift/Sources/RelayMarkCollaboration",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RelayMarkCollaborationTests",
            dependencies: ["RelayMarkCollaboration"],
            path: "adapters/swift/Tests/RelayMarkCollaborationTests",
            resources: [.process("Fixtures")]
        ),
        .target(
            name: "RelayMarkNativeCollaboration",
            dependencies: ["RelayMarkProseProjection", .product(name: "YSwift", package: "yswift")],
            path: "adapters/swift/Sources/RelayMarkNativeCollaboration"
        ),
        .target(
            name: "RelayMarkProseProjection",
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
            path: "adapters/swift/Sources/RelayMarkSwift"
        ),
        .testTarget(
            name: "RelayMarkSwiftTests",
            dependencies: ["RelayMarkSwift"],
            path: "adapters/swift/Tests/RelayMarkSwiftTests"
        )
    ]
)
