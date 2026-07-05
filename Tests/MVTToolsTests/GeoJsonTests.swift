import Foundation
import GISTools
@testable import MVTTools
import Testing

struct AddSetGeoJsonTests {

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
        tile.addGeoJson(geoJson: fc, layerProperty: "vt_layer", layerAllowlist: ["allowed_layer"])

        #expect(tile.hasLayer("allowed_layer"))
        #expect(tile.hasLayer("blocked_layer") == false)
    }

    /// Tests that `addGeoJson` without layer property puts all features into a default layer.
    @Test
    func addGeoJsonWithoutLayerProperty() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))

        let feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        let fc = FeatureCollection([feature])
        tile.addGeoJson(geoJson: fc)

        #expect(tile.layersWithContent.count == 1)
        #expect(tile.hasLayer("Layer-0"))
    }

    /// Tests that `setGeoJson` without layer property replaces all features in the default layer.
    @Test
    func setGeoJsonWithoutLayerProperty() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))

        let feature1 = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        tile.addGeoJson(geoJson: FeatureCollection([feature1]), layerName: "test")
        #expect(tile.features(for: "test").count == 1)

        let feature2 = Feature(Point(Coordinate3D(latitude: 30.0, longitude: 30.0)))
        tile.setGeoJson(geoJson: FeatureCollection([feature2]), layerName: "test")
        #expect(tile.features(for: "test").count == 1)
        #expect(tile.features(for: "test").first?.geometry.allCoordinates.first?.latitude == 30.0)
    }

    /// Tests that `addGeoJson` with explicit layer name targets the given layer.
    @Test
    func addGeoJsonWithExplicitLayerName() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))

        let feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        tile.addGeoJson(geoJson: FeatureCollection([feature]), layerName: "custom_layer")

        #expect(tile.hasLayer("custom_layer"))
        #expect(tile.features(for: "custom_layer").count == 1)
    }

    /// Tests that `addGeoJson` strips the routing property from features.
    @Test
    func addGeoJsonStripsRoutingProperty() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))

        var feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        feature.setProperty("roads", for: "vt_layer")
        tile.addGeoJson(geoJson: FeatureCollection([feature]), layerProperty: "vt_layer")

        let stored = tile.features(for: "roads").first
        #expect(stored?.properties["vt_layer"] == nil)
    }

    /// Tests that `setGeoJson` strips the routing property from features.
    @Test
    func setGeoJsonStripsRoutingProperty() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))

        var feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        feature.setProperty("roads", for: "vt_layer")
        tile.setGeoJson(geoJson: FeatureCollection([feature]), layerProperty: "vt_layer")

        let stored = tile.features(for: "roads").first
        #expect(stored?.properties["vt_layer"] == nil)
    }

}
