// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "mvt-tools",
    platforms: [
        .iOS(.v15),
        .macOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
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
        .package(url: "https://github.com/Outdooractive/gis-tools", from: "2.0.0"),
        .package(url: "https://github.com/Outdooractive/gis-tools-geopackage", from: "1.0.0"),
        .package(url: "https://github.com/Outdooractive/gis-tools-gpx", from: "1.0.0"),
        .package(url: "https://github.com/Outdooractive/gis-tools-shapefile", from: "1.0.0"),
        .package(url: "https://github.com/1024jp/GzipSwift.git", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.2"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
        .package(url: "https://github.com/apple/swift-protobuf", from: "1.33.1"),
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
                .product(name: "GISToolsGeoPackage", package: "gis-tools-geopackage"),
                .product(name: "GISToolsGPX", package: "gis-tools-gpx"),
                .product(name: "GISToolsShapefile", package: "gis-tools-shapefile"),
                .product(name: "Gzip", package: "GzipSwift"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]),
        .testTarget(
            name: "MVTToolsTests",
            dependencies: ["MVTTools"],
            exclude: ["TestData"]),
        .testTarget(
            name: "MVTCLITests",
            dependencies: ["MVTCLI"]),
    ]
)
