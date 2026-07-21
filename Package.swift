// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RelayMark",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
        .visionOS("26.0")
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
