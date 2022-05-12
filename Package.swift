// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "mvt-tools",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "MVTTools",
            targets: ["MVTTools"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Outdooractive/gis-tools", from: "0.2.49"),
        .package(name: "SwiftProtobuf", url: "https://github.com/apple/swift-protobuf", from: "1.19.0"),
    ],
    targets: [
        .target(
            name: "MVTTools",
            dependencies: [
                .product(name: "GISTools", package: "gis-tools"),
                .byName(name: "SwiftProtobuf"),
            ],
            swiftSettings: [
                // Remove when updating to Swift 6
                .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-enable-actor-data-race-checks"], .when(configuration: .debug))
            ]),
        .testTarget(
            name: "MVTToolsTests",
            dependencies: ["MVTTools"],
            exclude: ["TestData"]),
    ]
)
