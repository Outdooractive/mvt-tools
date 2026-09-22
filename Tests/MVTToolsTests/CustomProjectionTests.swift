#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
@testable import MVTTools
import Synchronization
import Testing

/// Tests for MVT encoding/decoding with projections registered at runtime
/// via ``Projection.register(_:)``.
struct CustomProjectionTests {

    /// SRID pool for this suite: unique per test call, since registration is
    /// add-only and process-global.
    private static let sridCounter = Mutex(901_500)

    private static func nextSrid(_ count: Int = 1) -> Int {
        sridCounter.withLock { value -> Int in
            let start = value
            value += count
            return start
        }
    }

    /// A simple planar "scaled degrees" projection: degrees × 1_000,
    /// round-tripping exactly.
    private static func scaledDegrees(srid: Int) -> CustomProjection {
        CustomProjection(
            srid: srid,
            kind: .planar,
            wraparoundExtent: 180_000.0,
            validExtent: ProjectionExtent(
                minX: -180_000.0,
                minY: -90_000.0,
                maxX: 180_000.0,
                maxY: 90_000.0),
            worldBoundingBox: nil,
            wktMatchers: [["PROJCS", "Scaled Test Grid \(srid)"]],
            forward: { coordinate in
                Coordinate3D(
                    latitude: coordinate.latitude * 1_000.0,
                    longitude: coordinate.longitude * 1_000.0,
                    altitude: coordinate.altitude,
                    m: coordinate.m)
            },
            inverse: { coordinate in
                Coordinate3D(
                    latitude: coordinate.latitude / 1_000.0,
                    longitude: coordinate.longitude / 1_000.0,
                    altitude: coordinate.altitude,
                    m: coordinate.m)
            })
    }

    /// Tests that a tile in a custom registered projection decodes and encodes
    /// with coordinates correctly transformed through the projection's
    /// forward/inverse math.
    @Test
    func mvtRoundTripWithCustomProjection() throws {
        let srid = Self.nextSrid()
        let custom = Self.scaledDegrees(srid: srid)
        #expect(Projection.register(custom))
        let projection = try #require(Projection(srid: srid))

        // A point at the center of tile 1/1/1 (top-left quadrant of the world).
        var tile = try VectorTile(x: 1, y: 1, z: 1, projection: projection)
        let center = tile.boundingBox.center
        #expect(center.projection.srid == srid)

        tile.setFeatures([
            Feature(Point(center)),
        ], for: "layer")

        let data = try #require(tile.mvtData())
        #expect(!data.isEmpty)

        let decoded = try VectorTile(mvtData: data, x: 1, y: 1, z: 1, projection: projection)
        #expect(decoded.projection.srid == srid)
        #expect(decoded.layers["layer"]?.features.count == 1)

        // MVT geometry integers quantize to the extent grid: the round trip
        // is accurate to one extent cell per axis (span / 4096).
        let decodedPoint = try #require(decoded.layers["layer"]?.features.first?.geometry as? Point)
        #expect(decodedPoint.coordinate.projection.srid == srid)
        #expect(abs(decodedPoint.coordinate.latitude - center.latitude) < 21.0)
        #expect(abs(decodedPoint.coordinate.longitude - center.longitude) < 44.0)
    }

    /// Tests that a custom projection tile reports a bounding box in the
    /// custom projection's units (not silently in Web Mercator meters).
    @Test
    func customProjectionBoundingBoxUnits() throws {
        let srid = Self.nextSrid()
        #expect(Projection.register(Self.scaledDegrees(srid: srid)))
        let projection = try #require(Projection(srid: srid))

        let tile = try VectorTile(x: 1, y: 1, z: 1, projection: projection)
        let boundingBox = tile.boundingBox

        #expect(boundingBox.projection.srid == srid)
        // Tile 1/1/1 is the south-east quadrant: longitude (0, 180) and
        // latitude (-85.05112878, 0), scaled by 1_000 in the custom
        // projection.
        #expect(abs(boundingBox.southWest.longitude - 0.0) < 0.000001)
        #expect(abs(boundingBox.northEast.longitude - 180_000.0) < 0.000001)
        #expect(abs(boundingBox.southWest.latitude - -85_051.12878) < 0.001)
        #expect(abs(boundingBox.northEast.latitude - 0.0) < 0.000001)
    }

    /// Tests that decoding MVT data written with EPSG:4326 into a custom
    /// projection expresses the same geographic location in the custom
    /// projection's coordinate space (tile-local integers are
    /// projection-independent; the decoded coordinates carry the requested
    /// projection's units).
    @Test
    func mvtDataFromOtherProjectionDecodesIntoProjectionUnits() throws {
        let srid = Self.nextSrid()
        #expect(Projection.register(Self.scaledDegrees(srid: srid)))
        let projection = try #require(Projection(srid: srid))

        // Tile 1/1/1 covers longitude (0, 180) and latitude (-85.05, 0);
        // (30, 90) is inside.
        var tile4326 = try VectorTile(x: 1, y: 1, z: 1, projection: .epsg4326)
        tile4326.setFeatures([
            Feature(Point(Coordinate3D(latitude: -30.0, longitude: 90.0))),
        ], for: "layer")
        let data = try #require(tile4326.mvtData())

        let decoded = try VectorTile(mvtData: data, x: 1, y: 1, z: 1, projection: projection)
        let point = try #require(decoded.layers["layer"]?.features.first?.geometry as? Point)
        #expect(point.coordinate.projection.srid == srid)
        // The decoded coordinate is the same geographic location expressed
        // in the custom projection: scaled degrees (~1000× the 4326 values).
        #expect(abs(point.coordinate.latitude - -30_000.0) < 21.0)
        #expect(abs(point.coordinate.longitude - 90_000.0) < 44.0)
    }

}
