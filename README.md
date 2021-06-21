# MVTTools

Vector tiles reader/writer for Swift

## Installation

### Swift Package Manager

```swift
.package(url: "https://github.com/Outdooractive/mvt-tools", from: "0.2.1"),
```

and

```swift
dependencies: [
    .product(name: "MVTTools", package: "mvt-tools"),
]),
```

## Features

TODO

## Usage

```swift
import MVTTools
```

## Contributing

Please create an issue or open a pull request with a fix

### Dependencies (for development)

```
brew install protobuf swift-protobuf swiftlint
```

## TODOs and future improvements

- Documentation (!)
- Tests
- Decode V1 tiles
- Clipping
- Simplification
- Locking (when updating/deleting features, indexing)
- Query option: within/intersects

- https://github.com/mapbox/vtcomposite
- https://github.com/mapbox/geosimplify-js
- https://github.com/mapbox/vt2geojson (command line tool?)

## Links

- Vector tiles
    - https://github.com/mapbox/vector-tile-spec/tree/master/2.1
    - https://github.com/mapbox/vector-tile-spec/blob/master/2.1/vector_tile.proto
    - https://docs.mapbox.com/vector-tiles/specification/#format

- Libraries
    - https://github.com/apple/swift-protobuf
    - https://github.com/Outdooractive/swift-turf

- Sample data for testing:
    - https://github.com/mapbox/mvt-fixtures
    - https://github.com/mapbox/mapnik-vector-tile/tree/master/bench
    - https://github.com/mapbox/mapnik-vector-tile/tree/master/examples
    - https://github.com/mapbox/mapnik-vector-tile/tree/master/test

- Other code for inspiration:
    - https://github.com/mapnik/node-mapnik/blob/master/src/mapnik_vector_tile.cpp

## License

MIT

## Author

Thomas Rasch, OutdoorActive
