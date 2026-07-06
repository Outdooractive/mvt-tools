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
    ],
    dependencies: [
        .package(url: "https://github.com/Outdooractive/gis-tools", from: "2.0.5"),
        .package(url: "https://github.com/Outdooractive/gis-tools-geopackage", from: "1.0.1"),
        .package(url: "https://github.com/Outdooractive/gis-tools-gpx", from: "1.0.4"),
        .package(url: "https://github.com/Outdooractive/gis-tools-shapefile", from: "1.0.2"),
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
                .target(name: "CMLT"),
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
            path: ".",  // package root — sources are listed explicitly
            sources: [
                "Sources/CMLT/Bridge.cpp",
                "Dependencies/maplibre-tile-spec/cpp/src/mlt/decoder.cpp",
                "Dependencies/maplibre-tile-spec/cpp/src/mlt/feature.cpp",
                "Dependencies/maplibre-tile-spec/cpp/src/mlt/geometry_vector.cpp",
                "Dependencies/maplibre-tile-spec/cpp/src/mlt/layer.cpp",
                "Dependencies/maplibre-tile-spec/cpp/src/mlt/properties.cpp",
                "Dependencies/maplibre-tile-spec/cpp/src/mlt/metadata/stream.cpp",
                "Dependencies/maplibre-tile-spec/cpp/src/mlt/metadata/tileset.cpp",
                "Dependencies/maplibre-tile-spec/cpp/src/mlt/util/rle.cpp",
                "Dependencies/maplibre-tile-spec/cpp/src/mlt/decode/int.cpp",
                "Dependencies/maplibre-tile-spec/cpp/src/mlt/encoder.cpp",
                "Dependencies/maplibre-tile-spec/cpp/src/mlt/encode/int.cpp",
                "Dependencies/maplibre-tile-spec/cpp/vendor/fastpfor/src/bitpacking.cpp",
                "Dependencies/maplibre-tile-spec/cpp/vendor/fastpfor/src/bitpackingaligned.cpp",
                "Dependencies/maplibre-tile-spec/cpp/vendor/fastpfor/src/bitpackingunaligned.cpp",
                "Dependencies/maplibre-tile-spec/cpp/vendor/fastpfor/src/horizontalbitpacking.cpp",
                "Dependencies/maplibre-tile-spec/cpp/vendor/fastpfor/src/simdunalignedbitpacking.cpp",
                "Dependencies/maplibre-tile-spec/cpp/vendor/fastpfor/src/simdbitpacking.cpp",
                "Dependencies/maplibre-tile-spec/cpp/vendor/fsst/libfsst.cpp",
                "Dependencies/maplibre-tile-spec/cpp/vendor/fsst/fsst_avx512.cpp",
            ],
            publicHeadersPath: "Sources/CMLT/include",
            cxxSettings: [
                .headerSearchPath("Sources/CMLT/patches"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/include"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/src"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/vendor/fastpfor/headers"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/vendor/fsst"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/vendor/json/include"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/vendor/earcut/include"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/vendor/earcut"),
                .define("MLT_WITH_FASTPFOR", to: "1"),
                .unsafeFlags(["-std=c++20"]),
            ],
        ),
    ]
)
