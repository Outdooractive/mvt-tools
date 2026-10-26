# Tile and geometry model

How ``VectorTile`` stores coordinates, layers, and features.

## Tile coordinates

A ``VectorTile`` has `x`, `y`, and `z` coordinates and a
`Projection`. The `xyz` values identify the tile in the standard
slippy-map grid: `z` is the zoom level and `x`/`y` address a tile within a
`2^z × 2^z` grid. The initializer validates the coordinate range:

```swift
let tile = try VectorTile(x: 8716, y: 8015, z: 14)
print(tile.mapTile)          // MapTile<(8716,8015)@14>
print(tile.boundingBox)      // tile bounds in the tile projection
```

Invalid coordinates throw VectorTileError or
VectorTileError.

The internal tile grid used by MVT and MLT is 4096 units wide and high
(``VectorTile/ExportOptions/extent``). A decoded coordinate is therefore
quantized to one 1/4096th of the tile width.

## Projections

The tile projection determines how tile-local coordinates are expressed in
the stored `Feature` values. Supported built-ins are EPSG:4326,
EPSG:3857, EPSG:4978, and `noSRID`. Runtime-registered custom projections are
also supported.

- EPSG:4326 uses latitude/longitude.
- EPSG:3857 and EPSG:4978 use projected x/y (and z) values.
- `noSRID` stores raw tile coordinates and skips projection and clipping.

The encoder and decoder always map tile-local integers through Web Mercator
tile bounds, so the same tile can be read into any registered projection and
will describe the same geographic location in that projection's units.

## Layers and features

Layers are stored as an internal dictionary of layer name to features.
``VectorTile/layerNames`` is sorted for deterministic output. Per-layer
operations include:

- ``VectorTile/features(for:)``
- ``VectorTile/setFeatures(_:for:)`` (replace)
- ``VectorTile/appendFeatures(_:to:)`` (append)
- ``VectorTile/removeFeatures(fromLayer:where:)``
- ``VectorTile/removeLayer(_:)``
- ``VectorTile/extract(layerNames:)``
- ``VectorTile/merge(_:ignoreTileCoordinateMismatch:)``

Features are `Feature` values. MVT supports numeric feature IDs
only; MLT supports unsigned 64-bit IDs. Features without a numeric ID are
still exported, without an ID.

## Feature identifiers

When a tile is decoded from MVT without a feature `id`, `MVTTools` assigns a
random UUID string ID. This keeps ``VectorTile/queryMany(at:tolerance:layerName:featureFilter:includeDuplicates:)``
useful for anonymous features. The ID is not part of the MVT wire format, so
it does not survive an encode/decode round trip. Use numeric IDs when stable
identity matters.

## Spatial indexing

Passing `indexed: .hilbert` (or calling
``VectorTile/createIndex(sortOption:)``) builds an R-Tree for each layer.
Queries apply the same precise geometry test on indexed and non-indexed
tiles; the index only changes performance, not results.

## Overzoom and underzoom

``VectorTile/rezoom(toTargetX:targetY:targetZ:)`` returns a new tile at an
ancestor or descendant coordinate. Features are copied without clipping;
clipping happens at encode/export time. Use
``VectorTile/rezoom(_:toTargetX:targetY:targetZ:)`` to combine several source
tiles into one target tile.
