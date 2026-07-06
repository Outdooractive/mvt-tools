[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fmvt-tools%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Outdooractive/mvt-tools)  
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fmvt-tools%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Outdooractive/mvt-tools)  
[![](https://img.shields.io/github/license/Outdooractive/mvt-tools)](https://github.com/Outdooractive/mvt-tools/blob/main/LICENSE)  
[![](https://img.shields.io/badge/Homebrew-Outdooractive%2Fhomebrew--tap%2Fmvt--tools-blue
)](#command-line-tool)  
[![](https://img.shields.io/github/v/release/Outdooractive/mvt-tools?sort=semver&display_name=tag)](https://github.com/Outdooractive/mvt-tools/releases) [![](https://img.shields.io/github/release-date/Outdooractive/mvt-tools?display_date=published_at
)](https://github.com/Outdooractive/mvt-tools/releases)  
[![](https://img.shields.io/github/issues/Outdooractive/mvt-tools
)](https://github.com/Outdooractive/mvt-tools/issues) [![](https://img.shields.io/github/issues-pr/Outdooractive/mvt-tools
)](https://github.com/Outdooractive/mvt-tools/pulls)  
[![](https://img.shields.io/github/check-runs/Outdooractive/mvt-tools/main)](https://github.com/Outdooractive/mvt-tools/actions)

# MVTTools

MapLibre/Mapbox vector tiles (MVT/MLT) reader/writer library for Swift, together with a powerful command-line tool for working with vector tiles, GeoJSON, GPX, Shapefile, and GeoPackage files.

## Features

- **Read & write** MapLibre/Mapbox Vector Tiles from/to disk, data objects or URLs (handles gzipped input).
- **GeoJSON import/export** — convert between MVT and GeoJSON formats.
- **GPX import/export** — convert between MVT and GPX (GPS eXchange) formats; waypoints, routes and tracks are automatically split into separate layers.
- **Shapefile import/export** — convert between MVT and ESRI Shapefile format; supports single-file and per-layer directory export with mixed-geometry detection.
- **GeoPackage import/export** — convert between MVT and OGC GeoPackage format; supports single-table and per-layer export with complete roundtrip fidelity via `"gpkg_layer"` metadata.
- **Export options** — gzip compression, buffering (pixels or extents), geometry simplification (meters or extents).
- **Projections** — EPSG:4326 (WGS84), EPSG:3857 (Web Mercator), EPSG:4978 (ECEF), `noSRID` (raw tile coordinates).
- **Spatial queries** — R-Tree indexed or linear scan; bounding-box search, center+radius proximity (`near`), bounding-box containment (`within`), bounding-box intersection (`intersects`).
- **Property queries** — powerful RPN-based query DSL with comparisons, string operators, regex, set membership, boolean logic, and existence checks.
- **Layer management** — extract, merge, remove, or filter layers and features.
- **Tile metadata** — per-layer feature counts, geometry-type breakdowns, property histograms.
- **Command-line tool** — `mvt` with subcommands: `dump`, `info`, `query`, `merge`, `import`, `export`.

## Requirements

This package requires Swift 6.3 or higher (at least Xcode 15), and compiles on iOS (\>= iOS 15), macOS (\>= macOS 15), tvOS (\>= tvOS 15), watchOS (\>= watchOS 8) as well as Linux.

## Installation with Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Outdooractive/mvt-tools", from: "1.10.2"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "MVTTools", package: "mvt-tools"),
    ]),
]
```

This package uses the [gis-tools](https://github.com/Outdooractive/gis-tools) library, and is being used by the [mvt-postgis](https://github.com/Outdooractive/mvt-postgis) library, please have a look at them as well.

## Usage

See the [API documentation](https://swiftpackageindex.com/Outdooractive/mvt-tools/main/documentation/mvttools) (via Swift Package Index).

### Read MVT

```swift
import MVTTools

let mvtData = try Data(contentsOf: URL(fileURLWithPath: "14_8716_8015.vector.mvt"))
let tile = VectorTile(data: mvtData, x: 8716, y: 8015, z: 14, indexed: .hilbert)!

print(tile.isIndexed)               // true
print(tile.layerNames.sorted())     // ["admin", "aeroway", "airport_label", …]

// Export as GeoJSON
let geoJsonData: Data? = tile.toGeoJson(prettyPrinted: true)

// Spatial query
let results = tile.query(
    at: Coordinate3D(latitude: 3.87, longitude: 11.52),
    tolerance: 100.0)
```

### Read GeoJSON

```swift
let geoJsonData = try Data(contentsOf: URL(fileURLWithPath: "features.geojson"))
let tile = VectorTile(geoJsonData: geoJsonData, layerProperty: "vt_layer")!

// The tile can now be exported as MVT
let mvtData = tile.data()
```

### Write MVT

```swift
var tile = VectorTile(x: 8716, y: 8015, z: 14)!

var feature = Feature(Point(Coordinate3D(latitude: 3.870163, longitude: 11.518585)))
feature.properties = [
    "name": "Test",
    "value": 42,
]

tile.setFeatures([feature], for: "my_layer")

// Write with compression and buffering options
let options = VectorTile.ExportOptions(
    bufferSize: .pixel(4),
    compression: .default,
    simplifyFeatures: .meters(1.0))
let mvtData = tile.data(options: options)
try mvtData?.write(to: URL(fileURLWithPath: "output.mvt"))

// Or write directly
tile.write(to: URL(fileURLWithPath: "output.mvt"), options: options)
```

### Read GPX

```swift
let gpxData = try Data(contentsOf: URL(fileURLWithPath: "track.gpx"))
let tile = VectorTile(gpxData: gpxData)!

// Waypoints, routes and tracks are split into separate layers.
print(tile.layerNames.sorted())   // ["rte", "trk", "wpt"]

// Export as MVT
let mvtData = tile.data()
```

### Write GPX

```swift
let gpxData = tile.toGpxData()
try gpxData?.write(to: URL(fileURLWithPath: "output.gpx"))

// Or write directly
tile.writeGPX(to: URL(fileURLWithPath: "output.gpx"))
```

### Read Shapefile

```swift
let tile = VectorTile(shapefile: URL(fileURLWithPath: "roads.shp"))!

// Layer name defaults to the filename.
print(tile.layerNames)   // ["roads"]
```

### Write Shapefile

```swift
// Single file export (all layers merged, throws on mixed geometry)
try tile.writeShapefile(to: URL(fileURLWithPath: "output.shp"))

// Per-layer export to a directory
try tile.writeShapefiles(to: URL(fileURLWithPath: "/tmp/layers"))
// Creates /tmp/layers/roads.shp, /tmp/layers/buildings.shp, …
```

### Read GeoPackage

```swift
// Load all feature tables (each becomes a layer)
let tile = try await VectorTile(geopackage: URL(fileURLWithPath: "data.gpkg"))

// Load a single table
let tile = try await VectorTile(
    geopackage: URL(fileURLWithPath: "data.gpkg"),
    table: "roads")
```

### Write GeoPackage

```swift
// Single table (all layers merged)
try await tile.writeGeoPackage(
    to: URL(fileURLWithPath: "output.gpkg"),
    table: "combined")

// One table per layer
try await tile.writeGeoPackage(to: URL(fileURLWithPath: "output.gpkg"))
```

### Write GeoJSON

```swift
let geoJsonData = tile.toGeoJson(
    layerNames: ["road", "building"],
    prettyPrinted: true,
    layerProperty: "vt_layer")
try geoJsonData?.write(to: URL(fileURLWithPath: "output.geojson"))

// Or write directly
tile.writeGeoJson(to: URL(fileURLWithPath: "output.geojson"), prettyPrinted: true)
```

### Layer management

```swift
// Add features to a layer
tile.appendFeatures([feature1, feature2], to: "roads")

// Replace a layer
tile.setFeatures([feature3], for: "buildings")

// Remove features matching a predicate
tile.removeFeatures(fromLayer: "roads") { $0.properties["class"] as? String == "footway" }

// Remove an entire layer
tile.removeLayer("temporary_layer")

// Extract layers into a new tile
let subset = tile.extract(layerNames: ["road", "building"])

// Merge tiles
tile.merge(anotherTile)
```

### Merge tiles

```swift
let tile1 = VectorTile(data: mvtData1, x: 5, y: 13, z: 4)!
let tile2 = VectorTile(data: mvtData2, x: 5, y: 13, z: 4)!
tile1.merge(tile2)
```

### Tile info

```swift
// Layer names
let names = VectorTile.layerNames(from: mvtData)  // ["road", "building", …]

// Feature statistics
if let info = tile.tileInfo() {
    for layer in info {
        print(layer.name,
              layer.features,       // total feature count
              layer.pointFeatures,  // point count
              layer.linestringFeatures,
              layer.polygonFeatures)
    }
}

// Static info (no VectorTile instance needed)
let info = VectorTile.tileInfo(from: mvtData)
```

### Export options

```swift
VectorTile.ExportOptions(
    bufferSize: .extent(512),       // buffer in tile-extent units
    // or: .pixel(4), .no
    compression: .level(9),         // gzip compression 0-9
    // or: .default, .no
    simplifyFeatures: .meters(1.0)  // simplify geometry to 1m tolerance
    // or: .extent(10), .no
)
```

### Playground

On macOS you can use a Swift Playground to inspect the MVTTools API such as `layerNames` and `projection`.

- Load a tile using MVTTools
- Inspect the properties of the `VectorTile`

## Query language

The query language is used by the `mvt query` CLI command and by the programmatic `tile.query(term:)` API. It filters features by evaluating an expression against each feature's properties and geometry. The language uses a Reverse Polish Notation (RPN) internally but the query syntax follows a natural infix style.

### Value access

Properties are accessed by prefixing the key with `.`:

| Query | Meaning |
|-------|---------|
| `.name` | Property `name` exists and is truthy |
| `.foo.bar` | Nested property `foo → bar` |
| `."foo.bar"` | Property whose key contains a dot |
| `.foo.[0]` | First element of array property `foo` |
| `.some.0` | Same as above, shorthand |

Assuming features with this structure:
```json
{
  "properties": {
    "foo": {"bar": 1, "baz": 10},
    "some": ["a", "b"],
    "value": 1,
    "name": "Some name"
  }
}
```

```
.foo         → true (exists)
.foo.bar     → true (1 is truthy)
.foo.x       → false (key not found)
.some.[0]    → true ("a" exists)
.some.2      → false (out of bounds)
```

### Comparisons

| Operator | Meaning | Example |
|----------|---------|---------|
| `==` | Equal | `.value == 1` |
| `!=` | Not equal | `.value != 2` |
| `>` | Greater than | `.value > 0` |
| `>=` | Greater or equal | `.value >= 1` |
| `<` | Less than | `.value < 2` |
| `<=` | Less or equal | `.value <= 1` |
| `=~` | Regex match | `.name =~ /^Some/i` |
| `=*` | String contains (case-insensitive) | `.name =* "ome"` |
| `=^` | String starts with (case-insensitive) | `.name =^ "some"` |
| `=$` | String ends with (case-insensitive) | `.name =$ "name"` |

Cross-type numeric comparisons work automatically (e.g. `Int` vs `Double`, `UInt8` vs `Int`).

```
.value == 1       → true
.value != 1       → false
.value > 0        → true
.value <= 1       → true
.name =~ /^Some/  → true (regex, case-sensitive)
.name =~ /^some/i → true (regex, case-insensitive)
.name =* "ome"    → true (contains, case-insensitive)
.name =^ "Some"   → true (starts with, case-insensitive)
.name =$ "name"   → true (ends with, case-insensitive)
```

### String values

Strings can be quoted with single or double quotes:

```
.name == 'Main Street'
.name == "Main Street"
.name =~ "Main.*"
```

### Set membership

```
.class in ["primary", "secondary"]         → true if .class matches either value
.value in [1, 3, 5]                        → integer sets
.name in ['Alice', 'Bob']                  → string sets
```

Commas inside quoted strings are preserved:
```
.tags in ["tag, with, comma", "other"]
```

### Boolean conditions

| Operator | Meaning | Example |
|----------|---------|---------|
| `and` | Logical AND | `.a == 1 and .b == 2` |
| `or` | Logical OR | `.a == 1 or .b == 1` |
| `not` | Logical NOT (postfix) | `.a not` |
| `exists` | Truthy check | `.a exists` |

```
.foo.bar == 1 and .value == 1      → true
.foo == 1 or .bar == 2             → false
.foo not                            → false (foo exists, so !true)
.foo.bar not                        → false (bar exists in foo)
.nonexistent not                    → true (property absent)
.foo exists                         → true (non-nil)
.nonexistent exists                 → false (nil)
```

`exists` can be combined with other conditions:
```
.bridge exists and .tunnel exists   → true
.nonexistent exists not             → true
```

### Spatial predicates

| Predicate | Syntax | Meaning |
|-----------|--------|---------|
| `near` | `near(lat, lon, tolerance)` | Feature **centroid** is within `tolerance` meters of the given point |
| `within` | `within(minLon, minLat, maxLon, maxLat)` | Feature's **bounding box** is fully inside the rectangle |
| `intersects` | `intersects(minLon, minLat, maxLon, maxLat)` | Feature's **geometry** intersects the rectangle |

```
near(3.87, 11.52, 1000)                                → features within 1 km
.area > 40000 and within(11.5, 3.8, 11.6, 3.9)         → large features in area
.highway == primary and intersects(11.5, 3.8, 11.6, 3.9)  → roads crossing the area
```

Note: `within` checks bbox containment, `intersects` does a precise geometry-level intersection test (via GISTools' `Feature.intersects(BoundingBox)` which uses a two-phase check: bbox coarse filter + precise geometry intersection).

### Complete examples

```
# Features with area > 20000 classified as hospital
.area > 20000 and .class == 'hospital'

# Features named "Hopital" (case-insensitive) near a coordinate
.name =~ /hopital/i and near(3.87324, 11.53731, 1000)

# Roads or buildings that intersect a bounding box
.class in ["road", "building"] and intersects(11.5, 3.8, 11.6, 3.9)

# Features that exist and have a name starting with "Lac" or "Lake"
(.name =^ "Lac" or .name =^ "Lake") — note: parentheses not supported in RPN,
use the natural evaluation order instead:
.name =^ "Lac" or .name =^ "Lake"

# Features with no area property
.area not

# Features with a bridge tag
.bridge exists
```

### Using the query API programmatically

```swift
// Text search (falls back to full-text search if query isn't recognized)
let results = tile.query(term: "école")
let results = tile.query(term: ".class == 'hospital' and .area > 1000")

// Direct use of QueryParser
let parser = QueryParser(string: ".highway in [\"primary\", \"secondary\"] and .name =* \"Main\"")!
let matches = parser.evaluate(on: someFeature)
```

# Command line tool

You can install the command line tool `mvt` either
- with homebrew: `brew install Outdooractive/homebrew-tap/mvt-tools`
- or locally to `/usr/local/bin` with `./install_mvt.sh`

`mvt` works with MVT, MLT, GeoJSON, GPX, Shapefile, and GeoPackage files from local disk or served from a web server.

GeoJSONs can contain a layer name in their Feature properties (default name is `vt_layer`), and any resulting GeoJSON will automatically include this property.
This can be controlled with the options `--property-name` (or `-P`), `--disable-input-layer-property` (or `-Di`) and `--disable-output-layer-property` (or `-Do`).
Some commands allow limiting the result to certain layers with `--layer` (or `-l`), which can be repeated for as many layers as necessary.

```bash
# mvt -h
OVERVIEW: A utility for inspecting and working with vector tiles (MVT/MLT), GeoJSON, GPX, Shapefile, and GeoPackage files.

A x/y/z tile coordinate is needed for encoding/decoding MVT/MLT tiles.
This tile coordinate can be extracted from the file path/URL if it's either in the form '/z/x/y' or 'z_x_y'.
Tile coordinates are not necessary for GeoJSON, GPX, Shapefile, and GeoPackage files.

Examples:
- Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt
- https://demotiles.maplibre.org/tiles/2/2/1.pbf

USAGE: mvt <subcommand>

OPTIONS:
  --version               Show the version.
  -h, --help              Show help information.

SUBCOMMANDS:
  dump (default)          Print the input file (MVT, MLT, GeoJSON, GPX, Shapefile, or GeoPackage) as pretty-printed GeoJSON to the console
  info                    Print information about the input file
  query                   Query the features in the input file
  merge                   Merge any number of input files into a single file of any supported format
  import                  Alias for 'merge'
  export                  Alias for 'merge'

  See 'mvt help <subcommand>' for detailed help.
```
---
### mvt dump

Print any supported input file as pretty-printed GeoJSON.

```bash
mvt dump Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt
{
  "type" : "FeatureCollection",
  "features" : [
    {
      "bbox" : [
        11.516327261924731,
        3.8807821163834175,
        11.516590118408191,
        3.8815421167424793
      ],
      "properties" : {
        "oneway" : 1,
        "vt_layer" : "tunnel",
        "class" : "motorway"
      },
      "geometry" : {
        "coordinates" : [
          ...
        ],
        "type" : "LineString"
      },
      "id" : 1,
      "type" : "Feature"
    },
    ...
}
```
---
### mvt info

Print some informations about the input file:
- The number of features, points, linestrings, polygons per layer
- The properties for each layer
- Counts of specific properties

**Example 1**: Print information about a vector tile.

```bash
mvt info Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt

 Name               | Features | Points | LineStrings | Polygons | Unknown | Version
--------------------+----------+--------+-------------+----------+---------+--------
 area_label         | 55       | 55     | 0           | 0        | 0       | 2
 barrier_line       | 4219     | 0      | 4219        | 0        | 0       | 2
 bridge             | 14       | 0      | 14          | 0        | 0       | 2
 building           | 5414     | 0      | 0           | 5414     | 0       | 2
 ...
 road               | 502      | 1      | 497         | 4        | 0       | 2
```

**Example 2**: Inspect a remote MapLibre tile.

```bash
mvt info https://demotiles.maplibre.org/tiles/2/2/1.pbf

 Name      | Features | Points | LineStrings | Polygons | Unknown | Version
-----------+----------+--------+-------------+----------+---------+--------
 centroids | 104      | 104    | 0           | 0        | 0       | 2
 countries | 113      | 0      | 0           | 113      | 0       | 2
 geolines  | 4        | 0      | 4           | 0        | 0       | 2
```

**Example 3**: Print property counts per layer.

```bash
mvt info Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt

 Name               | area | class | group | layer | ldir | len | name | ...
--------------------+------+-------+-------+-------+------+-----+------+-----
 airport_label      | 0    | 0     | 0     | 0     | 0    | 0   | 0    | ...
 area_label         | 55   | 55    | 0     | 0     | 0    | 0   | 55   | ...
 ...
```

**Example 4**: Count values for a specific property.

```bash
mvt info -p class Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt

 Name  | cemetery | driveway | fence | hedge | hospital | industrial | ...
-------+----------+----------+-------+-------+----------+------------+-----
 class | 4        | 36       | 3895  | 324   | 9        | 2          | ...
```

---
### mvt query

The `mvt query` command uses the [query language](#query-language) described above.

**Example 1**: Full-text search.

```bash
mvt query Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt "École"
```

**Example 2**: Spatial query by coordinate.

```bash
mvt query Tests/MVTToolsTests/TestData/14_8716_8015.geojson "3.87324,11.53731,1000"
```

**Example 3**: Property query with comparisons.

```bash
mvt query -p Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt ".area > 40000 and .class == 'hospital'"
```

**Example 4**: Regex, string operators, and set membership.

```bash
# Case-insensitive regex
mvt query -p 14_8716_8015.vector.mvt ".name =~ /hopital/i"

# String starts with / ends with
mvt query -p 14_8716_8015.vector.mvt ".name =^ 'Main'"
mvt query -p 14_8716_8015.vector.mvt ".name =$ 'Street'"

# Set membership
mvt query -p 14_8716_8015.vector.mvt ".class in ['hospital', 'school']"
```

**Example 5**: Spatial predicates.

```bash
# Features near a point
mvt query -p 14_8716_8015.vector.mvt "near(3.87324,11.53731,1000)"

# Features within a bounding box
mvt query -p 14_8716_8015.vector.mvt "within(11.5, 3.8, 11.6, 3.9)"

# Features intersecting a bounding box
mvt query -p 14_8716_8015.vector.mvt ".class == 'road' and intersects(11.5, 3.8, 11.6, 3.9)"
```

**Example 6**: Combined queries.

```bash
# Name + spatial
mvt query -p 14_8716_8015.vector.mvt ".name =~ /^lac/i and near(3.87324,11.53731,10000)"

# Existence + comparison
mvt query -p 14_8716_8015.vector.mvt ".bridge exists and .tunnel not"
```

---
### mvt merge

Merge any number of input files in any combination. Output format is auto-detected from the output file extension.

```bash
# Merge vector tiles:
mvt merge --output merged.mvt path/to/first.mvt path/to/second.mvt

# Merge GeoJSON files:
mvt merge --output merged.geojson path/to/first.geojson path/to/second.geojson

# Merge GeoJSON files into a vector tile:
mvt merge --output merged.mvt path/to/first.geojson path/to/second.geojson

# Merge vector tiles into a GeoJSON file:
mvt merge --output merged.geojson path/to/first.mvt path/to/second.mvt

# All supported formats can be mixed:
mvt merge --output merged.gpkg data.geojson tracks.gpx roads.shp tile.mvt
```
---
### mvt export

Alias for `merge` — write any supported input file as GeoJSON.

```bash
mvt export --output dumped.geojson --pretty-print Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt
```
---
### mvt import

Alias for `merge` — import data from any supported format into a tile.

```bash
mvt import --output new.mvt -x 8716 -y 8015 -z 14 data.geojson
mvt import --output new.mvt tracks.gpx roads.shp
mvt import --output combined.gpkg data.geojson tracks.gpx
```
---

# Contributing

Please [create an issue](https://github.com/Outdooractive/mvt-tools/issues) or [open a pull request](https://github.com/Outdooractive/mvt-tools/pulls).

### Dependencies (for development)

```
brew install protobuf swift-protobuf swiftlint
```

# TODOs and future improvements

- Locking (when updating/deleting features, indexing)
&lt;!-- All planned format support has been implemented. --&gt;

- https://github.com/mapbox/vtcomposite
- https://github.com/mapbox/geosimplify-js

# Links

- Libraries
    - https://github.com/Outdooractive/gis-tools
    - https://github.com/Outdooractive/mvt-postgis
    - https://github.com/apple/swift-protobuf

- Vector tiles
    - https://github.com/mapbox/vector-tile-spec/tree/master/2.1
    - https://github.com/mapbox/vector-tile-spec/blob/master/2.1/vector_tile.proto
    - https://docs.mapbox.com/vector-tiles/specification/#format

- Sample data for testing:
    - https://github.com/mapbox/mvt-fixtures
    - https://github.com/mapbox/mapnik-vector-tile/tree/master/bench
    - https://github.com/mapbox/mapnik-vector-tile/tree/master/examples
    - https://github.com/mapbox/mapnik-vector-tile/tree/master/test

- Other code for inspiration:
    - https://github.com/mapnik/node-mapnik/blob/master/src/mapnik_vector_tile.cpp
    - https://github.com/mapbox/vt2geojson

# License

MIT

# Authors

Thomas Rasch, Outdooractive
