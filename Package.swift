// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "RelayMark",
    platforms: [
        .macOS("26.6"),
        .iOS("26.6"),
        .visionOS("26.6")
    ],
    products: [
        .library(name: "RelayMarkSwift", targets: ["RelayMarkSwift"])
    ],
    targets: [
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
