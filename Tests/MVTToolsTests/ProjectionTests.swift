#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools
import XCTest

@testable import MVTTools

final class ProjectionTests: XCTestCase {

    func testProjectToEpsg3857() {
        let projection1 = Projection.projectToEpsg3857(coordinate: Coordinate3D(latitude: 20.5, longitude: 10.5))
        XCTAssertEqual(projection1.latitude, 2332357.812619, accuracy: 0.00001)
        XCTAssertEqual(projection1.longitude, 1168854.653329, accuracy: 0.00001)

        let projection2 = Projection.projectToEpsg3857(coordinate: Coordinate3D(latitude: 45.0, longitude: -180.0))
        XCTAssertEqual(projection2.latitude, 5621521.486192, accuracy: 0.00001)
        XCTAssertEqual(projection2.longitude, -20037508.342789, accuracy: 0.00001)

        let projection3 = Projection.projectToEpsg3857(coordinate: Coordinate3D(latitude: -45.0, longitude: 45.0))
        XCTAssertEqual(projection3.latitude, -5621521.486192, accuracy: 0.00001)
        XCTAssertEqual(projection3.longitude, 5009377.085697, accuracy: 0.00001)
    }

    func testProjectToEpsg4326() {
        let projection1 = Projection.projectToEpsg4326(coordinate: Coordinate3D(latitude: 2332357.812619, longitude: 1168854.653329))
        XCTAssertEqual(projection1.latitude, 20.5, accuracy: 0.00001)
        XCTAssertEqual(projection1.longitude, 10.5, accuracy: 0.00001)

        let projection2 = Projection.projectToEpsg4326(coordinate: Coordinate3D(latitude: 5621521.486192, longitude: -20037508.342789))
        XCTAssertEqual(projection2.latitude, 45.0, accuracy: 0.00001)
        XCTAssertEqual(projection2.longitude, -180.0, accuracy: 0.00001)

        let projection3 = Projection.projectToEpsg4326(coordinate: Coordinate3D(latitude: -5621521.49, longitude: 5009377.09))
        XCTAssertEqual(projection3.latitude, -45.0, accuracy: 0.00001)
        XCTAssertEqual(projection3.longitude, 45.0, accuracy: 0.00001)
    }

    func testEpsg3857TileBounds() {
        let worldBounds = Projection.epsg3857TileBounds(x: 0, y: 0, z: 0)
        XCTAssertEqual(worldBounds.southWest.longitude, -20037508.342789, accuracy: 0.00001)
        XCTAssertEqual(worldBounds.southWest.latitude, -20037508.342789, accuracy: 0.00001)
        XCTAssertEqual(worldBounds.northEast.longitude, 20037508.342789, accuracy: 0.00001)
        XCTAssertEqual(worldBounds.northEast.latitude, 20037508.342789, accuracy: 0.00001)

        let z3Bounds = Projection.epsg3857TileBounds(x: 3, y: 3, z: 3)
        XCTAssertEqual(z3Bounds.southWest.longitude, -5009377.085697, accuracy: 0.00001)
        XCTAssertEqual(z3Bounds.southWest.latitude, 0.0, accuracy: 0.00001)
        XCTAssertEqual(z3Bounds.northEast.longitude, 0.0, accuracy: 0.00001)
        XCTAssertEqual(z3Bounds.northEast.latitude, 5009377.085697, accuracy: 0.00001)

        let z32Bounds = Projection.epsg3857TileBounds(x: 2145960701, y: 1428172928, z: 32)
        XCTAssertEqual(z32Bounds.southWest.longitude, -14210.149281, accuracy: 0.00001)
        XCTAssertEqual(z32Bounds.southWest.latitude, 6711666.720463, accuracy: 0.00001)
        XCTAssertEqual(z32Bounds.northEast.longitude, -14210.139951, accuracy: 0.00001)
        XCTAssertEqual(z32Bounds.northEast.latitude, 6711666.729793, accuracy: 0.00001)
    }

    func testEpsg4236TileBounds() {
        let worldBounds = Projection.epsg4236TileBounds(x: 0, y: 0, z: 0)
        XCTAssertEqual(worldBounds.southWest.longitude, -180.0, accuracy: 0.00001)
        XCTAssertEqual(worldBounds.southWest.latitude, -85.051128, accuracy: 0.00001)
        XCTAssertEqual(worldBounds.northEast.longitude, 180.0, accuracy: 0.00001)
        XCTAssertEqual(worldBounds.northEast.latitude, 85.051128, accuracy: 0.00001)

        let upperLeftWorld = Projection.epsg4236TileBounds(x: 0, y: 0, z: 1)
        XCTAssertEqual(upperLeftWorld.southWest.longitude, -180.0, accuracy: 0.00001)
        XCTAssertEqual(upperLeftWorld.southWest.latitude, 0.0, accuracy: 0.00001)
        XCTAssertEqual(upperLeftWorld.northEast.longitude, 0.0, accuracy: 0.00001)
        XCTAssertEqual(upperLeftWorld.northEast.latitude, 85.051128, accuracy: 0.00001)

        let z3Bounds = Projection.epsg4236TileBounds(x: 5, y: 10, z: 10)
        XCTAssertEqual(z3Bounds.southWest.longitude, -178.242187, accuracy: 0.00001)
        XCTAssertEqual(z3Bounds.southWest.latitude, 84.706048, accuracy: 0.00001)
        XCTAssertEqual(z3Bounds.northEast.longitude, -177.890625, accuracy: 0.00001)
        XCTAssertEqual(z3Bounds.northEast.latitude, 84.738387, accuracy: 0.00001)

        let z32Bounds = Projection.epsg4236TileBounds(x: 2145960701, y: 1428172928, z: 32)
        XCTAssertEqual(z32Bounds.southWest.longitude, -0.127651, accuracy: 0.00001)
        XCTAssertEqual(z32Bounds.southWest.latitude, 51.508094, accuracy: 0.00001)
        XCTAssertEqual(z32Bounds.northEast.longitude, -0.127651, accuracy: 0.00001)
        XCTAssertEqual(z32Bounds.northEast.latitude, 51.508094, accuracy: 0.00001)
    }

    func testTileFromCoordinate() {
        let center = Coordinate3D(latitude: 0.0, longitude: 0.0)
        let worldTile = Projection.tile(for: center, atZoom: 0)
        XCTAssertEqual(worldTile.x, 0)
        XCTAssertEqual(worldTile.y, 0)

        let zoom10Coordinate = Coordinate3D(latitude: 84.71, longitude: -178.0)
        let zoom10Tile = Projection.tile(for: zoom10Coordinate, atZoom: 10)
        XCTAssertEqual(zoom10Tile.x, 5)
        XCTAssertEqual(zoom10Tile.y, 10)

        let zoom18Coordinate = Coordinate3D(latitude: 1.0, longitude: 1.0)
        let zoom18Tile = Projection.tile(for: zoom18Coordinate, atZoom: 18)
        XCTAssertEqual(zoom18Tile.x, 131800)
        XCTAssertEqual(zoom18Tile.y, 130343)
    }

    static var allTests = [
        ("testProjectToEpsg3857", testProjectToEpsg3857),
        ("testProjectToEpsg4326", testProjectToEpsg4326),
        ("testEpsg3857TileBounds", testEpsg3857TileBounds),
        ("testEpsg4236TileBounds", testEpsg4236TileBounds),
        ("testTileFromCoordinate", testTileFromCoordinate),
    ]

}
