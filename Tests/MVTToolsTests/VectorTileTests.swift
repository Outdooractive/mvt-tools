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
        XCTAssertEqual(resultLayerNames, ["barrier_line", "building", "building_label", "landuse", "road", "road_label"])

//        let string = String(data: tileAsJsonData!, encoding: .utf8)
//        try? string?.write(to: URL(fileURLWithPath: "/\(NSHomeDirectory())/Desktop/test.json"), atomically: true, encoding: .utf8)
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

    func testMerge() {
        var tile1 = VectorTile(x: 0, y: 0, z: 0)!
        var tile2 = VectorTile(x: 0, y: 0, z: 0)!
        var tile3 = VectorTile(x: 0, y: 0, z: 0)!

        let feature1 = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        let feature2 = Feature(Point(Coordinate3D(latitude: -10.0, longitude: -10.0)))

        XCTAssertEqual(tile1.features(for: "test1")?.count ?? 0, 0)
        XCTAssertEqual(tile1.features(for: "test2")?.count ?? 0, 0)

        tile1.appendFeatures([feature1], to: "test1")
        tile2.appendFeatures([feature2], to: "test1")
        tile3.appendFeatures([feature2], to: "test2")

        XCTAssertEqual(tile1.features(for: "test1")!.count, 1)
        XCTAssertTrue(tile1.merge(tile2))
        XCTAssertEqual(tile1.features(for: "test1")!.count, 2)

        XCTAssertEqual(tile1.features(for: "test2")?.count ?? 0, 0)
        XCTAssertTrue(tile1.merge(tile3))
        XCTAssertEqual(tile1.features(for: "test1")!.count, 2)
        XCTAssertEqual(tile1.features(for: "test2")!.count, 1)
    }

    func testEncodeDecodeBigInt() throws {
        let feature = try XCTUnwrap(Feature(jsonData: TestData.dataFromFile(name: "bigint_id.geojson")))
        XCTAssertEqual(feature.id, .uint(18446744073638380036))

        var tile = try XCTUnwrap(VectorTile(x: 10, y: 25, z: 6))
        tile.setFeatures([feature], for: "test")
        let tileData = try XCTUnwrap(tile.data())
        XCTAssertFalse(tileData.isEmpty)

        let tile2 = try XCTUnwrap(VectorTile(data: tileData, x: 10, y: 25, z: 6))
        let feature2: Feature = try XCTUnwrap(tile2.features(for: "test")?.first)

        XCTAssertEqual(feature.id, feature2.id)
    }

}
