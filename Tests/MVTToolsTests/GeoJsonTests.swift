import Foundation
import GISTools
@testable import MVTTools
import Testing

struct GeoJsonTests {

    /// Tests exporting a tile to GeoJSON with all layers and with a subset of layers,
    /// verifying that the correct layer names appear in the output feature properties.
    @Test
    func toGeoJSON() throws {
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

    /// Tests that MVT encoding/decoding round-trips a GeoJSON feature with null/m values correctly
    /// (note: MVT format does not preserve altitude or m values).
    @Test
    func geoJSONWithNull() throws {
        let fc = FeatureCollection(Feature(Point(Coordinate3D(latitude: 47.56, longitude: 10.22, m: 1234))))
        var tile = try #require(VectorTile(x: 8657, y: 5725, z: 14))
        tile.addGeoJson(geoJson: fc, layerName: "test")

        let data = try #require(tile.data())
        let decodedTile = try #require(VectorTile(data: data, x: 8657, y: 5725, z: 14))
        let decodedFc = try #require(decodedTile.features(for: "test").first)
        let decodedCoordinate = try #require(decodedFc.geometry.allCoordinates.first)

        #expect(abs(decodedCoordinate.latitude - 47.56) < 0.00001)
        #expect(abs(decodedCoordinate.longitude - 10.22) < 0.00001)
    }

    /// Tests that `addGeoJson` with a layer property distributes features into layers
    /// based on the property value, and respects the layer allow list.
    @Test
    func addGeoJsonWithLayerProperty() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))

        var feature1 = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        feature1.setProperty("roads", for: "vt_layer")
        var feature2 = Feature(Point(Coordinate3D(latitude: 20.0, longitude: 20.0)))
        feature2.setProperty("buildings", for: "vt_layer")

        let fc = FeatureCollection([feature1, feature2])
        tile.addGeoJson(geoJson: fc, layerProperty: "vt_layer")

        #expect(tile.hasLayer("roads"))
        #expect(tile.hasLayer("buildings"))
        #expect(tile.features(for: "roads").count == 1)
        #expect(tile.features(for: "buildings").count == 1)
    }

    /// Tests that `setGeoJson` replaces features in a layer but does not remove other layers.
    @Test
    func setGeoJsonReplacesContent() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))

        var feature1 = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        feature1.setProperty("layer_a", for: "vt_layer")
        tile.addGeoJson(geoJson: FeatureCollection([feature1]), layerProperty: "vt_layer")
        #expect(tile.features(for: "layer_a").count == 1)

        var feature2 = Feature(Point(Coordinate3D(latitude: 30.0, longitude: 30.0)))
        feature2.setProperty("layer_a", for: "vt_layer")
        tile.setGeoJson(geoJson: FeatureCollection([feature2]), layerProperty: "vt_layer")

        #expect(tile.features(for: "layer_a").count == 1)
        #expect(tile.features(for: "layer_a").first?.geometry.allCoordinates.first?.latitude == 30.0)
    }

    /// Tests that `addGeoJson` with a layer allow list only imports the specified layers.
    @Test
    func addGeoJsonWithLayerAllowList() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))

        var feature1 = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        feature1.setProperty("allowed_layer", for: "vt_layer")
        var feature2 = Feature(Point(Coordinate3D(latitude: 20.0, longitude: 20.0)))
        feature2.setProperty("blocked_layer", for: "vt_layer")

        let fc = FeatureCollection([feature1, feature2])
        tile.addGeoJson(geoJson: fc, layerProperty: "vt_layer", layerAllowList: ["allowed_layer"])

        #expect(tile.hasLayer("allowed_layer"))
        #expect(tile.hasLayer("blocked_layer") == false)
    }

}
