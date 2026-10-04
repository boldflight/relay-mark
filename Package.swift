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
        .package(url: "https://github.com/boldflight/yswift.git", revision: "73666ada5aa9f9d461647db57359e2454f058bd3"),
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
