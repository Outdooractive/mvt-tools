#if EnableMVT
#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
import struct GISTools.Polygon
@testable import MVTTools
import Testing

struct MVTWindingTests {

    // MARK: - Helpers

    private static let mapTile = MapTile(x: 8661, y: 5722, z: 14)

    /// Returns a coordinate in `projection` for the given tile-local point.
    private static func coordinate(
        tileX: Int,
        tileY: Int,
        projection: Projection
    ) -> Coordinate3D {
        if projection.hasSRID {
            return Projections.forwardProjection(
                for: projection,
                x: mapTile.x,
                y: mapTile.y,
                z: mapTile.z,
                extent: VectorTile.ExportOptions.extent)(tileX, tileY)
        }
        return Coordinate3D(
            x: Double(tileX),
            y: Double(tileY),
            projection: .noSRID)
    }

    /// Builds a closed ring from tile-local points.
    private static func ring(
        _ points: [(x: Int, y: Int)],
        projection: Projection
    ) -> [Coordinate3D] {
        guard let first = points.first else { return [] }

        var coordinates = points.map {
            coordinate(tileX: $0.x, tileY: $0.y, projection: projection)
        }
        coordinates.append(
            coordinate(tileX: first.x, tileY: first.y, projection: projection))
        return coordinates
    }

    /// Builds a closed square. `clockwise == true` produces a ring that is
    /// clockwise in tile space, i.e. an MVT exterior ring.
    private static func square(
        minX: Int,
        minY: Int,
        size: Int,
        clockwise: Bool,
        projection: Projection
    ) -> [Coordinate3D] {
        let points = clockwise
            ? [
                (x: minX, y: minY),
                (x: minX + size, y: minY),
                (x: minX + size, y: minY + size),
                (x: minX, y: minY + size),
            ]
            : [
                (x: minX, y: minY),
                (x: minX, y: minY + size),
                (x: minX + size, y: minY + size),
                (x: minX + size, y: minY),
            ]
        return ring(points, projection: projection)
    }

    /// Calculates the signed area in tile coordinates. Positive values are
    /// MVT exterior rings, negative values are holes.
    private static func signedArea(_ ring: Ring) -> Double {
        let coordinates = ring.coordinates
        guard coordinates.count > 2 else { return 0.0 }

        var sum = 0.0
        for index in coordinates.indices {
            let current = coordinates[index]
            let next = coordinates[(index + 1) % coordinates.count]
            sum += current.x * next.y - next.x * current.y
        }
        return sum / 2.0
    }

    /// Encodes a geometry and decodes the raw MVT output in tile space.
    private static func encodeAndDecode(
        _ geometry: any GeoJsonGeometry,
        projection: Projection
    ) throws -> VectorTile {
        var tile = try VectorTile(
            x: mapTile.x,
            y: mapTile.y,
            z: mapTile.z,
            projection: projection)
        tile.setFeatures([Feature(geometry)], for: "test")

        let data = try #require(tile.mvtData(options: .init(
            bufferSize: .no,
            compression: .no,
            simplifyFeatures: .no)))
        return try VectorTile(
            mvtData: data,
            x: mapTile.x,
            y: mapTile.y,
            z: mapTile.z,
            projection: .noSRID)
    }

    // MARK: - Exterior rings

    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID])
    func exteriorRingWindingIsNormalizedInTileSpace(projection: Projection) throws {
        // Counter-clockwise in tile space is the wrong winding for an MVT
        // exterior ring. The encoder must reverse it, independent of the
        // source projection.
        let outer = MVTWindingTests.square(
            minX: 2000,
            minY: 2000,
            size: 100,
            clockwise: false,
            projection: projection)
        let polygon = try #require(Polygon([outer]))

        let decoded = try MVTWindingTests.encodeAndDecode(
            polygon,
            projection: projection)
        let decodedPolygon = try #require(
            decoded.features(for: "test").first?.geometry as? Polygon
        )

        #expect(MVTWindingTests.signedArea(decodedPolygon.rings[0]) > 0.0)
    }

    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID])
    func clockwiseExteriorRingIsNotReversed(projection: Projection) throws {
        let outer = MVTWindingTests.square(
            minX: 2000,
            minY: 2000,
            size: 100,
            clockwise: true,
            projection: projection)
        let polygon = try #require(Polygon([outer]))

        let decoded = try MVTWindingTests.encodeAndDecode(
            polygon,
            projection: projection)
        let decodedPolygon = try #require(
            decoded.features(for: "test").first?.geometry as? Polygon
        )
        let ring = decodedPolygon.rings[0]

        #expect(MVTWindingTests.signedArea(ring) > 0.0)

        // A correctly wound ring must keep its vertex order. The second
        // vertex distinguishes the original ring from a reversed one.
        #expect(abs(ring.coordinates[1].x - Double(2100)) < 1.0)
        #expect(abs(ring.coordinates[1].y - Double(2000)) < 1.0)
    }

    // MARK: - Holes

    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID])
    func holeRingWindingIsNormalizedInTileSpace(projection: Projection) throws {
        let outer = MVTWindingTests.square(
            minX: 2000,
            minY: 2000,
            size: 100,
            clockwise: true,
            projection: projection)
        // Clockwise in tile space is the wrong winding for a hole.
        let hole = MVTWindingTests.square(
            minX: 2030,
            minY: 2030,
            size: 40,
            clockwise: true,
            projection: projection)
        let polygon = try #require(Polygon([outer, hole]))

        let decoded = try MVTWindingTests.encodeAndDecode(
            polygon,
            projection: projection)
        let decodedPolygon = try #require(
            decoded.features(for: "test").first?.geometry as? Polygon
        )

        #expect(decodedPolygon.rings.count == 2)
        #expect(MVTWindingTests.signedArea(decodedPolygon.rings[0]) > 0.0)
        #expect(MVTWindingTests.signedArea(decodedPolygon.rings[1]) < 0.0)
    }

    // MARK: - Multi polygons

    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978, .noSRID])
    func multiPolygonExteriorsAreNormalizedInTileSpace(projection: Projection) throws {
        let first = MVTWindingTests.square(
            minX: 1900,
            minY: 1900,
            size: 80,
            clockwise: true,
            projection: projection)
        let second = MVTWindingTests.square(
            minX: 2100,
            minY: 2100,
            size: 80,
            clockwise: false,
            projection: projection)
        let firstPolygon = try #require(Polygon([first]))
        let secondPolygon = try #require(Polygon([second]))
        let multiPolygon = try #require(MultiPolygon([firstPolygon, secondPolygon]))

        let decoded = try MVTWindingTests.encodeAndDecode(
            multiPolygon,
            projection: projection)
        let decodedMultiPolygon = try #require(
            decoded.features(for: "test").first?.geometry as? MultiPolygon
        )

        #expect(decodedMultiPolygon.polygons.count == 2)
        #expect(decodedMultiPolygon.polygons.allSatisfy({
            MVTWindingTests.signedArea($0.rings[0]) > 0.0
        }))
    }

    // MARK: - Round trip into the source projection

    @Test(arguments: [Projection.epsg4326, .epsg3857, .epsg4978])
    func polygonWithHoleRoundTripsToSourceProjection(projection: Projection) throws {
        let outer = MVTWindingTests.square(
            minX: 2000,
            minY: 2000,
            size: 100,
            clockwise: true,
            projection: projection)
        let hole = MVTWindingTests.square(
            minX: 2030,
            minY: 2030,
            size: 40,
            clockwise: false,
            projection: projection)
        let polygon = try #require(Polygon([outer, hole]))

        var tile = try VectorTile(
            x: MVTWindingTests.mapTile.x,
            y: MVTWindingTests.mapTile.y,
            z: MVTWindingTests.mapTile.z,
            projection: projection)
        tile.setFeatures([Feature(polygon)], for: "test")

        let data = try #require(tile.mvtData(options: .init(
            bufferSize: .no,
            compression: .no,
            simplifyFeatures: .no)))
        let decoded = try VectorTile(
            mvtData: data,
            x: MVTWindingTests.mapTile.x,
            y: MVTWindingTests.mapTile.y,
            z: MVTWindingTests.mapTile.z,
            projection: projection)
        let decodedPolygon = try #require(
            decoded.features(for: "test").first?.geometry as? Polygon
        )

        #expect(decodedPolygon.rings.count == 2)
        #expect(decodedPolygon.rings[0].isClockwise)
        #expect(decodedPolygon.rings[1].isCounterClockwise)
    }

}
#endif
