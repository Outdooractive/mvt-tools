#if !os(Linux)
    import CoreLocation
#endif
import GISTools
@testable import MVTTools
import Testing

struct QueryTests {

    @Test
    func queryBoundingBox() async throws {
        let coordinate = Coordinate3D(latitude: 47.0, longitude: -120.0)
        let queryBoundingBox = VectorTile.queryBoundingBox(at: coordinate, tolerance: 15.0, projection: .epsg4326)
        #expect(queryBoundingBox.northEast.latitude > queryBoundingBox.southWest.latitude)
        #expect(queryBoundingBox.northEast.longitude > queryBoundingBox.southWest.longitude)
    }

    @Test
    func query() async throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        #expect(mvt.isEmpty == false)

        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14))
        #expect(tile.isIndexed == false)

        let result = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0)
        #expect(result.count == 107)
    }

    @Test
    func queryWithIndex() async throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        #expect(mvt.isEmpty == false)

        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14, indexed: .hilbert))
        #expect(tile.isIndexed)

        let resultWithIndex = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0)
        #expect(resultWithIndex.count == 107)
    }

}
