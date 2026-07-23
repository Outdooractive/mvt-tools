import Foundation
import GISTools
@testable import MVTTools
import struct GISTools.Polygon
import Testing

/// Regression tests for the MLT encoder's polygon ring-closure handling.
///
/// The MLT binary format omits the closing vertex from polygon rings; the
/// decoder re-adds it when reading.  Storing the closing vertex inflates every
/// ring size by 1 and shifts all subsequent cumulative ring offsets, which
/// corrupts polygon geometry for consumers like maplibre-gl-js.
///
/// These tests verify that:
/// - Closed polygon rings round-trip correctly (encode → decode).
/// - Multiple polygons in a single layer do not corrupt each other's offsets.
/// - MultiLineString parts (open lines) are NOT stripped.
/// - All four projections (EPSG:4326, EPSG:3857, EPSG:4978, noSRID) behave
///   correctly.
struct MLTEncoderRingClosureTests {

    // MARK: - Helpers

    /// Encode `features` into a single MLT layer, decode it back, and return the
    /// decoded features.
    private func roundtrip(
        _ features: [Feature],
        projection: Projection,
        x: Int = 0,
        y: Int = 0,
        z: Int = 0
    ) throws -> [Feature] {
        let data = try #require(MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: features, boundingBox: nil)],
            x: x, y: y, z: z, projection: projection))
        let decoded = try MLTDecoder.decode(
            from: data, x: x, y: y, z: z, projection: projection)
        return try #require(decoded["test"]?.features)
    }

    /// A simple closed square ring in tile-extent coordinates.
    private var closedSquare: [Coordinate3D] {
        [
            Coordinate3D(x: 100.0, y: 100.0, projection: .noSRID),
            Coordinate3D(x: 500.0, y: 100.0, projection: .noSRID),
            Coordinate3D(x: 500.0, y: 500.0, projection: .noSRID),
            Coordinate3D(x: 100.0, y: 500.0, projection: .noSRID),
            Coordinate3D(x: 100.0, y: 100.0, projection: .noSRID),
        ]
    }

    // MARK: - Polygon ring closure

    @Test
    func polygonRingIsStoredWithoutClosingVertex() throws {
        // A closed ring with 5 vertices (4 unique + closing) must round-trip
        // back to 5 vertices: the encoder strips the closing vertex, the decoder
        // re-adds it.
        let poly = try #require(Polygon([closedSquare]))
        let feature = Feature(poly, id: .int(1))

        let decoded = try roundtrip([feature], projection: .noSRID)
        let result = try #require(decoded.first?.geometry as? Polygon)
        #expect(result.rings.count == 1)
        #expect(result.rings[0].coordinates.count == closedSquare.count)
        #expect(result.rings[0].coordinates.first == result.rings[0].coordinates.last)
    }

    @Test
    func polygonWithHoleRoundtripsCorrectly() throws {
        let outer = closedSquare
        let inner: [Coordinate3D] = [
            Coordinate3D(x: 200.0, y: 200.0, projection: .noSRID),
            Coordinate3D(x: 400.0, y: 200.0, projection: .noSRID),
            Coordinate3D(x: 400.0, y: 400.0, projection: .noSRID),
            Coordinate3D(x: 200.0, y: 400.0, projection: .noSRID),
            Coordinate3D(x: 200.0, y: 200.0, projection: .noSRID),
        ]
        let poly = try #require(Polygon([outer, inner]))
        let feature = Feature(poly, id: .int(1))

        let decoded = try roundtrip([feature], projection: .noSRID)
        let result = try #require(decoded.first?.geometry as? Polygon)
        #expect(result.rings.count == 2)
        #expect(result.rings[0].coordinates.count == outer.count)
        #expect(result.rings[1].coordinates.count == inner.count)
        #expect(result.rings[0].coordinates.first == result.rings[0].coordinates.last)
        #expect(result.rings[1].coordinates.first == result.rings[1].coordinates.last)
    }

    // MARK: - Multiple polygons (offset corruption regression)

    @Test
    func multiplePolygonsDoNotCorruptOffsets() throws {
        // This is the core regression: with the closing-vertex bug, the
        // cumulative ring offsets drift, so later polygons read vertices from
        // the wrong position.  Encode several polygons with different vertex
        // counts and verify each decodes with the correct ring.
        let ring1 = closedSquare // 5 verts (4 unique + closing)
        let ring2: [Coordinate3D] = [
            Coordinate3D(x: 600.0, y: 600.0, projection: .noSRID),
            Coordinate3D(x: 900.0, y: 600.0, projection: .noSRID),
            Coordinate3D(x: 900.0, y: 900.0, projection: .noSRID),
            Coordinate3D(x: 600.0, y: 900.0, projection: .noSRID),
            Coordinate3D(x: 600.0, y: 600.0, projection: .noSRID),
        ]
        let ring3: [Coordinate3D] = [
            Coordinate3D(x: 1000.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 2000.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 2000.0, y: 2000.0, projection: .noSRID),
            Coordinate3D(x: 1500.0, y: 2500.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 2000.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 1000.0, projection: .noSRID),
        ]

        let features = [
            Feature(try #require(Polygon([ring1])), id: .int(1)),
            Feature(try #require(Polygon([ring2])), id: .int(2)),
            Feature(try #require(Polygon([ring3])), id: .int(3)),
        ]

        let decoded = try roundtrip(features, projection: .noSRID)
        #expect(decoded.count == 3)

        let p1 = try #require(decoded[0].geometry as? Polygon)
        let p2 = try #require(decoded[1].geometry as? Polygon)
        let p3 = try #require(decoded[2].geometry as? Polygon)

        #expect(p1.rings[0].coordinates.count == ring1.count)
        #expect(p2.rings[0].coordinates.count == ring2.count)
        #expect(p3.rings[0].coordinates.count == ring3.count)

        // Verify the actual vertex positions (not just counts) to catch
        // offset drift that maps vertices to wrong rings.
        for (a, b) in zip(p1.rings[0].coordinates, ring1) {
            #expect(abs(a.x - b.x) < 1.0)
            #expect(abs(a.y - b.y) < 1.0)
        }
        for (a, b) in zip(p2.rings[0].coordinates, ring2) {
            #expect(abs(a.x - b.x) < 1.0)
            #expect(abs(a.y - b.y) < 1.0)
        }
        for (a, b) in zip(p3.rings[0].coordinates, ring3) {
            #expect(abs(a.x - b.x) < 1.0)
            #expect(abs(a.y - b.y) < 1.0)
        }
    }

    // MARK: - MultiPolygon

    @Test
    func multiPolygonWithMultipleRingsRoundtripsCorrectly() throws {
        let poly1 = try #require(Polygon([closedSquare]))
        let poly2Ring: [Coordinate3D] = [
            Coordinate3D(x: 1000.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 3000.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 3000.0, y: 3000.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 3000.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 1000.0, projection: .noSRID),
        ]
        let poly2Hole: [Coordinate3D] = [
            Coordinate3D(x: 1500.0, y: 1500.0, projection: .noSRID),
            Coordinate3D(x: 2500.0, y: 1500.0, projection: .noSRID),
            Coordinate3D(x: 2500.0, y: 2500.0, projection: .noSRID),
            Coordinate3D(x: 1500.0, y: 2500.0, projection: .noSRID),
            Coordinate3D(x: 1500.0, y: 1500.0, projection: .noSRID),
        ]
        let poly2 = try #require(Polygon([poly2Ring, poly2Hole]))
        let mpoly = try #require(MultiPolygon([poly1, poly2]))
        let feature = Feature(mpoly, id: .int(1))

        let decoded = try roundtrip([feature], projection: .noSRID)
        let result = try #require(decoded.first?.geometry as? MultiPolygon)
        #expect(result.coordinates.count == 2)
        #expect(result.coordinates[0].count == 1)
        #expect(result.coordinates[1].count == 2)
        #expect(result.coordinates[0][0].count == closedSquare.count)
        #expect(result.coordinates[1][0].count == poly2Ring.count)
        #expect(result.coordinates[1][1].count == poly2Hole.count)
    }

    // MARK: - MultiLineString must NOT be stripped

    @Test
    func multiLineStringPartsAreNotStripped() throws {
        // MultiLineString parts are open lines — the encoder must keep every
        // vertex, including a duplicated endpoint if present.
        let line1: [Coordinate3D] = [
            Coordinate3D(x: 100.0, y: 100.0, projection: .noSRID),
            Coordinate3D(x: 500.0, y: 100.0, projection: .noSRID),
            Coordinate3D(x: 500.0, y: 500.0, projection: .noSRID),
        ]
        let line2: [Coordinate3D] = [
            Coordinate3D(x: 600.0, y: 600.0, projection: .noSRID),
            Coordinate3D(x: 900.0, y: 600.0, projection: .noSRID),
        ]
        let mls = try #require(MultiLineString([line1, line2]))
        let feature = Feature(mls, id: .int(1))

        let decoded = try roundtrip([feature], projection: .noSRID)
        let result = try #require(decoded.first?.geometry as? MultiLineString)
        #expect(result.coordinates.count == 2)
        #expect(result.coordinates[0].count == line1.count)
        #expect(result.coordinates[1].count == line2.count)
    }

    // MARK: - All projections

    @Test
    func polygonRingClosureEpsg4326() throws {
        let ring = [
            Coordinate3D(latitude: 47.0, longitude: 10.0),
            Coordinate3D(latitude: 47.0, longitude: 11.0),
            Coordinate3D(latitude: 48.0, longitude: 11.0),
            Coordinate3D(latitude: 48.0, longitude: 10.0),
            Coordinate3D(latitude: 47.0, longitude: 10.0),
        ]
        let poly = try #require(Polygon([ring]))
        let feature = Feature(poly, id: .int(1))

        let decoded = try roundtrip([feature], projection: .epsg4326)
        let result = try #require(decoded.first?.geometry as? Polygon)
        #expect(result.rings.count == 1)
        #expect(result.rings[0].coordinates.count == ring.count)
        #expect(result.rings[0].coordinates.first == result.rings[0].coordinates.last)
    }

    @Test
    func polygonRingClosureEpsg3857() throws {
        let ring = [
            Coordinate3D(x: 1_000_000.0, y: 5_900_000.0, projection: .epsg3857),
            Coordinate3D(x: 1_200_000.0, y: 5_900_000.0, projection: .epsg3857),
            Coordinate3D(x: 1_200_000.0, y: 6_100_000.0, projection: .epsg3857),
            Coordinate3D(x: 1_000_000.0, y: 6_100_000.0, projection: .epsg3857),
            Coordinate3D(x: 1_000_000.0, y: 5_900_000.0, projection: .epsg3857),
        ]
        let poly = try #require(Polygon([ring]))
        let feature = Feature(poly, id: .int(1))

        let decoded = try roundtrip([feature], projection: .epsg3857)
        let result = try #require(decoded.first?.geometry as? Polygon)
        #expect(result.rings.count == 1)
        #expect(result.rings[0].coordinates.count == ring.count)
        #expect(result.rings[0].coordinates.first == result.rings[0].coordinates.last)
    }

    @Test
    func polygonRingClosureEpsg4978() throws {
        let ring = [
            Coordinate3D(x: 4_200_000.0, y: 600_000.0, z: 4_700_000.0, projection: .epsg4978),
            Coordinate3D(x: 4_300_000.0, y: 700_000.0, z: 4_700_000.0, projection: .epsg4978),
            Coordinate3D(x: 4_300_000.0, y: 700_000.0, z: 4_800_000.0, projection: .epsg4978),
            Coordinate3D(x: 4_200_000.0, y: 600_000.0, z: 4_800_000.0, projection: .epsg4978),
            Coordinate3D(x: 4_200_000.0, y: 600_000.0, z: 4_700_000.0, projection: .epsg4978),
        ]
        let poly = try #require(Polygon([ring]))
        let feature = Feature(poly, id: .int(1))

        let decoded = try roundtrip([feature], projection: .epsg4978)
        let result = try #require(decoded.first?.geometry as? Polygon)
        #expect(result.rings.count == 1)
        #expect(result.rings[0].coordinates.count == ring.count)
    }

    @Test
    func polygonRingClosureNoSRID() throws {
        let poly = try #require(Polygon([closedSquare]))
        let feature = Feature(poly, id: .int(1))

        let decoded = try roundtrip([feature], projection: .noSRID)
        let result = try #require(decoded.first?.geometry as? Polygon)
        #expect(result.rings.count == 1)
        #expect(result.rings[0].coordinates.count == closedSquare.count)
        #expect(result.rings[0].coordinates.first == result.rings[0].coordinates.last)
    }

    // MARK: - Already-open ring (no closing vertex)

    @Test
    func openRingIsAcceptedAsIs() throws {
        // A ring without a closing vertex (first != last) should be stored
        // unchanged — nothing to strip.  The decoder will close it.
        let openRing: [Coordinate3D] = [
            Coordinate3D(x: 100.0, y: 100.0, projection: .noSRID),
            Coordinate3D(x: 500.0, y: 100.0, projection: .noSRID),
            Coordinate3D(x: 500.0, y: 500.0, projection: .noSRID),
            Coordinate3D(x: 100.0, y: 500.0, projection: .noSRID),
        ]
        let poly = try #require(Polygon([openRing]))
        let feature = Feature(poly, id: .int(1))

        let decoded = try roundtrip([feature], projection: .noSRID)
        let result = try #require(decoded.first?.geometry as? Polygon)
        #expect(result.rings.count == 1)
        // Decoder re-closes the ring → 5 vertices
        #expect(result.rings[0].coordinates.count == openRing.count + 1)
        #expect(result.rings[0].coordinates.first == result.rings[0].coordinates.last)
    }

}