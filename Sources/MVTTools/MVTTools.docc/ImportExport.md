# Import and export traits

Which formats are built in, and how package traits gate them.

## Availability

GeoJSON is always available. MVT and the remaining format coders are package
traits:

| Format | Trait | Import | Export |
| --- | --- | --- | --- |
| MVT | `EnableMVT` | `VectorTile(mvtData:...)` | `mvtData(options:)`, `writeMVT(to:options:)` |
| MLT | `EnableMLT` (pure Swift) | `VectorTile(mltData:...)` | `mltData(options:)`, `writeMLT(to:options:)` |
| MLT (C++) | `EnableMLTCXX` | `VectorTile(mltData:...)` | `mltData(options:)`, `writeMLT(to:options:)` |
| GeoJSON | built in | `VectorTile(geoJsonData:...)` | `toGeoJson(...)`, `writeGeoJson(to:...)` |
| CSV | `EnableCSV` | `VectorTile(csvData:...)` | `toCsvData(...)`, `writeCSV(to:...)` |
| GPX | `EnableGPX` | `VectorTile(gpxData:...)` | `toGpxData(...)`, `writeGPX(to:...)` |
| FIT | `EnableFIT` | `VectorTile(fitData:...)` | `toFitData(...)`, `writeFIT(to:...)` |
| Shapefile | `EnableShapefile` | `VectorTile(shapefile:...)` | `writeShapefile(to:...)`, `writeShapefiles(to:...)` |
| GeoPackage | `EnableGeoPackage` | `VectorTile(geopackage:...)` | `writeGeoPackage(to:...)` |

Every `contentsOf…` initializer reads from a file URL. Every `write…` method
returns `Bool` or throws; `to…Data` methods return optional `Data`.

Enable traits from the command line:

```bash
swift test --enable-all-traits
swift test --traits EnableMVT   # Mapbox Vector Tiles
swift test --traits EnableMLT   # pure Swift MLT, no C++ interop
swift test --traits EnableMLTCXX # C++ MLT backend
```

Or select individual traits in a consuming package:

```swift
.product(name: "MVTTools", package: "mvt-tools", condition: .when(traits: ["EnableCSV"]))
```

## Export options

``VectorTile/ExportOptions`` is shared by all coders:

```swift
var options = VectorTile.ExportOptions()
options.bufferSize = .pixel(8)          // or .extent(512), .no
options.compression = .level(9)         // 0...9, gzip
options.simplifyFeatures = .meters(2.0) // or .extent(4), .no
```

Buffers are measured in tile-extent units or in 512-pixel tile units.
Simplification tolerances are in meters (or extent units). GeoJSON export
honours compression as well, and gzipped GeoJSON is accepted on import.

## Layer routing

GeoJSON, GPX, and CSV input can split features into layers using a property:

```swift
let tile = try VectorTile(
    geoJsonData: data,
    layerProperty: "vt_layer",
    layerAllowlist: ["roads", "buildings"])
```

The routing property is removed from the stored feature. GeoJSON, GPX, CSV,
and GeoPackage writers can restore a layer property on export. GeoPackage uses
the reserved `"gpkg_layer"` property to preserve layers when merging tables.

## What is preserved

MVT and MLT are vector tile formats, not general-purpose feature stores:

- MVT preserves numeric feature IDs, property types (string, bool, integer,
  unsigned integer, float, double), and geometry vertices quantized to the
  tile grid.
- MLT preserves unsigned 64-bit IDs and numeric/string/bool properties.
- Neither format preserves altitude or the GeoJSON `m` value.
- Arrays and dictionaries are stored as JSON strings in MVT properties.
- String feature IDs are not representable in MVT or MLT.

See <doc:Limitations> for the complete list.

## Import/export helpers

The shared helpers are useful when writing custom formats:

- `processFeatures(_:options:)`
- `processedFeatures(_:clipBoundingBox:simplifyDistance:)`
- `expanded(_:byBufferSize:)`
