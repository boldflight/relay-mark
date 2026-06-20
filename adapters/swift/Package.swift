// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RelayMarkSwift",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "RelayMarkSwift", targets: ["RelayMarkSwift"])
    ],
    targets: [
        .target(name: "RelayMarkSwift"),
        .testTarget(name: "RelayMarkSwiftTests", dependencies: ["RelayMarkSwift"])
    ]
)
