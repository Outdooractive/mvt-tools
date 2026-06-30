#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
import struct GISTools.Polygon
@testable import MVTTools
import Testing

struct VectorTileTests {

    /// Tests loading a real MVT tile from disk, verifying layer names match expected values,
    /// then exporting to GeoJSON and performing a spatial query.
    @Test
    func loadMvt() throws {
        let tileLayerNames: [String] = ["landuse", "waterway", "water", "aeroway", "barrier_line", "building", "landuse_overlay", "tunnel", "road", "bridge", "admin", "country_label_line", "country_label", "marine_label", "state_label", "place_label", "water_label", "area_label", "rail_station_label", "airport_label", "road_label", "waterway_label", "building_label"].sorted()

        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        #expect(mvt.isEmpty == false)

        let layerNames = VectorTile.layerNames(from: mvt)?.sorted()
        #expect(layerNames == tileLayerNames)

        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14))
        #expect(tile.layerNames.sorted() == tileLayerNames)

        let _ = try #require(tile.toGeoJson(prettyPrinted: true))

        let result = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0)
        let resultLayerNames: [String] = Set(result.map({ $0.layerName })).sorted()
        #expect(resultLayerNames == ["barrier_line", "building", "building_label", "landuse", "road", "road_label"])
    }

    /// Tests creating a tile with a point feature, setting properties (including arrays and dictionaries),
    /// encoding to MVT data, and verifying it produces valid output.
    @Test
    func writeMvt() throws {
        var tile = try #require(VectorTile(x: 8716, y: 8015, z: 14))

        var feature = Feature(Point(Coordinate3D(latitude: 3.870163, longitude: 11.518585)))
        feature.properties = [
            "test": 1,
            "test2": 5.567,
            "test3": [1, 2, 3],
            "test4": [
                "sub1": 1,
                "sub2": 2,
            ],
        ]

        tile.setFeatures([feature], for: "test")
        let _ = try #require(tile.data())
    }

    /// Tests that `tileInfo(from:)` returns layer metadata for a real MVT tile,
    /// with the expected number of layers.
    @Test
    func tileInfo() throws {
        let tileName = "14_8716_8015.vector.mvt"
        let mvt = try TestData.dataFromFile(name: tileName)
        #expect(mvt.isEmpty == false)

        let layers = try #require(VectorTile.tileInfo(from: mvt))
        #expect(layers.count == 23)
    }

    /// Tests merging two tiles with the same coordinate, verifying features
    /// from both source tiles appear in the result.
    @Test
    func merge() throws {
        var tile1 = try #require(VectorTile(x: 0, y: 0, z: 0))
        var tile2 = try #require(VectorTile(x: 0, y: 0, z: 0))
        var tile3 = try #require(VectorTile(x: 0, y: 0, z: 0))

        #expect(tile1.features(for: "test1").count == 0)
        #expect(tile1.features(for: "test2").count == 0)

        let feature1 = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        let feature2 = Feature(Point(Coordinate3D(latitude: -10.0, longitude: -10.0)))

        tile1.appendFeatures([feature1], to: "test1")
        tile2.appendFeatures([feature2], to: "test1")
        tile3.appendFeatures([feature2], to: "test2")

        #expect(tile1.features(for: "test1").count == 1)
        let tile1and2mergeResult = tile1.merge(tile2)
        #expect(tile1and2mergeResult)
        #expect(tile1.features(for: "test1").count == 2)

        #expect(tile1.features(for: "test2").count == 0)
        let tile1and3mergeResult = tile1.merge(tile3)
        #expect(tile1and3mergeResult)
        #expect(tile1.features(for: "test1").count == 2)
        #expect(tile1.features(for: "test2").count == 1)
    }

    /// Tests that a feature with a large integer ID (64-bit) survives
    /// encode-decode round trip without precision loss.
    @Test
    func encodeDecodeBigInt() throws {
        let feature = try #require(Feature(jsonData: TestData.dataFromFile(name: "bigint_id.geojson")))
        #expect(feature.id == .uint(18_446_744_073_638_380_036))

        var tile = try #require(VectorTile(x: 10, y: 25, z: 6))
        tile.setFeatures([feature], for: "test")
        let tileData = try #require(tile.data())
        #expect(tileData.isEmpty == false)

        let tile2 = try #require(VectorTile(data: tileData, x: 10, y: 25, z: 6))
        let feature2: Feature = try #require(tile2.features(for: "test").first)

        #expect(feature.id == feature2.id)
    }

    /// Tests that `extract(layerNames:)` creates a new tile containing only the specified layers.
    @Test
    func extractLayers() throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14))

        let extracted = try #require(tile.extract(layerNames: ["road", "building"]))
        #expect(extracted.layerNames.count == 2)
        #expect(extracted.hasLayer("road"))
        #expect(extracted.hasLayer("building"))
        #expect(extracted.hasLayer("water") == false)
    }

    /// Tests that `clear()` removes all layers and features from a tile.
    @Test
    func clearRemovesAllContent() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))
        let feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        tile.appendFeatures([feature], to: "test")

        #expect(tile.isEmpty == false)

        tile.clear()
        #expect(tile.isEmpty)
        #expect(tile.layerNames.isEmpty)
        #expect(tile.layersWithContent.isEmpty)
    }

    /// Tests that `isEmpty` returns true for a newly created empty tile.
    @Test
    func isEmptyForNewTile() throws {
        let tile = try #require(VectorTile(x: 0, y: 0, z: 0))
        #expect(tile.isEmpty)
        #expect(tile.layersWithContent.isEmpty)
    }

    /// Tests that `hasLayer(_:)` correctly identifies present and absent layers.
    @Test
    func hasLayer() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))
        #expect(tile.hasLayer("test") == false)

        let feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        tile.appendFeatures([feature], to: "test")
        #expect(tile.hasLayer("test"))
    }

    /// Tests that `removeLayer(_:)` removes the layer and returns its features.
    @Test
    func removeLayer() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))
        let feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        tile.appendFeatures([feature], to: "test")

        let removedFeatures = tile.removeLayer("test")
        #expect(removedFeatures?.count == 1)
        #expect(tile.hasLayer("test") == false)
        #expect(tile.isEmpty)
    }

    /// Tests that `removeFeatures(fromLayer:where:)` removes only matching features.
    @Test
    func removeFeaturesWhere() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))
        let feature1 = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        let feature2 = Feature(Point(Coordinate3D(latitude: 20.0, longitude: 20.0)))

        tile.appendFeatures([feature1, feature2], to: "test")
        #expect(tile.features(for: "test").count == 2)

        tile.removeFeatures(fromLayer: "test", where: { feature in
            feature.geometry.allCoordinates.first?.latitude == 10.0
        })
        #expect(tile.features(for: "test").count == 1)
        #expect(tile.features(for: "test").first?.geometry.allCoordinates.first?.latitude == 20.0)
    }

    /// Tests that invalid tile coordinates (negative x/y/z) return nil.
    @Test
    func invalidCoordinatesReturnNil() {
        #expect(VectorTile(x: -1, y: 0, z: 0) == nil)
        #expect(VectorTile(x: 0, y: -1, z: 0) == nil)
        #expect(VectorTile(x: 0, y: 0, z: -1) == nil)
    }

    /// Tests that tile coordinates exceeding the maximum at a given zoom level return nil.
    @Test
    func outOfBoundsCoordinatesReturnNil() {
        #expect(VectorTile(x: 4, y: 2, z: 2) == nil)
        #expect(VectorTile(x: 2, y: 4, z: 2) == nil)
    }

    /// Tests that `layersWithContent` only includes layers that have features.
    @Test
    func layersWithContent() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))
        let feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))

        #expect(tile.layersWithContent.isEmpty)

        tile.appendFeatures([feature], to: "test1")
        #expect(tile.layersWithContent.count == 1)

        tile.setFeatures([], for: "test2")
        #expect(tile.layersWithContent.count == 1)
    }

    /// Tests that a GeoJSON file can be loaded directly into a tile and produces valid MVT data.
    @Test
    func loadGeoJson() throws {
        let geoJsonData = try TestData.dataFromFile(name: "14_8716_8015.geojson")
        let tile = try #require(VectorTile(geoJsonData: geoJsonData, layerProperty: nil))
        #expect(tile.isEmpty == false)
        #expect(tile.origin == .geoJson)

        let mvtData = try #require(tile.data())
        #expect(mvtData.isEmpty == false)
    }

    /// Tests writing tile data to a file and reading it back.
    @Test
    func writeMvtToFile() throws {
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test_write_to_file_\(UUID().uuidString).mvt")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))
        let feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        tile.appendFeatures([feature], to: "test")

        let success = tile.write(to: tempUrl)
        #expect(success)

        let readTile = try #require(VectorTile(contentsOf: tempUrl, x: 0, y: 0, z: 0))
        #expect(readTile.features(for: "test").count == 1)
    }

    /// Tests writing GeoJSON to a file and reading it back.
    @Test
    func writeGeoJsonToFile() throws {
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test_write_geojson_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))
        let feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        tile.appendFeatures([feature], to: "test")

        let success = tile.writeGeoJson(to: tempUrl)
        #expect(success)

        let readTile = try #require(VectorTile(contentsOfGeoJson: tempUrl, layerProperty: nil))
        #expect(readTile.isEmpty == false)
    }

    /// Tests that `layerNames(from:)` returns nil for invalid data.
    @Test
    func layerNamesFromInvalidData() {
        let invalidData = Data([0x00, 0x01, 0x02])
        #expect(VectorTile.layerNames(from: invalidData) == nil)
    }

    /// Tests that `layerNames(from:)` returns an empty array for empty protobuf data.
    @Test
    func layerNamesFromEmptyData() {
        let names = VectorTile.layerNames(from: Data())
        #expect(names != nil)
        #expect(names?.isEmpty == true)
    }

    /// Tests that the tile is created with the correct projection
    /// and coordinates from the MapTile convenience initializer.
    @Test
    func initWithMapTile() throws {
        let mapTile = MapTile(x: 100, y: 200, z: 8)
        let tile = try #require(VectorTile(tile: mapTile, projection: .epsg3857))

        #expect(tile.x == 100)
        #expect(tile.y == 200)
        #expect(tile.z == 8)
        #expect(tile.projection == .epsg3857)
        #expect(tile.mapTile == mapTile)
    }

}
