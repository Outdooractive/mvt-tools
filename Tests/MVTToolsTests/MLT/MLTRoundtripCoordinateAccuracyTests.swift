import Foundation
import GISTools
@testable import MVTTools
import Testing

struct MLTRoundtripCoordinateAccuracyTests {

    /// Roundtrip `geom` through encode→decode at z=0 with the given projection.
    private func roundtripCoord(
        _ geom: GeoJsonGeometry,
        projection: Projection,
        x: Int, y: Int, z: Int
    ) throws -> GeoJsonGeometry {
        let f = Feature(geom)
        let data = try #require(MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [f], boundingBox: nil)],
            x: x, y: y, z: z, projection: projection))
        let decoded = try MLTDecoder.decode(
            from: data, x: x, y: y, z: z, projection: projection)
        return try #require(decoded["test"]?.features.first?.geometry)
    }

    /// Check a roundtrip for all geometry types (Point, MultiPoint, LineString, Polygon).
    private func checkBasicGeometries(
        projection: Projection,
        x: Int, y: Int, z: Int,
        coords: [Coordinate3D], tolerance: Double
    ) async throws {
        // Point
        let pt = try roundtripCoord(Point(coords[0]), projection: projection, x: x, y: y, z: z)
        let p = try #require(pt as? Point)
        #expect(abs(p.coordinate.x - coords[0].x) < tolerance)
        #expect(abs(p.coordinate.y - coords[0].y) < tolerance)

        // MultiPoint
        let mp = try #require(MultiPoint(coords))
        let mpGeom = try roundtripCoord(mp, projection: projection, x: x, y: y, z: z)
        let mpr = try #require(mpGeom as? MultiPoint)
        #expect(mpr.coordinates.count == coords.count)
        for (a, b) in zip(mpr.coordinates, coords) {
            #expect(abs(a.x - b.x) < tolerance)
            #expect(abs(a.y - b.y) < tolerance)
        }

        // LineString
        let ls = try #require(LineString(coords))
        let lsGeom = try roundtripCoord(ls, projection: projection, x: x, y: y, z: z)
        let lsr = try #require(lsGeom as? LineString)
        #expect(lsr.coordinates.count == coords.count)
        for (a, b) in zip(lsr.coordinates, coords) {
            #expect(abs(a.x - b.x) < tolerance)
            #expect(abs(a.y - b.y) < tolerance)
        }

        // Polygon (closed ring)
        let ring = coords + [coords[0]]
        let poly = try #require(Polygon([ring]))
        let poGeom = try roundtripCoord(poly, projection: projection, x: x, y: y, z: z)
        let por = try #require(poGeom as? Polygon)
        #expect(por.rings.count == 1)
        #expect(por.rings[0].coordinates.count == ring.count)
        for (a, b) in zip(por.rings[0].coordinates, ring) {
            #expect(abs(a.x - b.x) < tolerance)
            #expect(abs(a.y - b.y) < tolerance)
        }
    }

    // MARK: - Coordinate accuracy across projections

    @Test
    func coordinateAccuracyNoSRID() async throws {
        try await checkBasicGeometries(
            projection: .noSRID, x: 0, y: 0, z: 0,
            coords: [
                Coordinate3D(x: 100.0, y: 200.0, projection: .noSRID),
                Coordinate3D(x: 1500.0, y: 800.0, projection: .noSRID),
                Coordinate3D(x: 3000.0, y: 3500.0, projection: .noSRID),
            ],
            tolerance: 1.0)
    }

    @Test
    func coordinateAccuracyEpsg4326() async throws {
        try await checkBasicGeometries(
            projection: .epsg4326, x: 0, y: 0, z: 0,
            coords: [
                Coordinate3D(latitude: 48.8566, longitude: 2.3522),
                Coordinate3D(latitude: 52.5200, longitude: 13.4050),
                Coordinate3D(latitude: 47.3769, longitude: 8.5417),
            ],
            tolerance: 0.1)
    }

    @Test
    func coordinateAccuracyEpsg3857() async throws {
        let tile = (z: 0, x: 0, y: 0)
        let coords = [
            Coordinate3D(x: 600_000.0, y: 5_800_000.0, projection: .epsg3857),
            Coordinate3D(x: 1_500_000.0, y: 6_900_000.0, projection: .epsg3857),
            Coordinate3D(x: 950_000.0, y: 6_000_000.0, projection: .epsg3857),
        ]
        try await checkBasicGeometries(
            projection: .epsg3857, x: tile.x, y: tile.y, z: tile.z,
            coords: coords, tolerance: 15_000.0)
    }

    @Test
    func coordinateAccuracyEpsg4978() async throws {
        let tile = (z: 0, x: 0, y: 0)
        let coords = [
            Coordinate3D(x: 4_200_000.0, y: 600_000.0, z: 4_700_000.0, projection: .epsg4978),
            Coordinate3D(x: 4_000_000.0, y: 900_000.0, z: 4_800_000.0, projection: .epsg4978),
            Coordinate3D(x: 4_400_000.0, y: 700_000.0, z: 4_600_000.0, projection: .epsg4978),
        ]
        try await checkBasicGeometries(
            projection: .epsg4978, x: tile.x, y: tile.y, z: tile.z,
            coords: coords, tolerance: 50_000.0)
    }

}
