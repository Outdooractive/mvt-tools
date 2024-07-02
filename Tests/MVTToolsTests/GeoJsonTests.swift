import XCTest

import CommonCrypto
import GISTools
@testable import MVTTools

final class GeoJsonTests: XCTestCase {

    func testToGeoJSON() async throws {
        let tileName = "14_8716_8015.vector.mvt"
        let mvt = TestData.dataFromFile(name: tileName)
        XCTAssertFalse(mvt.isEmpty)

        let tile = try XCTUnwrap(VectorTile(data: mvt, x: 8716, y: 8015, z: 14))

        // Export all layers
        let allLayersFc = try XCTUnwrap(FeatureCollection(jsonData: try XCTUnwrap(tile.toGeoJson())))
        let allLayersLayerList = Set(try XCTUnwrap(allLayersFc.features.compactMap({ $0.properties["vt_layer"] as? String })))
        XCTAssertEqual(Set(tile.layersWithContent.map(\.0)), allLayersLayerList)

        // Export some layers
        let someLayers = ["landuse", "waterway", "water"]
        let someLayersFc = try XCTUnwrap(FeatureCollection(jsonData: try XCTUnwrap(tile.toGeoJson(layerNames: someLayers, additionalFeatureProperties: ["test": "test"]))))
        let someLayersLayerList = Set(try XCTUnwrap(someLayersFc.features.compactMap({ $0.properties["vt_layer"] as? String })))
        XCTAssertEqual(Set(someLayers), someLayersLayerList)
        XCTAssertTrue(someLayersFc.features.allSatisfy({ ($0.properties["test"] as? String) == "test" }))
    }

    func testGeoJSONWithNull() throws {
        let fc = FeatureCollection(Feature(Point(Coordinate3D(latitude: 47.56, longitude: 10.22, m: 1234))))
        var tile = try XCTUnwrap(VectorTile(x: 8657, y: 5725, z: 14))
        tile.addGeoJson(geoJson: fc, layerName: "test")

        let data = try XCTUnwrap(tile.data())

        let decodedTile = try XCTUnwrap(VectorTile(data: data, x: 8657, y: 5725, z: 14))
        let decodedFc = try XCTUnwrap(decodedTile.features(for: "test")?.first)
        let decodedCoordinate = try XCTUnwrap(decodedFc.geometry.allCoordinates.first)

        // Note: The MVT format doesn't encode altitude/m values, they will get lost
        XCTAssertEqual(decodedCoordinate.latitude, 47.56, accuracy: 0.00001)
        XCTAssertEqual(decodedCoordinate.longitude, 10.22, accuracy: 0.00001)
    }

}
