# ``MVTTools``

Read, write, convert, inspect, and query Mapbox/MapLibre vector tiles.

## Overview

`MVTTools` provides a single ``VectorTile`` value type for working with
vector tile data as GeoJSON-style `Feature` values. It supports:

- MVT (Mapbox Vector Tile 2.1, with version-1 layers decoded as well)
- MLT (MapLibre Tiles, behind the `EnableMLT` trait)
- GeoJSON, GPX, FIT, CSV, Shapefile, and GeoPackage conversion
- Web Mercator tile coordinates, overzoom/underzoom, merging, and spatial
  queries

```swift
import MVTTools

let data = try Data(contentsOf: url)
let tile = try VectorTile(mvtData: data, x: 8716, y: 8015, z: 14)

for layerName in tile.layerNames {
    print(layerName, tile.features(for: layerName).count)
}
```

The `mvt` command-line product is built from the `MVTCLI` target and uses the
same library code.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:TileModel>

### Formats and traits

- <doc:ImportExport>
- <doc:MLT>

### Command line and queries

- <doc:Commands>
- <doc:Querying>

### Behaviour and caveats

- <doc:Limitations>
- <doc:Concurrency>
