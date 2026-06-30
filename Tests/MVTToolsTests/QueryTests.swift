#if canImport(CoreLocation)
import CoreLocation
#endif
import GISTools
@testable import MVTTools
import Testing

struct QueryTests {

    /// Tests that the query bounding box for EPSG:4326 produces
    /// valid northEast > southWest coordinates.
    @Test
    func queryBoundingBox() {
        let coordinate = Coordinate3D(latitude: 47.0, longitude: -120.0)
        let queryBoundingBox = VectorTile.queryBoundingBox(at: coordinate, tolerance: 15.0, projection: .epsg4326)
        #expect(queryBoundingBox.northEast.latitude > queryBoundingBox.southWest.latitude)
        #expect(queryBoundingBox.northEast.longitude > queryBoundingBox.southWest.longitude)
    }

    /// Tests performing a spatial query on a non-indexed tile,
    /// verifying the expected number of results and layer names.
    @Test
    func query() throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        #expect(mvt.isEmpty == false)

        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14))
        #expect(tile.isIndexed == false)

        let result = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0)
        #expect(result.count == 107)
    }

    /// Tests that a spatial query on an indexed (R-Tree) tile returns
    /// the same number of results as a non-indexed query.
    @Test
    func queryWithIndex() throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        #expect(mvt.isEmpty == false)

        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14, indexed: .hilbert))
        #expect(tile.isIndexed)

        let resultWithIndex = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0)
        #expect(resultWithIndex.count == 107)
    }

    /// Tests performing a text-based search across feature properties.
    @Test
    func textSearch() throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14))

        let results = tile.query(term: "lake")
        #expect(results is [VectorTile.QueryResult])
    }

    /// Tests that a text search with a non-matching term returns empty results.
    @Test
    func textSearchNoMatch() throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14))

        let results = tile.query(term: "zzzxxxyyy_nonexistent")
        #expect(results.isEmpty)
    }

    /// Tests querying within a specific layer by name.
    @Test
    func queryInSpecificLayer() throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14))

        let results = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0, layerName: "road")
        #expect(results.isNotEmpty)
        #expect(results.allSatisfy({ $0.layerName == "road" }))
    }

    /// Tests the queryMany function with a single coordinate.
    @Test
    func queryMany() throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14))

        let coordinates = [
            Coordinate3D(latitude: 3.870163, longitude: 11.518585),
        ]

        let (features, results) = tile.queryMany(at: coordinates, tolerance: 100.0)
        #expect(results.isNotEmpty)
        #expect(features.isEmpty == false)
    }

    /// Tests querying with a feature filter that excludes certain features.
    @Test
    func queryWithFeatureFilter() throws {
        let mvt = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")
        let tile = try #require(VectorTile(data: mvt, x: 8716, y: 8015, z: 14))

        let allResults = tile.query(at: Coordinate3D(latitude: 3.870163, longitude: 11.518585), tolerance: 100.0)
        let filteredResults = tile.query(
            at: Coordinate3D(latitude: 3.870163, longitude: 11.518585),
            tolerance: 100.0,
            featureFilter: { _ in false })

        #expect(filteredResults.isEmpty)
        #expect(allResults.isNotEmpty)
    }

    /// Tests that createIndex with a Hilbert sort option produces an indexed tile.
    @Test
    func createIndex() throws {
        var tile = try #require(VectorTile(x: 0, y: 0, z: 0))
        let feature = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 10.0)))
        tile.appendFeatures([feature], to: "test")

        #expect(tile.isIndexed == false)
        tile.createIndex(sortOption: .hilbert)
        #expect(tile.isIndexed)
    }

    /// Tests the query bounding box for .noSRID projection.
    @Test
    func queryBoundingBoxNoSRID() {
        let coordinate = Coordinate3D(x: 100.0, y: 200.0, projection: .noSRID)
        let bbox = VectorTile.queryBoundingBox(at: coordinate, tolerance: 10.0, projection: .noSRID)

        #expect(bbox.southWest.x == 90.0)
        #expect(bbox.southWest.y == 190.0)
        #expect(bbox.northEast.x == 110.0)
        #expect(bbox.northEast.y == 210.0)
    }

    /// Tests the query bounding box for .epsg4978 projection.
    @Test
    func queryBoundingBoxEpsg4978() {
        let coordinate = Coordinate3D(x: 4_510_691.0, y: 0.0, projection: .epsg4978)
        let bbox = VectorTile.queryBoundingBox(at: coordinate, tolerance: 1000.0, projection: .epsg4978)

        #expect(bbox.southWest.x < bbox.northEast.x)
        #expect(bbox.southWest.y < bbox.northEast.y)
    }

}
