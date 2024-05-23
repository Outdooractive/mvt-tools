#if !os(Linux)
    import CoreLocation
#endif
import GISTools
import XCTest

@testable import MVTTools

final class QueryTests: XCTestCase {

    func testQueryBoundingBox() {
        let coordinate = Coordinate3D(latitude: 47.0, longitude: -120.0)
        let queryBoundingBox = VectorTile.queryBoundingBox(at: coordinate, tolerance: 15.0, projection: .epsg4326)
        XCTAssertGreaterThan(queryBoundingBox.northEast.latitude, queryBoundingBox.southWest.latitude)
        XCTAssertGreaterThan(queryBoundingBox.northEast.longitude, queryBoundingBox.southWest.longitude)
    }

    func testQuery() {
        let tileName = "14_8716_8015.vector.mvt"
        let mvt = TestData.dataFromFile(name: tileName)
        XCTAssertFalse(mvt.isEmpty)

        guard let tile = VectorTile(data: mvt, x: 8716, y: 8015, z: 14) else {
            XCTAssert(false, "Unable to parse the vector tile \(tileName)")
            return
        }

        XCTAssertFalse(tile.isIndexed)

        measure {
            let result = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0)
            XCTAssertNotNil(result)
            XCTAssertEqual(result.count, 107)
        }
    }

    func testQueryWithIndex() {
        let tileName = "14_8716_8015.vector.mvt"
        let mvt = TestData.dataFromFile(name: tileName)
        XCTAssertFalse(mvt.isEmpty)

        guard let tile = VectorTile(data: mvt, x: 8716, y: 8015, z: 14, indexed: .hilbert) else {
            XCTAssert(false, "Unable to parse the vector tile \(tileName)")
            return
        }

        XCTAssertTrue(tile.isIndexed)

        measure {
            let resultWithIndex = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0)
            XCTAssertNotNil(resultWithIndex)
            XCTAssertEqual(resultWithIndex.count, 107)
        }
    }

}
