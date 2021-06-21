// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "MVTTools",
    products: [
        .library(
            name: "MVTTools",
            targets: ["MVTTools"]),
    ],
    dependencies: [
        .package(name: "GISTools", url: "https://github.com/Outdooractive/gis-tools", from: "0.2.0"),
        .package(name: "SwiftProtobuf", url: "https://github.com/apple/swift-protobuf", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "MVTTools",
            dependencies: ["GISTools", "SwiftProtobuf"]),
        .testTarget(
            name: "MVTToolsTests",
            dependencies: ["MVTTools"],
            exclude: ["TestData"]),
    ]
)
