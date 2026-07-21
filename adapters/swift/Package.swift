// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "RelayMarkSwift",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "RelayMarkSwift", targets: ["RelayMarkSwift"])
    ],
    targets: [
        .target(name: "RelayMarkSwift"),
        .testTarget(name: "RelayMarkSwiftTests", dependencies: ["RelayMarkSwift"])
    ]
)
