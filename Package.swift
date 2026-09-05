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
        .library(name: "RelayMarkCollaboration", targets: ["RelayMarkCollaboration"])
    ],
    targets: [
        .target(
            name: "RelayMarkCollaboration",
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
