// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TrysteroChat",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "TrysteroChat",
            dependencies: ["TrysteroSwift"]
        )
    ]
)
