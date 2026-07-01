// swift-tools-version:6.3

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
        .library(
            name: "MLTTools",
            targets: ["MLTTools"]),
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
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]),
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
                .target(name: "MLTTools"),
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]),

        .testTarget(
            name: "MVTToolsTests",
            dependencies: ["MVTTools"],
            exclude: ["TestData"],
            swiftSettings: [.interoperabilityMode(.Cxx)]),
        .testTarget(
            name: "MVTCLITests",
            dependencies: ["MVTCLI"],
            swiftSettings: [.interoperabilityMode(.Cxx)]),

        // MARK: - MLT C++ bridge (decoder + encoder + FastPFOR + FSST)

        .target(
            name: "CMLT",
            dependencies: [],
            path: "Sources/CMLT",
            sources: [
                "Bridge.cpp",
                "cpp/src/mlt/decoder.cpp",
                "cpp/src/mlt/feature.cpp",
                "cpp/src/mlt/geometry_vector.cpp",
                "cpp/src/mlt/layer.cpp",
                "cpp/src/mlt/properties.cpp",
                "cpp/src/mlt/metadata/stream.cpp",
                "cpp/src/mlt/metadata/tileset.cpp",
                "cpp/src/mlt/util/rle.cpp",
                "cpp/src/mlt/decode/int.cpp",
                "cpp/src/mlt/encoder.cpp",
                "cpp/src/mlt/encode/int.cpp",
                "vendor/fastpfor/src/bitpacking.cpp",
                "vendor/fastpfor/src/bitpackingaligned.cpp",
                "vendor/fastpfor/src/bitpackingunaligned.cpp",
                "vendor/fastpfor/src/horizontalbitpacking.cpp",
                "vendor/fastpfor/src/simdunalignedbitpacking.cpp",
                "vendor/fastpfor/src/codecfactory.cpp",
                "vendor/fastpfor/src/simdbitpacking.cpp",
                "vendor_wrappers/streamvbyte.cpp",
                "vendor_wrappers/varintdecode.cpp",
                "vendor/fsst/libfsst.cpp",
                "vendor/fsst/fsst_avx512.cpp",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("patches"),
                .headerSearchPath("cpp/include"),
                .headerSearchPath("cpp/src"),
                .headerSearchPath("vendor/fastpfor/headers"),
                .headerSearchPath("vendor/fsst"),
                .headerSearchPath("vendor/json/include"),
                .headerSearchPath("vendor/earcut/include"),
                .headerSearchPath("vendor/earcut"),
                .define("MLT_WITH_FASTPFOR", to: "1"),
                .define("MLT_WITH_JSON", to: "1"),
                .unsafeFlags(["-std=c++20"]),
            ],
        ),

        // MARK: - Swift wrapper for MLT

        .target(
            name: "MLTTools",
            dependencies: [
                .target(name: "CMLT"),
                .product(name: "GISTools", package: "gis-tools"),
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]),

        .testTarget(
            name: "MLTToolsTests",
            dependencies: ["MLTTools"],
            swiftSettings: [.interoperabilityMode(.Cxx)]),
    ]
)
