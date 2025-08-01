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

MapLibre/Mapbox vector tiles (MVT) reader/writer library for Swift, together with a powerful tool for working with vector tiles and GeoJSONs from the command line.

## Features

- Load and write MapLibre/Mapbox Vector Tiles from/to disk, data objects or URLs (also handles gzipped input).
- Export options: Zipped, buffered (in pixels or extents), simplified (in meters or extents).
- Can dump a tile as a GeoJSON object.
- Supported projections: EPSG:4326, EPSG:3857 or none (uses the tile's coordinate space).
- Fast search (supports indexing), either within a bounding box or with center and radius.
- Extract selected layers into a new tile.
- Merge tiles into one.
- Can extract some infos from tiles like feature count, etc.
- Powerful command line tool (via [Homebrew](#command-line-tool), documentation below) for working with vector tiles and GeoJSON files.

## Requirements

This package requires Swift 6.0 or higher (at least Xcode 15), and compiles on iOS (\>= iOS 15), macOS (\>= macOS 14), tvOS (\>= tvOS 15), watchOS (\>= watchOS 8) as well as Linux.

## Installation with Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Outdooractive/mvt-tools", from: "1.10.1"),
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

### Read

```swift
import MVTTools

// Load
let mvtData = Data(contentsOf: URL(fileURLWithPath: "14_8716_8015.vector.mvt"))!
let tile = VectorTile(data: mvtData, x: 8716, y: 8015, z: 14, indexed: .hilbert)!

print(tile.isIndexed)
print(tile.layerNames.sorted())

let tileAsGeoJsonData: Data? = tile.toGeoJson(prettyPrinted: true)
...

let result = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0)
...
```

### Write

```swift
import MVTTools

var tile = VectorTile(x: 8716, y: 8015, z: 14)!
var feature = Feature(Point(Coordinate3D(latitude: 3.870163, longitude: 11.518585)))
feature.properties = [
    "test": 1,
    "test2": 5.567,
    "test3": [1, 2, 3],
    "test4": [
        "sub1": 1,
        "sub2": 2
    ]
]

tile.setFeatures([feature], for: "test")

// Also have a look at ``VectorTile.ExportOptions``
let tileData = tile.data()
...
```

### Playground

On macOS you can use a Swift Playground to inspect the MVTTools API such as `layerNames` and `projection`.

* Load tile using MVTTools
* Inspect the properties of the `VectorTile`

# Command line tool

You can install the command line tool `mvt` either
- with homebrew: `brew install Outdooractive/homebrew-tap/mvt-tools`
- or locally to `/usr/local/bin` with `./install_mvt.sh`

`mvt` works with vector tiles or GeoJSON files from local disk or served from a web server.

GeoJSONs can contain a layer name in their Feature properties (default name is `vt_layer`), and any resulting GeoJSON will automatically include this property.
This can be controlled with the options `--property-name` (or `-P`), `--disable-input-layer-property` (or `-Di`) and `--disable-output-layer-property` (or `-Do`).
Some commands allow limiting the result to certain layers with `--layer` (or `-l`), which can be repeated for as many layers as necessary.

```bash
# mvt -h
OVERVIEW: A utility for inspecting and working with vector tiles (MVT) and GeoJSON files.

A x/y/z tile coordinate is needed for encoding/decoding vector tiles (MVT).
This tile coordinate can be extracted from the file path/URL if it's either in the form '/z/x/y' or 'z_x_y'.
Tile coordinates are not necessary for GeoJSON input files.

Examples:
- Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt
- https://demotiles.maplibre.org/tiles/2/2/1.pbf

USAGE: mvt <subcommand>

OPTIONS:
  --version               Show the version.
  -h, --help              Show help information.

SUBCOMMANDS:
  dump (default)          Print the input file (mvt or GeoJSON) as pretty-printed GeoJSON to the console
  info                    Print information about the input file (mvt or GeoJSON)
  query                   Query the features in the input file (mvt or GeoJSON)
  merge                   Merge any number of vector tiles or GeoJSONs
  import                  Import some GeoJSONs into a vector tile
  export                  Export a vector tile as GeoJSON to a file

  See 'mvt help <subcommand>' for detailed help.
```
---
### mvt dump

Print a vector tile or GeoJSON file as pretty-printed GeoJSON.

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

Print some informations about vector tiles/GeoJSONs:
- The number of features, points, linestrings, polygons per layer
- The properties for each layer
- Counts of specific properties

**Example 1**: Print information about the MVTTools test vector tile at zoom 14, at Yaoundé, Cameroon.

```bash
mvt info Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt

 Name               | Features | Points | LineStrings | Polygons | Unknown | Version
--------------------+----------+--------+-------------+----------+---------+--------
 area_label         | 55       | 55     | 0           | 0        | 0       | 2
 barrier_line       | 4219     | 0      | 4219        | 0        | 0       | 2
 bridge             | 14       | 0      | 14          | 0        | 0       | 2
 building           | 5414     | 0      | 0           | 5414     | 0       | 2
 building_label     | 413      | 413    | 0           | 0        | 0       | 2
 ...
 road               | 502      | 1      | 497         | 4        | 0       | 2
 road_label         | 309      | 0      | 309         | 0        | 0       | 2
```
---

**Example 2**: Inspect a MapLibre vector tile at zoom 2, with an extent showing Norway to India.

```bash
mvt info https://demotiles.maplibre.org/tiles/2/2/1.pbf

 Name      | Features | Points | LineStrings | Polygons | Unknown | Version
-----------+----------+--------+-------------+----------+---------+--------
 centroids | 104      | 104    | 0           | 0        | 0       | 2
 countries | 113      | 0      | 0           | 113      | 0       | 2
 geolines  | 4        | 0      | 4           | 0        | 0       | 2
```
---

**Example 3**: Print information about the properties for each layer.

```bash
mvt info Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt

 Name               | area | class | group | layer | ldir | len | name | name_de | name_en | name_es | name_fr | network | oneway | ref | reflen | scalerank | type
--------------------+------+-------+-------+-------+------+-----+------+---------+---------+---------+---------+---------+--------+-----+--------+-----------+-----
 airport_label      | 0    | 0     | 0     | 0     | 0    | 0   | 0    | 0       | 0       | 0       | 0       | 0       | 0      | 0   | 0      | 0         | 0
 area_label         | 55   | 55    | 0     | 0     | 0    | 0   | 55   | 55      | 55      | 55      | 55      | 0       | 0      | 0   | 0      | 0         | 0
 barrier_line       | 0    | 4219  | 0     | 0     | 0    | 0   | 0    | 0       | 0       | 0       | 0       | 0       | 0      | 0   | 0      | 0         | 0
 bridge             | 0    | 14    | 0     | 13    | 0    | 0   | 0    | 0       | 0       | 0       | 0       | 0       | 14     | 0   | 0      | 0         | 0
...
```
---

**Example 4**: Print information about specific properties.

```bash
mvt info -p class Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt

 Name  | cemetery | driveway | fence | hedge | hospital | industrial | main | major_rail | mini_roundabout | minor_rail | motorway | park | parking | path | pitch | rail | school | service | street | street_limited | wetland | wood
-------+----------+----------+-------+-------+----------+------------+------+------------+-----------------+------------+----------+------+---------+------+-------+------+--------+---------+--------+----------------+---------+-----
 class | 4        | 36       | 3895  | 324   | 9        | 2          | 113  | 21         | 1               | 13         | 30       | 95   | 59      | 46   | 21    | 2    | 59     | 187     | 376    | 4              | 4       | 12
```

---
### mvt query

**Example 1**: Query a vector tile or GeoJSON file with a search term.

```bash
mvt query Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt "École"
{
  "features" : [
    {
      "bbox" : [
        11.537318229675295,
        3.8732409490233337,
        11.537318229675295,
        3.8732409490233337
      ],
      "geometry" : {
        "coordinates" : [
          11.537318229675295,
          3.8732409490233337
        ],
        "type" : "Point"
      },
      "id" : 51,
      "layer" : "building_label",
      "properties" : {
        "area" : 173.97920227050781,
        "name" : "École Maternelle",
        "name_de" : "École Maternelle",
        "name_en" : "École Maternelle",
        "name_es" : "École Maternelle",
        "name_fr" : "École Maternelle"
      },
      "type" : "Feature"
    },
    ...
}
```
---
**Example 2**: Query a tile with `latitude,longitude,radius`.

```bash
mvt query Tests/MVTToolsTests/TestData/14_8716_8015.geojson "3.87324,11.53731,1000"
{
  "features" : [
    {
      "bbox" : [
        11.529276967048643,
        3.8803432426251487,
        11.530832648277283,
        3.8823074685255259
      ],
      "geometry" : {
        "coordinates" : [
          ...
        ],
        "type" : "LineString"
      },
      "id" : 48,
      "layer" : "road",
      "properties" : {
        "class" : "driveway",
        "oneway" : 0
      },
      "type" : "Feature"
    },
    ...
}
```
---
**Example 3**: Query Feature properties in a tile.

```bash
mvt query -p Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt ".area > 40000 and .class == 'hospital'"

{
  "features" : [
    {
      "bbox" : [
        11.510410308837876,
        3.871287406415171,
        11.510410308837876,
        3.871287406415171
      ],
      "geometry" : {
        "coordinates" : [
          11.510410308837876,
          3.871287406415171
        ],
        "type" : "Point"
      },
      "id" : 2,
      "properties" : {
        "area" : 48364.9375,
        "class" : "hospital",
        "name" : "Hopital Central de Yaoundé",
        "name_de" : "Hopital Central de Yaoundé",
        "name_en" : "Hopital Central de Yaoundé",
        "name_es" : "Hopital Central de Yaoundé",
        "name_fr" : "Hopital Central de Yaoundé",
        "vt_layer" : "area_label"
      },
      "type" : "Feature"
    }
  ],
  "type" : "FeatureCollection"
}
```

The query language is very loosely modeled after the jq query language.
The output will contain all features where the query returns `true`.

Here is an overview. Example:
```
"properties": {
  "foo": {"bar": 1},
  "some": ["a", "b"],
  "value": 1,
  "string": "Some name"
}
```

Values are retrieved by putting a `.` in front of the property name. The property name must be quoted
if it is a number or contains non-alphabetic characters. Elements in arrays can be
accessed either by simply using the array index after the dot, or by wrapping it in brackets.

```
.foo       // true, property "foo" exists
.foo.bar   // true, property "foo" is a dictionary containing "bar"
."foo"."bar" // true, same as above but quoted
.'foo'.'bar' // true, same as above but quoted
.foo.x     // false, "foo" doesn't contain "x"
."foo.bar" // false, property "foo.bar" doesn't exist
.foo.[0]   // false, "foo" is not an array
.some.[0]  // true, "some" is an array and has an element at index "0"
.some.0    // true, same as above but without brackets
.some."0"  // false, "0" is a string key but "some" is not a dictionary
```

Comparisons can be expressed like this:
```
.value == "bar" // false
.value == 1  // true
.value != 1  // false
.value > 1   // false
.value >= 1  // true
.value < 1   // false
.value <= 1  // true
.string =~ /[Ss]ome/ // true
.string =~ /some/    // false
.string =~ /some/i   // true, case insensitive regexp
.string =~ "^Some"   // true, can also use quotes
```

Conditions (evaluated left to right):
```
.foo.bar == 1 and .value == 1 // true
.foo == 1 or .bar == 2        // false
.foo == 1 or .value == 1      // true
.foo not          // false, true if foo does not exist
.foo and .bar not // true, foo and bar don't exist together
.foo or .bar not  // false, true if neither foo nor bar exist
.foo.bar not      // false, true if "bar" in dictionary "foo" doesn't exist
```

Other:
```
near(latitude,longitude,tolerance) // true if the feature is within "tolerance" around the coordinate
```

Some complete examples:
```
// Can use single quotes for strings
mvt query -p 14_8716_8015.vector.mvt ".area > 20000 and .class == 'hospital'"

// ... or double quotes, but they must be escaped
mvt query -p 14_8716_8015.vector.mvt ".area > 20000 and .class == \"hospital\""

// No need to quote the query if it doesn't conflict with your shell
// Print all features that have an "area" property
mvt query -p 14_8716_8015.vector.mvt .area
// Features which don't have "area" and "name" properties
mvt query -p 14_8716_8015.vector.mvt .area and .name not

// Case insensitive regular expression
vt query -p 14_8716_8015.vector.mvt ".name =~ /hopital/i"

// Case sensitive regular expression
mvt query -p 14_8716_8015.vector.mvt ".name =~ /Recherches?/"
// Can also use quotes instead of slashes
mvt query -p 14_8716_8015.vector.mvt ".name =~ 'Recherches?'"

// Features around a coordinate
mvt query -p 14_8716_8015.vector.mvt "near(3.87324,11.53731,1000)"
// With other conditions
mvt query -p 14_8716_8015.vector.mvt ".name =~ /^lac/i and near(3.87324,11.53731,10000)"
```

---
### mvt merge

Merge two or more vector tiles or GeoJSON files in any combination.

```bash
# All vector tiles:
mvt merge --output merged.mvt path/to/first.mvt path/to/second.mvt

# All GeoJSON files:
mvt merge --output merged.geojson path/to/first.geojson path/to/second.geojson

# Merge GeoJSON files into a vector tile:
mvt merge --output merged.mvt --output-format mvt path/to/first.geojson path/to/second.geojson

# Merge vector tiles into a GeoJSOn file:
mvt merge --output merged.geojson --output-format geojson path/to/first.mvt path/to/second.mvt
```
---
### mvt export

Write a vector tile as GeoJSON to a file.

```bash
mvt export --output dumped.geojson --pretty-print Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt
```
---
### mvt import

Create a vector tile from GeoJSON.

```bash
mvt import new.mvt -x 8716 -y 8015 -z 14 Tests/MVTToolsTests/TestData/14_8716_8015.geojson
```
---

# Contributing

Please [create an issue](https://github.com/Outdooractive/mvt-tools/issues) or [open a pull request](https://github.com/Outdooractive/mvt-tools/pulls).

### Dependencies (for development)

```
brew install protobuf swift-protobuf swiftlint
```

# TODOs and future improvements

- Documentation (!)
- Tests
- Locking (when updating/deleting features, indexing)
- Query option: within/intersects

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
