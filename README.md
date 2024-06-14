[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fmvt-tools%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Outdooractive/mvt-tools)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fmvt-tools%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Outdooractive/mvt-tools)

# MVTTools

Mapbox vector tiles (MVT) reader/writer for Swift.

## Requirements

This package requires Swift 5.10 or higher (at least Xcode 14), and compiles on iOS (\>= iOS 13), macOS (\>= macOS 10.15), tvOS (\>= tvOS 13), watchOS (\>= watchOS 6) as well as Linux.

## Installation with Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Outdooractive/mvt-tools", from: "1.6.1"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "MVTTools", package: "mvt-tools"),
    ]),
]
```

This package uses the [gis-tools](https://github.com/Outdooractive/gis-tools) library, and is being used by the [mvt-postgis](https://github.com/Outdooractive/mvt-postgis) library, please have a look at them as well.

## Command line tool

You can install the command line tool `mvt` locally to `/usr/local/bin` with

```bash
# ./install_mvt.sh

# mvt -h
OVERVIEW: A utility for inspecting and working with vector tiles.

USAGE: mvt <subcommand>

OPTIONS:
  --version               Show the version.
  -h, --help              Show help information.

SUBCOMMANDS:
  dump (default)          Print the vector tile as GeoJSON
  info                    Print information about the vector tile
  merge                   Merge two or more vector tiles
  query                   Query the features in a vector tile
  export                  Export the vector tile as GeoJSON
  import                  Import some GeoJSONs to a vector tile

  See 'mvt help <subcommand>' for detailed help.
```

---

## Features

- Load and write Mapnik Vector Tiles from/to disk or data objects (also handles gzipped input)
- Export options: Zipped, buffered (in pixels or extents), simplified (in meters or extents)
- Can dump a tile as a GeoJSON object
- Supported projections: EPSG:4326, EPSG:3857 or none (uses the tile's coordinate space)
- Fast search (supports indexing), either within a bounding box or with center and radius
- Extract selected layers into a new tile
- Merge two tiles into one
- Can extract some infos from tiles like feature count, etc.
- Command line tool

## Usage

### Load

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

On macOS you can use a Swift Playground to inspect the MVTTools API such as `layerNames` & `projection`.

* Load tile using MVTTools
* Inspect the properties of the `VectorTile`

### `mvt dump`

Print the vector tile as GeoJSON.

`mvt` works with a vector tile from local disk.

Example 1: Print information about the MVTTools test vector tile at zoom 14, at Yaoundé, Cameroon.

```bash
mvt dump Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt
```

### `mvt info`

```bash
mvt info Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt
```

*Result*

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
    
---

`mvt` works with a vector tile served from a web server.

Example 2:  Inspect a MapLibre vector tile at zoom 2, with an extent showing Norway to India.

```bash
mvt info https://demotiles.maplibre.org/tiles/2/2/1.pbf
```

*Result*

    Name      | Features | Points | LineStrings | Polygons | Unknown | Version
    ----------+----------+--------+-------------+----------+---------+--------
    centroids | 104      | 104    | 0           | 0        | 0       | 2      
    countries | 113      | 0      | 0           | 113      | 0       | 2      
    geolines  | 4        | 0      | 4           | 0        | 0       | 2    


## Contributing

Please create an issue or open a pull request with a fix

## Dependencies (for development)

```
brew install protobuf swift-protobuf swiftlint
```

## TODOs and future improvements

- Documentation (!)
- Tests
- Decode V1 tiles
- Locking (when updating/deleting features, indexing)
- Query option: within/intersects

- https://github.com/mapbox/vtcomposite
- https://github.com/mapbox/geosimplify-js

## Links

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

## License

MIT

## Author

Thomas Rasch, Outdooractive
