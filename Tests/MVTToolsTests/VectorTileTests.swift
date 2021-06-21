#if !os(Linux)
import CoreLocation
#endif
import GISTools
import struct GISTools.Polygon
import XCTest

@testable import MVTTools

final class VectorTileTests: XCTestCase {

    func testLoadMvt() {
        let tileName: String = "14_8716_8015.vector.mvt"
        let tileLayerNames: [String] = ["landuse", "waterway", "water", "aeroway", "barrier_line", "building", "landuse_overlay", "tunnel", "road", "bridge", "admin", "country_label_line", "country_label", "marine_label", "state_label", "place_label", "water_label", "area_label", "rail_station_label", "airport_label", "road_label", "waterway_label", "building_label"].sorted()

        let mvt = TestData.dataFromFile(name: tileName)
        XCTAssertFalse(mvt.isEmpty)

        let layerNames = VectorTile.layerNames(from: mvt)?.sorted()
        XCTAssertEqual(layerNames, tileLayerNames)

//        guard let tile = VectorTile(data: mvt, x: 8716, y: 8015, z: 14, layerWhitelist: ["road"]) else {
        guard let tile = VectorTile(data: mvt, x: 8716, y: 8015, z: 14) else {
            XCTAssert(false, "Unable to parse the vector tile \(tileName)")
            return
        }
        XCTAssertEqual(tile.layerNames.sorted(), tileLayerNames)

        let tileAsJsonData: Data? = tile.toGeoJson(prettyPrinted: true)
        XCTAssertNotNil(tileAsJsonData)

        let result = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0)
        let resultLayerNames: [String] = Set(result.map({ $0.layerName })).sorted()
        XCTAssertEqual(resultLayerNames, ["barrier_line", "building", "building_label", "road", "road_label"])

//        let string = String(data: tileAsJsonData!, encoding: .utf8)
//        try? string?.write(to: URL(fileURLWithPath: "/\(NSHomeDirectory())/Desktop/test.json"), atomically: true, encoding: .utf8)
    }

    func testQuery() {
        let tileName: String = "14_8716_8015.vector.mvt"
        let mvt = TestData.dataFromFile(name: tileName)
        XCTAssertFalse(mvt.isEmpty)

        guard let tile = VectorTile(data: mvt, x: 8716, y: 8015, z: 14) else {
            XCTAssert(false, "Unable to parse the vector tile \(tileName)")
            return
        }

        measure {
            let result = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0)
            XCTAssertNotNil(result)
            XCTAssertEqual(result.count, 68)
        }
    }

    func testQueryWithIndex() {
        let tileName: String = "14_8716_8015.vector.mvt"
        let mvt = TestData.dataFromFile(name: tileName)
        XCTAssertFalse(mvt.isEmpty)

        guard var tile = VectorTile(data: mvt, x: 8716, y: 8015, z: 14) else {
            XCTAssert(false, "Unable to parse the vector tile \(tileName)")
            return
        }

        tile.createIndex()

        measure {
            let resultWithIndex = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0)
            XCTAssertNotNil(resultWithIndex)
            XCTAssertEqual(resultWithIndex.count, 68)
        }
    }

    func testWriteMvt() {
        guard var tile = VectorTile(x: 8716, y: 8015, z: 14) else {
            XCTAssert(false, "Unable to create a vector tile")
            return
        }

        var feature = Feature(Point(Coordinate3D(latitude: 3.870163, longitude: 11.518585)))
        feature.properties = [
            "test": 1,
            "test2": 5.567,
            "test3": [1, 2, 3],
            "test4": [
                "sub1": 1,
                "sub2": 2
            ]
        ]

        tile.setFeatures([feature], for: "test")
        let tileData = tile.data()
        XCTAssertNotNil(tileData)

//        tile.write(to: URL(fileURLWithPath: "/\(NSHomeDirectory())/Desktop/14_8716_8015.test.mvt"))
    }

    func testTileInfo() {
        let tileName: String = "14_8716_8015.vector.mvt"
        let mvt = TestData.dataFromFile(name: tileName)
        XCTAssertFalse(mvt.isEmpty)

        guard let info = VectorTile.tileInfo(from: mvt) else {
            XCTAssert(false, "Unable to parse the vector tile \(tileName)")
            return
        }

        XCTAssertFalse(info.isEmpty)

        guard let layers = info["layers"] as? [[String: Any]] else {
            XCTAssert(false, "Info without 'layers'")
            return
        }
        guard let errors = info["errors"] as? Bool else {
            XCTAssert(false, "Info without 'errors'")
            return
        }

        XCTAssertEqual(errors, false)
        XCTAssertEqual(layers.count, 23)
    }

    static var allTests = [
        ("testLoadMvt", testLoadMvt),
        ("testQuery", testQuery),
        ("testQueryWithIndex", testQueryWithIndex),
        ("testWriteMvt", testWriteMvt),
        ("testTileInfo", testTileInfo),
    ]

}
