# Getting started

Load a tile, inspect it, and write it back in another format.

## Add the package

```swift
dependencies: [
    .package(url: "https://github.com/Outdooractive/mvt-tools", from: "3.0.0"),
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "MVTTools", package: "mvt-tools"),
        ]),
]
```

Optional format coders are package traits. Enable them in the consuming
package with `--enable-all-traits`, or select individual traits such as
`EnableCSV` or `EnableMLT`. MLT is pure Swift by default; enable
`EnableMLTCXX` only if you want the optional C++ backend.

## Read MVT

```swift
import Foundation
import MVTTools

let url = URL(fileURLWithPath: "14_8716_8015.vector.mvt")
let data = try Data(contentsOf: url)

let tile = try VectorTile(
    mvtData: data,
    x: 8716,
    y: 8015,
    z: 14,
    indexed: .hilbert)

print(tile.layerNames)
print(tile.features(for: "road").count)
```

Gzipped MVT and MLT input is decompressed automatically. Use
``VectorTile/layerNames(from:)`` or ``VectorTile/layerNames(at:)`` when only
the layer names are needed.

## Convert to GeoJSON

```swift
let geoJson = tile.toGeoJson(
    layerNames: ["road", "building"],
    prettyPrinted: true,
    layerProperty: "vt_layer")

try geoJson?.write(to: outputURL)
```

Features are exported with the layer name in the `vt_layer` property by
default. Pass `layerProperty: nil` to suppress it.

## Create a tile and write MVT

```swift
var tile = try VectorTile(x: 8716, y: 8015, z: 14)

let feature = Feature(
    Point(Coordinate3D(latitude: 3.870163, longitude: 11.518585)),
    properties: ["name": "Example"])

tile.setFeatures([feature], for: "places")

let options = VectorTile.ExportOptions(
    bufferSize: .pixel(4),
    compression: .default,
    simplifyFeatures: .meters(1.0))

try tile.writeMVT(to: outputURL, options: options)
```

``VectorTile/ExportOptions`` controls buffering (in pixel or extent units),
gzip compression, and simplification. ``VectorTile/ExportOptions/extent`` is
the tile grid size (4096); ``VectorTile/ExportOptions/tileSize`` is the
reference raster tile size (512 pixels).

## Convert other formats

```swift
let geoJsonTile = try VectorTile(contentsOfGeoJson: geoJsonURL)

#if EnableCSV
let csvTile = try VectorTile(contentsOfCSV: csvURL)
#endif

#if EnableGPX
let gpxTile = try VectorTile(contentsOfGPX: gpxURL)
#endif
```

See <doc:ImportExport> for the full format matrix and availability rules.
