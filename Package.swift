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
        .package(url: "https://github.com/boldflight/yswift.git", revision: "3c4837081884f96e15e81ce9064e8ac885c7aa92"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0")
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
            dependencies: ["RelayMarkProseProjection", "RelayMarkSwift", .product(name: "YSwift", package: "yswift"),
                           .product(name: "Markdown", package: "swift-markdown")],
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
