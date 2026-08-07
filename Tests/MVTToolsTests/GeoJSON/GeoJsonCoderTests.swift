import Foundation
import GISTools
@testable import MVTTools
import Testing

struct GeoJsonFormatIOTests {

    /// Tests exporting a tile to GeoJSON with all layers and with a subset of layers,
    /// verifying that the correct layer names appear in the output feature properties.
    @Test
    func toGeoJSON() throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        #expect(mvt.isEmpty == false)

        let tile = try VectorTile(mvtData: mvt, x: 8716, y: 8015, z: 14)

        let allLayersJSONData = try #require(tile.toGeoJson(layerProperty: VectorTile.defaultLayerPropertyName))
        let allLayersFc = try #require(FeatureCollection(jsonData: allLayersJSONData))
        let allLayersLayerList = Set(try #require(allLayersFc.features.compactMap({ $0.properties[VectorTile.defaultLayerPropertyName] as? String })))
        #expect(Set(tile.layersWithContent.map(\.0)) == allLayersLayerList)

        let someLayers = ["landuse", "waterway", "water"]
        let someLayersJSONData = try #require(tile.toGeoJson(layerNames: someLayers, additionalFeatureProperties: ["test": "test"], layerProperty: VectorTile.defaultLayerPropertyName))
        let someLayersFc = try #require(FeatureCollection(jsonData: someLayersJSONData))
        let someLayersLayerList = Set(try #require(someLayersFc.features.compactMap({ $0.properties[VectorTile.defaultLayerPropertyName] as? String })))
        #expect(Set(someLayers) == someLayersLayerList)
        #expect(someLayersFc.features.allSatisfy({ ($0.properties["test"] as? String) == "test" }))
    }

    /// Tests that MVT encoding/decoding round-trips a GeoJSON feature with null/m values correctly
    /// (note: MVT format does not preserve altitude or m values).
    @Test
    func geoJSONWithNull() throws {
        let fc = FeatureCollection(Feature(Point(Coordinate3D(latitude: 47.56, longitude: 10.22, m: 1234))))
        var tile = try VectorTile(x: 8657, y: 5725, z: 14)
        tile.addGeoJson(geoJson: fc, layerName: "test")

        let data = try #require(tile.mvtData())
        let decodedTile = try VectorTile(mvtData: data, x: 8657, y: 5725, z: 14)
        let decodedFc = try #require(decodedTile.features(for: "test").first)
        let decodedCoordinate = try #require(decodedFc.geometry.allCoordinates.first)

        #expect(abs(decodedCoordinate.latitude - 47.56) < 0.00001)
        #expect(abs(decodedCoordinate.longitude - 10.22) < 0.00001)
    }

    /// Tests that a GeoJSON file can be loaded directly into a tile and produces valid MVT data.
    @Test
    func loadGeoJson() throws {
        let geoJsonData = try TestData.dataFromFile(name: "14_8716_8015.geojson")
        let tile = try VectorTile(geoJsonData: geoJsonData, layerProperty: nil)
        #expect(tile.isEmpty == false)
        #expect(tile.origin == .geoJson)

        let mvtData = try #require(tile.mvtData())
        #expect(mvtData.isEmpty == false)
    }

    /// Tests writing GeoJSON to a file and reading it back.
    @Test
    func writeGeoJsonToFile() throws {
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test_write_geojson_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        var tile = try VectorTile(x: 0, y: 0, z: 0)
        let feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        tile.appendFeatures([feature], to: "test")

        let success = tile.writeGeoJson(to: tempUrl)
        #expect(success)

        let readTile = try VectorTile(contentsOfGeoJson: tempUrl, layerProperty: nil)
        #expect(readTile.isEmpty == false)
    }

}
