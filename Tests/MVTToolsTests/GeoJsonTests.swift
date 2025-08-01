import CommonCrypto
import GISTools
@testable import MVTTools
import Testing

struct GeoJsonTests {

    @Test
    func toGeoJSON() async throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        #expect(mvt.isEmpty == false)

        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14))

        // Export all layers
        let allLayersJSONData = try #require(tile.toGeoJson(layerProperty: VectorTile.defaultLayerPropertyName))
        let allLayersFc = try #require(FeatureCollection(jsonData: allLayersJSONData))
        let allLayersLayerList = Set(try #require(allLayersFc.features.compactMap({ $0.properties[VectorTile.defaultLayerPropertyName] as? String })))
        #expect(Set(tile.layersWithContent.map(\.0)) == allLayersLayerList)

        // Export some layers
        let someLayers = ["landuse", "waterway", "water"]
        let someLayersJSONData = try #require(tile.toGeoJson(layerNames: someLayers, additionalFeatureProperties: ["test": "test"], layerProperty: VectorTile.defaultLayerPropertyName))
        let someLayersFc = try #require(FeatureCollection(jsonData: someLayersJSONData))
        let someLayersLayerList = Set(try #require(someLayersFc.features.compactMap({ $0.properties[VectorTile.defaultLayerPropertyName] as? String })))
        #expect(Set(someLayers) == someLayersLayerList)
        #expect(someLayersFc.features.allSatisfy({ ($0.properties["test"] as? String) == "test" }))
    }

    @Test
    func geoJSONWithNull() throws {
        let fc = FeatureCollection(Feature(Point(Coordinate3D(latitude: 47.56, longitude: 10.22, m: 1234))))
        var tile = try #require(VectorTile(x: 8657, y: 5725, z: 14))
        tile.addGeoJson(geoJson: fc, layerName: "test")

        let data = try #require(tile.data())
        let decodedTile = try #require(VectorTile(data: data, x: 8657, y: 5725, z: 14))
        let decodedFc = try #require(decodedTile.features(for: "test").first)
        let decodedCoordinate = try #require(decodedFc.geometry.allCoordinates.first)

        // Note: The MVT format doesn't encode altitude/m values, they will get lost
        #expect(abs(decodedCoordinate.latitude - 47.56) < 0.00001)
        #expect(abs(decodedCoordinate.longitude - 10.22) < 0.00001)
    }

}
