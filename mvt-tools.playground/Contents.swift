import Foundation
import CoreLocation
import GISTools
import MVTTools

//: # MVTTools Playground
//: Explore the MapLibre/Mapbox Vector Tile library interactively.

//: ## 1. Load a vector tile
//: The tile must be in the playground's Resources folder.
//: Download one with: `cd Resources && ./get_vector_tile.sh`
let playgroundFile = "maplibre.org_2_2_1.pbf"
let fileURL = Bundle.main.url(forResource: playgroundFile, withExtension: nil)!
let mvtData = try Data(contentsOf: fileURL)

//: Create a VectorTile from raw MVT data — requires the tile coordinate (z/x/y).
let tile = VectorTile(data: mvtData, x: 2, y: 1, z: 2, indexed: .hilbert)!
tile.isIndexed       // true — R-Tree index is built
tile.projection      // .epsg4326
tile.boundingBox     // tile bounds in EPSG:4326
tile.layerNames.sorted()  // ["centroids", "countries", "geolines"]

//: ## 2. Layer management
//: Access and inspect features per layer.
tile.features(for: "countries").count    // number of country features
tile.hasLayer("centroids")               // true
tile.hasLayer("roads")                   // false

//: Extract a subset of layers into a new tile.
let countriesOnly = tile.extract(layerNames: ["countries"])!
countriesOnly.layerNames  // ["countries"]

//: ## 3. Tile metadata
//: Get per-layer feature counts and property statistics.
if let info = tile.tileInfo() {
    for layer in info {
        print("\(layer.name): \(layer.features) features " +
              "(\(layer.pointFeatures)pt, \(layer.linestringFeatures)ls, \(layer.polygonFeatures)pg)")
    }
}

//: Layer names from raw data (no VectorTile instance needed).
VectorTile.layerNames(from: mvtData)  // ["centroids", "countries", "geolines"]

//: Static tile info (also works without creating a VectorTile).
VectorTile.tileInfo(from: mvtData)?.first?.propertyNames

//: ## 4. Spatial queries
//: Find features near a coordinate.
let results = tile.query(
    at: Coordinate3D(latitude: 30.0, longitude: 10.0),
    tolerance: 5_000_000)  // 5000 km tolerance
results.count               // features near the Sahara

//: Query within a specific layer.
tile.query(
    at: Coordinate3D(latitude: 30.0, longitude: 10.0),
    tolerance: 5_000_000,
    layerName: "countries").count

//: Query with a bounding box.
let bbox = BoundingBox(
    southWest: Coordinate3D(latitude: -10.0, longitude: -20.0),
    northEast: Coordinate3D(latitude: 40.0, longitude: 30.0))
tile.query(in: bbox, layerName: "countries").count

//: ## 5. Text search with the query DSL
//: The query DSL supports property comparisons, boolean logic, regex, string operators,
//: set membership, and spatial predicates.

//: Literal text search — finds features whose properties contain "Fran" (full-text).
let parser = QueryParser(string: "Fran")!
let results2 = tile.query(term: "Fran")

//: Property value comparison.
tile.query(term: ".name == 'France'").count

//: Numeric comparison.
tile.query(term: ".scalerank > 3")

//: Boolean combination.
tile.query(term: ".name =~ /^C/ and .scalerank < 3")

//: String operators.
tile.query(term: ".name =* 'land'")       // contains "land"
tile.query(term: ".name =^ 'South'")      // starts with "South"
tile.query(term: ".name =$ 'land'")       // ends with "land"

//: Set membership.
tile.query(term: ".name in ['France', 'Germany', 'Italy']")

//: Existence check.
tile.query(term: ".name exists")
tile.query(term: ".nonexistent not")      // true if property is absent

//: Spatial + property combined.
tile.query(term: ".scalerank < 4 and near(30.0, 10.0, 5000000)")

//: `within` bbox containment.
tile.query(term: "within(-10.0, -10.0, 40.0, 40.0)")

//: `intersects` bbox intersection.
tile.query(term: "intersects(-10.0, -10.0, 40.0, 40.0)")

//: ## 6. Export to GeoJSON
//: Export all layers.
let allGeoJSON = tile.toGeoJson(prettyPrinted: true)!
String(data: allGeoJSON, encoding: .utf8)!.prefix(200)

//: Export specific layers only.
let subsetGeoJSON = tile.toGeoJson(
    layerNames: ["countries"],
    prettyPrinted: true,
    layerProperty: "vt_layer")!

//: Export with simplification.
let simplified = tile.toGeoJson(
    options: .init(simplifyFeatures: .meters(100_000)))

//: ## 7. Export options for MVT output
//: Configure buffering, compression, and simplification.

//: Default options (no buffer, no compression, no simplification).
tile.data()?.count

//: With gzip compression.
tile.data(options: .init(compression: .level(9)))?.count

//: With buffer and simplification.
let options = VectorTile.ExportOptions(
    bufferSize: .pixel(4),
    compression: .default,
    simplifyFeatures: .meters(1000.0))
tile.data(options: options)?.count

//: ## 8. Modify tile content
//: Add features, remove layers, merge tiles.

var mutableTile = VectorTile(x: 0, y: 0, z: 0)!

var point = Feature(Point(Coordinate3D(latitude: 48.0, longitude: 11.0)))
point.properties = ["name": "Munich", "population": 1_500_000]

mutableTile.appendFeatures([point], to: "cities")
mutableTile.features(for: "cities").count  // 1

mutableTile.setFeatures([], for: "cities")  // replace with empty
mutableTile.features(for: "cities").isEmpty // true

//: Merge tiles.
let anotherTile = VectorTile(x: 0, y: 0, z: 0)!
mutableTile.merge(anotherTile)

//: ## 9. Load from GeoJSON
//: You can create a VectorTile directly from GeoJSON data.
//: Tile coordinates are derived from the feature bounding box.

//: (No GeoJSON file in Resources — this demonstrates the API)
// let geoJsonData = try Data(contentsOf: ...)
// let geojsonTile = VectorTile(geoJsonData: geoJsonData, layerProperty: "vt_layer")

//: ## 10. Direct QueryParser usage
//: The QueryParser can be used programmatically without a tile.

let parser2 = QueryParser(string: ".scalerank < 4 and .name =~ '^C'")!
let feature = tile.features(for: "countries").first!
parser2.evaluate(on: feature)  // true or false

//: Build a pipeline manually.
let manualPipeline: [QueryParser.Expression] = [
    .value([.key("scalerank")]),
    .literal(4),
    .comparison(.lessThan),
]
let manualParser = QueryParser(pipeline: manualPipeline)
manualParser.evaluate(on: feature)

//: ---
//: ![](maplibre.org_2_2_1.png)
//: MapLibre ZXY = 2/2/1 — Layers: centroids, countries, geolines
//: ![](openstreetmap.org_2_2_1.png)
//: OpenStreetMap ZXY = 2/2/1
