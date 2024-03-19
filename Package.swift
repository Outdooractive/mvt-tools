// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "mvt-tools",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .executable(
            name: "mvt",
            targets: ["MVTCLI"]),
        .library(
            name: "MVTTools",
            targets: ["MVTTools"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Outdooractive/gis-tools", branch: "45_feature_id_overflow"),
        .package(url: "https://github.com/1024jp/GzipSwift.git", from: "5.2.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4"),
        .package(url: "https://github.com/apple/swift-protobuf", from: "1.25.2"),
    ],
    targets: [
        .executableTarget(
            name: "MVTCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "MVTTools"),
            ]),
        .target(
            name: "MVTTools",
            dependencies: [
                .product(name: "GISTools", package: "gis-tools"),
                .product(name: "Gzip", package: "GzipSwift"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]),
        .testTarget(
            name: "MVTToolsTests",
            dependencies: ["MVTTools"],
            exclude: ["TestData"]),
    ]
)
