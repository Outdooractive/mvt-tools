#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
@testable import MVTTools
import Synchronization
import Testing

/// Tests for the projection-agnostic tile coordinate handling introduced
/// with gis-tools 3.0.0: MVT/MLT encode/decode, tile bounding boxes, query
/// bounding boxes and export clipping must work for *any* registered
/// projection (built-in EPSG codes as well as runtime-registered
/// ``CustomProjection`` values).
struct ProjectionHandlingTests {

    // MARK: - Custom projection fixture

    /// SRID pool for this suite: unique per test call, since registration is
    /// add-only and process-global.
    private static let sridCounter = Mutex(902_500)

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

    // MARK: - Tile/layer bounding boxes

    /// Tests the tile bounding box for all built-in projections.
    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978])
    func tileBoundingBoxBuiltIns(projection: Projection) throws {
        let tile = try VectorTile(x: 8716, y: 8015, z: 14, projection: projection)
        let boundingBox = tile.boundingBox

        #expect(boundingBox.projection == projection)
        #expect(boundingBox.southWest.latitude < boundingBox.northEast.latitude)
        #expect(boundingBox.southWest.longitude < boundingBox.northEast.longitude)
    }

    /// Tests the tile bounding box for a runtime-registered custom
    /// projection: the box must be in the custom projection's units.
    @Test
    func tileBoundingBoxCustomProjection() throws {
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

    /// Tests that the noSRID tile bounding box spans the raw extent grid.
    @Test
    func tileBoundingBoxNoSRID() throws {
        let tile = try VectorTile(x: 1, y: 1, z: 1, projection: .noSRID)
        let boundingBox = tile.boundingBox

        #expect(boundingBox.projection == .noSRID)
        #expect(boundingBox.southWest.x == 0.0)
        #expect(boundingBox.southWest.y == 0.0)
        #expect(boundingBox.northEast.x == Double(VectorTile.ExportOptions.extent))
        #expect(boundingBox.northEast.y == Double(VectorTile.ExportOptions.extent))
    }

    // MARK: - MVT round trips per projection

    /// MVT round trip for every built-in projection: a known geographic
    /// anchor point inside tile 1/1/1 (latitude -40, longitude 90) must
    /// decode to (approximately) the same coordinate in the tile's
    /// projection.
    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978])
    func mvtRoundTripBuiltIns(projection: Projection) throws {
        let anchor = Coordinate3D(latitude: -40.0, longitude: 90.0).projected(to: projection)

        var tile = try VectorTile(x: 1, y: 1, z: 1, projection: projection)
        tile.setFeatures([Feature(Point(anchor))], for: "layer")
        let data = try #require(tile.mvtData())
        #expect(!data.isEmpty)

        let decoded = try VectorTile(mvtData: data, x: 1, y: 1, z: 1, projection: projection)
        let decodedPoint = try #require(decoded.features(for: "layer").first?.geometry as? Point)

        // The tile extent is 4096 units; one cell spans ~1/4096 of the tile
        // (0.044° for EPSG:4326, ~4_900 units for EPSG:3857/4978). The
        // tolerance is one cell with safety margin.
        let tolerance: Double = if projection == .epsg4326 {
            0.1
        }
        else {
            10_000.0
        }
        #expect(decodedPoint.coordinate.projection == projection)
        #expect(abs(decodedPoint.coordinate.latitude - anchor.latitude) < tolerance)
        #expect(abs(decodedPoint.coordinate.longitude - anchor.longitude) < tolerance)
    }

    /// MVT round trip in a custom registered projection.
    @Test
    func mvtRoundTripCustomProjection() throws {
        let srid = Self.nextSrid()
        #expect(Projection.register(Self.scaledDegrees(srid: srid)))
        let projection = try #require(Projection(srid: srid))

        var tile = try VectorTile(x: 1, y: 1, z: 1, projection: projection)
        let center = tile.boundingBox.center
        #expect(center.projection.srid == srid)

        tile.setFeatures([Feature(Point(center))], for: "layer")
        let data = try #require(tile.mvtData())

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

    // MARK: - Encoder clipping

    /// Tests that the encoder's clip box is computed in the tile's own
    /// projection for the built-ins: features inside the tile survive, a
    /// feature in another tile (no wraparound between the quadrants) is
    /// clipped away.
    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978])
    func encoderClipBoxBuiltIns(projection: Projection) throws {
        var tile = try VectorTile(x: 1, y: 1, z: 1, projection: projection)
        // Inside tile 1/1/1 (longitude 0 ... 180, latitude -85 ... 0):
        // latitude -40, longitude 90.
        let inside = Feature(
            Point(Coordinate3D(latitude: -40.0, longitude: 90.0).projected(to: projection)),
            id: .int(1))
        // In tile 1/0/1 (longitude -180 ... 0, latitude -85 ... 0):
        // latitude -40, longitude -90 — not reachable by wraparound from
        // tile 1/1/1's bounds.
        let otherTile = Feature(
            Point(Coordinate3D(latitude: -40.0, longitude: -90.0).projected(to: projection)),
            id: .int(2))

        tile.setFeatures([inside, otherTile], for: "layer")
        let data = try #require(tile.mvtData())

        let decoded = try VectorTile(mvtData: data, x: 1, y: 1, z: 1, projection: projection)
        let ids = decoded.features(for: "layer").compactMap(\.id)
        #expect(ids == [.int(1)])
    }

    /// Tests that the encoder clip box works for a custom registered
    /// projection (clipping against the custom projection's tile bounds).
    @Test
    func encoderClipBoxCustomProjection() throws {
        let srid = Self.nextSrid()
        #expect(Projection.register(Self.scaledDegrees(srid: srid)))
        let projection = try #require(Projection(srid: srid))

        var tile = try VectorTile(x: 1, y: 1, z: 1, projection: projection)
        let center = tile.boundingBox.center

        let inside = Feature(Point(center), id: .int(1))
        // x = +90_000 is outside tile 1/1/1's x range (0 ... 180_000).
        let farAway = Feature(
            Point(Coordinate3D(x: center.longitude + 90_000.0, y: center.latitude, projection: projection)),
            id: .int(2))

        tile.setFeatures([inside, farAway], for: "layer")
        let data = try #require(tile.mvtData())

        let decoded = try VectorTile(mvtData: data, x: 1, y: 1, z: 1, projection: projection)
        let ids = decoded.features(for: "layer").compactMap(\.id)
        #expect(ids == [.int(1)])
    }

    // MARK: - Export options clipping

    /// Tests that export clipping (GeoJSON export with buffer options)
    /// works for a custom registered projection: features outside the
    /// buffered tile bounds are clipped away.
    @Test
    func exportClipBoxCustomProjection() throws {
        let srid = Self.nextSrid()
        #expect(Projection.register(Self.scaledDegrees(srid: srid)))
        let projection = try #require(Projection(srid: srid))

        var tile = try VectorTile(x: 1, y: 1, z: 1, projection: projection)
        let center = tile.boundingBox.center

        let inside = Feature(Point(center), id: .int(1))
        let farAway = Feature(
            Point(Coordinate3D(x: center.longitude + 90_000.0, y: center.latitude, projection: projection)),
            id: .int(2))

        tile.setFeatures([inside, farAway], for: "layer")

        let geoJsonData = try #require(tile.toGeoJson(options: .init(bufferSize: .extent(512))))
        let fc = try #require(FeatureCollection(jsonData: geoJsonData))
        #expect(fc.features.count == 1)
        #expect(fc.features[0].id == .int(1))
    }

    // MARK: - Query bounding boxes

    /// Tests the query bounding box for a custom registered projection:
    /// the tolerance is applied in the projection's own units (meters for
    /// planar projections).
    @Test
    func queryBoundingBoxCustomProjection() throws {
        let srid = Self.nextSrid()
        #expect(Projection.register(Self.scaledDegrees(srid: srid)))
        let projection = try #require(Projection(srid: srid))

        let coordinate = Coordinate3D(x: 1_000.0, y: 2_000.0, projection: projection)
        let boundingBox = VectorTile.queryBoundingBox(at: coordinate, tolerance: 100.0, projection: projection)

        #expect(boundingBox.projection.srid == srid)
        #expect(abs(boundingBox.southWest.longitude - 900.0) < 0.000001)
        #expect(abs(boundingBox.northEast.longitude - 1_100.0) < 0.000001)
        #expect(abs(boundingBox.southWest.latitude - 1_900.0) < 0.000001)
        #expect(abs(boundingBox.northEast.latitude - 2_100.0) < 0.000001)
    }

    /// Tests a spatial query against a tile in a custom registered
    /// projection: only features within the tolerance match.
    @Test
    func queryCustomProjection() throws {
        let srid = Self.nextSrid()
        #expect(Projection.register(Self.scaledDegrees(srid: srid)))
        let projection = try #require(Projection(srid: srid))

        var tile = try VectorTile(x: 0, y: 0, z: 0, projection: projection)
        // Coordinates in scaled degrees: (10_000, 20_000) and (10_500, 20_000)
        // are 500 units apart (~0.5°).
        let near = Feature(
            Point(Coordinate3D(x: 10_000.0, y: 20_000.0, projection: projection)),
            id: .int(1))
        let far = Feature(
            Point(Coordinate3D(x: 10_500.0, y: 20_000.0, projection: projection)),
            id: .int(2))
        tile.setFeatures([near, far], for: "layer")

        // Tolerance 100 (planar units) matches only the first point.
        let results = tile.query(
            at: Coordinate3D(x: 10_000.0, y: 20_000.0, projection: projection),
            tolerance: 100.0)
        #expect(results.count == 1)
        #expect(results[0].feature.id == .int(1))

        // Tolerance 600 (planar units) matches both points.
        let widerResults = tile.query(
            at: Coordinate3D(x: 10_000.0, y: 20_000.0, projection: projection),
            tolerance: 600.0)
        #expect(widerResults.count == 2)
    }

    /// Tests that indexed (R-Tree) queries return the same results as
    /// linear scans in a custom registered projection.
    @Test
    func queryCustomProjectionWithIndex() throws {
        let srid = Self.nextSrid()
        #expect(Projection.register(Self.scaledDegrees(srid: srid)))
        let projection = try #require(Projection(srid: srid))

        var tile = try VectorTile(x: 0, y: 0, z: 0, projection: projection)
        let near = Feature(
            Point(Coordinate3D(x: 10_000.0, y: 20_000.0, projection: projection)),
            id: .int(1))
        let far = Feature(
            Point(Coordinate3D(x: 10_500.0, y: 20_000.0, projection: projection)),
            id: .int(2))
        tile.setFeatures([near, far], for: "layer")
        tile.createIndex(sortOption: .hilbert)
        #expect(tile.isIndexed)

        let results = tile.query(
            at: Coordinate3D(x: 10_000.0, y: 20_000.0, projection: projection),
            tolerance: 100.0)
        #expect(results.count == 1)
        #expect(results[0].feature.id == .int(1))
    }

    // MARK: - Overzoom

    /// Tests that overzoom/rezoom preserves the source projection and
    /// features for a custom registered projection.
    @Test
    func rezoomCustomProjection() throws {
        let srid = Self.nextSrid()
        #expect(Projection.register(Self.scaledDegrees(srid: srid)))
        let projection = try #require(Projection(srid: srid))

        var source = try VectorTile(x: 1, y: 1, z: 1, projection: projection)
        source.setFeatures([
            Feature(Point(Coordinate3D(x: 10_000.0, y: -20_000.0, projection: projection)), id: .int(1)),
        ], for: "layer")

        let result = try #require(source.rezoom(toTargetX: 2, targetY: 2, targetZ: 2))
        #expect(result.projection.srid == srid)
        #expect(result.features(for: "layer").count == 1)

        let point = try #require(result.features(for: "layer").first?.geometry as? Point)
        #expect(point.coordinate.projection.srid == srid)
        // Tile 1/1/1 covers longitude (0, 180_000) and latitude
        // (-85_051.129, 0); rezoomed to 2/2/2 (the north-west quarter of
        // tile 1/1/1: longitude (0, 90_000), latitude (-42_525.56, 0)),
        // the point (10_000, -20_000) is still inside.
        #expect(abs(point.coordinate.longitude - 10_000.0) < 44.0)
        #expect(abs(point.coordinate.latitude - -20_000.0) < 21.0)
    }

    // MARK: - Merge

    /// Tests that merging tiles in a custom projection keeps the
    /// projection and the features.
    @Test
    func mergeCustomProjection() throws {
        let srid = Self.nextSrid()
        #expect(Projection.register(Self.scaledDegrees(srid: srid)))
        let projection = try #require(Projection(srid: srid))

        var tile1 = try VectorTile(x: 0, y: 0, z: 0, projection: projection)
        tile1.setFeatures([
            Feature(Point(Coordinate3D(x: 1_000.0, y: 2_000.0, projection: projection)), id: .int(1)),
        ], for: "layer")

        var tile2 = try VectorTile(x: 0, y: 0, z: 0, projection: projection)
        tile2.setFeatures([
            Feature(Point(Coordinate3D(x: 3_000.0, y: 4_000.0, projection: projection)), id: .int(2)),
        ], for: "layer")

        tile1.merge(tile2)
        #expect(tile1.projection.srid == srid)
        #expect(tile1.features(for: "layer").count == 2)

        let ids = Set(tile1.features(for: "layer").compactMap(\.id))
        #expect(ids == [.int(1), .int(2)])
    }

    // MARK: - Merge

    /// Tests that merging tiles with different projections warns but keeps
    /// merging, projecting the foreign features into the tile's projection.
    @Test
    func mergeWithMismatchedProjectionProjectsFeatures() throws {
        let srid = Self.nextSrid()
        #expect(Projection.register(Self.scaledDegrees(srid: srid)))
        let projection = try #require(Projection(srid: srid))

        var tile = try VectorTile(x: 0, y: 0, z: 0, projection: projection)
        tile.setFeatures([
            Feature(Point(Coordinate3D(x: 1_000.0, y: 2_000.0, projection: projection)), id: .int(1)),
        ], for: "layer")

        var other = try VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)
        other.setFeatures([
            Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(2)),
        ], for: "layer")

        let merged = tile.merge(other)
        #expect(merged)
        #expect(tile.projection.srid == srid)
        #expect(tile.features(for: "layer").count == 2)

        // The foreign 4326 point is projected into the custom projection.
        let byId = Dictionary(uniqueKeysWithValues: tile.features(for: "layer").map({ ($0.id!, $0) }))
        let projectedPoint = try #require(byId[.int(2)]?.geometry as? Point)
        #expect(projectedPoint.coordinate.projection.srid == srid)
        #expect(abs(projectedPoint.coordinate.latitude - 10_000.0) < 0.000001)
        #expect(abs(projectedPoint.coordinate.longitude - 20_000.0) < 0.000001)
    }

}
