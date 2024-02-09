import Foundation
import MVTTools

/*
```console
# Download from MapLibre a vector tile at zoom 2, with an extent showing Norway to India
wget https://demotiles.maplibre.org/tiles/2/2/1.pbf
```
 */
//: Set the path to the `.pbf` file in `<playground>/Resources`
let playgroundFile = "maplibre.org_2_2_1.pbf"
let fileURL = Bundle.main.url(forResource: playgroundFile, withExtension: nil)!
let mvtData = try Data(contentsOf: fileURL)

//: Load tile using MVT
let tile = VectorTile(data: mvtData, x: 2, y: 1, z: 2, indexed: .hilbert)!

//: Inspect the properties of the `VectorTile`
tile.isIndexed
tile.projection

print(tile.layerNames.sorted())
//: ### MapLibre ZXY = 2/2/1 — Layers: ["centroids", "countries", "geolines"]
//: ![](maplibre.org_2_2_1.png)
//: ---
//: ### OpenStreetMap ZXY = 2/2/1
//: ![](openstreetmap.org_2_2_1.png)
