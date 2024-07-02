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

}
