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
    traits: [
        .trait(
            name: "EnableMLT",
            description: "Enables the MapLibre tile specification (MLT) decoder/encoder backed by a C++ bridge (FastPFOR + FSST). Requires Swift C++ interoperability."),
        .trait(
            name: "EnableCSV",
            description: "Enables CSV vector tile import/export."),
        .trait(
            name: "EnableGeoPackage",
            description: "Enables GeoPackage vector tile import/export via gis-tools-geopackage."),
        .trait(
            name: "EnableGPX",
            description: "Enables GPX vector tile import/export."),
        .trait(
            name: "EnableFIT",
            description: "Enables FIT vector tile import/export."),
        .trait(
            name: "EnableShapefile",
            description: "Enables Shapefile vector tile import/export."),
    ],
    dependencies: [
        .package(url: "https://github.com/Outdooractive/gis-tools", from: "2.3.0"),
        .package(url: "https://github.com/Outdooractive/gis-tools-csv", from: "1.2.0"),
        .package(url: "https://github.com/Outdooractive/gis-tools-geopackage", from: "1.0.3"),
        .package(url: "https://github.com/Outdooractive/gis-tools-gpx", from: "1.0.4"),
        .package(url: "https://github.com/Outdooractive/gis-tools-fit", from: "1.0.0"),
        .package(url: "https://github.com/Outdooractive/gis-tools-shapefile", from: "1.0.2"),
        .package(url: "https://github.com/1024jp/GzipSwift.git", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
        .package(url: "https://github.com/apple/swift-protobuf", from: "1.38.1"),
    ],
    targets: [
        .executableTarget(
            name: "MVTCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "GISToolsCSV", package: "gis-tools-csv"),
                .target(name: "MVTTools"),
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]),
        .target(
            name: "MVTTools",
            dependencies: [
                .product(name: "GISTools", package: "gis-tools"),
                .product(name: "GISToolsCSV", package: "gis-tools-csv",
                         condition: .when(traits: ["EnableCSV"])),
                .product(name: "GISToolsGeoPackage", package: "gis-tools-geopackage",
                         condition: .when(traits: ["EnableGeoPackage"])),
                .product(name: "GISToolsGPX", package: "gis-tools-gpx",
                         condition: .when(traits: ["EnableGPX"])),
                .product(name: "GISToolsFIT", package: "gis-tools-fit",
                         condition: .when(traits: ["EnableFIT"])),
                .product(name: "GISToolsShapefile", package: "gis-tools-shapefile",
                         condition: .when(traits: ["EnableShapefile"])),
                .product(name: "Gzip", package: "GzipSwift"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .target(name: "CMLT", condition: .when(traits: ["EnableMLT"])),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx, .when(traits: ["EnableMLT"])),
            ]),

        .testTarget(
            name: "MVTToolsTests",
            dependencies: ["MVTTools"],
            exclude: ["TestData"],
            swiftSettings: [
                .interoperabilityMode(.Cxx, .when(traits: ["EnableMLT"])),
            ]),
        .testTarget(
            name: "MVTCLITests",
            dependencies: ["MVTCLI"],
            swiftSettings: [
                .interoperabilityMode(.Cxx, .when(traits: ["EnableMLT"])),
            ]),

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
                "Dependencies/maplibre-tile-spec/cpp/vendor/fastpfor/fastpfor/bitpacking.cpp",
                "Dependencies/maplibre-tile-spec/cpp/vendor/fsst/libfsst.cpp",
                "Dependencies/maplibre-tile-spec/cpp/vendor/fsst/fsst_avx512.cpp",
            ],
            publicHeadersPath: "Sources/CMLT/include",
            cxxSettings: [
                .headerSearchPath("Sources/CMLT/patches"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/include"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/src"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/vendor/fastpfor"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/vendor/fsst"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/vendor/json/include"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/vendor/earcut/include"),
                .headerSearchPath("Dependencies/maplibre-tile-spec/cpp/vendor/earcut"),
                .define("MLT_WITH_FASTPFOR", to: "1"),
                .unsafeFlags(["-std=c++20"]),
                .define("__SSE4_2__", .when(platforms: [.linux])),
            ],
        ),
    ]
)
