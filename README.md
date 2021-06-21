# MVTTools

Vector tiles reader/writer for Swift

## 1. Dependencies (for development)

```
brew install protobuf swift-protobuf swiftlint
```

## 2. TODO

- Documentation (!)
- Tests

## 3. Links

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

## 4. Features

TODO

## 5. Future improvements

- Decode V1 tiles
- Clipping
- Simplification
- Locking (when updating/deleting features, indexing)
- Query option: within/intersects

- https://github.com/mapbox/vtcomposite
- https://github.com/mapbox/geosimplify-js
- https://github.com/mapbox/vt2geojson (command line tool?)
