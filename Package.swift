// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TrysteroSwift",
    platforms: [
        .iOS(.v13),
        .macOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "TrysteroSwift",
            targets: ["TrysteroSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", branch: "release-M137"),
        .package(url: "https://github.com/Galaxoid-Labs/NostrClient.git", branch: "main")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "TrysteroSwift",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC"),
                "NostrClient"
            ]),
        .testTarget(
            name: "TrysteroSwiftTests",
            dependencies: ["TrysteroSwift"]
        ),
    ]
)
