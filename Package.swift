// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "RelayMark",
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
            dependencies: ["RelayMarkModel", "RelayMarkProseProjection", "RelayMarkSwift", .product(name: "YSwift", package: "yswift")],
            path: "adapters/swift/Sources/RelayMarkNativeCollaboration"
        ),
        .target(
            name: "RelayMarkEditor",
            dependencies: ["RelayMarkCollaboration", "RelayMarkNativeCollaboration", "RelayMarkProseProjection", "RelayMarkSwift"],
            path: "adapters/swift/Sources/RelayMarkEditor"
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
