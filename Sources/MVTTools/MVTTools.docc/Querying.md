# Querying

Text search, spatial search, and the RPN query DSL.

## Text and query-DSL search

``VectorTile/query(term:layerName:featureFilter:)`` searches feature
properties. If the term contains query-DSL operators (`==`, `>`, `=~`, `in`,
`and`, ...) it is parsed as a query; otherwise every string property is
matched case-insensitively as a substring.

```swift
let hospitals = tile.query(term: ".class == 'hospital' and .area > 1000")
let named = tile.query(term: "école")
```

The query language is implemented by `GISTools.QueryParser` and supports:

- property access: `.name`, `.foo.bar`, `."key.with.dots"`, `.items.[0]`
- comparisons: `==`, `!=`, `>`, `>=`, `<`, `<=`
- regex and string operators: `=~ /pattern/i`, `=*` contains, `=^` starts
  with, `=$` ends with
- set membership: `.class in ["primary", "secondary"]`
- boolean logic: `and`, `or`, postfix `not`, `exists`
- spatial predicates: `near(lat,lon,meters)`, `within(minLon,minLat,maxLon,maxLat)`,
  `intersects(minLon,minLat,maxLon,maxLat)`

## Spatial queries

```swift
let near = tile.query(
    at: Coordinate3D(latitude: 3.87, longitude: 11.52),
    tolerance: 100.0)

let inBox = tile.query(in: boundingBox)
```

Tolerance follows the tile projection: meters for EPSG:4326/3857, native
units for other projections, and tile units for `noSRID`.

## Many coordinates

``VectorTile/queryMany(at:tolerance:layerName:featureFilter:includeDuplicates:)``
returns both a feature dictionary keyed by feature ID and one result per
coordinate. Set `includeDuplicates: false` to report a feature only once.

## Indexed vs linear

Call ``VectorTile/createIndex(sortOption:)`` or initialize with
`indexed: .hilbert`. Indexed queries apply a precise geometry intersection
check after the R-tree bounding-box candidate search, so results match a
linear scan exactly. The index changes performance, not semantics.
