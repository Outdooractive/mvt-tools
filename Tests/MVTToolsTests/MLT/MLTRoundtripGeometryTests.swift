import Foundation
import GISTools
@testable import MVTTools
import struct GISTools.Polygon
import Testing

struct MLTRoundtripGeometryTests {

    // MARK: - Geometry round-trips

    @Test
    func encodePointAndLine() throws {
        let point = Feature(Point(Coordinate3D(latitude: 5.0, longitude: 10.0)), id: .int(1))
        let line = Feature(MultiLineString([[
            Coordinate3D(latitude: 1.0, longitude: 2.0),
            Coordinate3D(latitude: 3.0, longitude: 4.0),
        ]])!, id: .int(2))
        let poly = Feature(Polygon([[
            Coordinate3D(latitude: 0.0, longitude: 0.0),
            Coordinate3D(latitude: 10.0, longitude: 0.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
            Coordinate3D(latitude: 0.0, longitude: 10.0),
            Coordinate3D(latitude: 0.0, longitude: 0.0),
        ]])!, id: .int(3))

        guard let data = MLTEncoder.encode(
            layers: [
                "points": VectorTile.LayerContainer(features: [point], boundingBox: nil),
                "lines": VectorTile.LayerContainer(features: [line], boundingBox: nil),
                "polygons": VectorTile.LayerContainer(features: [poly], boundingBox: nil),
            ],
            x: 0, y: 0, z: 0, projection: .epsg4326)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .epsg4326)
        #expect(decoded.keys.count == 3)
        #expect(decoded["points"]?.features.count == 1)
        #expect(decoded["lines"]?.features.count == 1)
        #expect(decoded["polygons"]?.features.count == 1)
    }

    @Test
    func multiLineStringRoundtrip() throws {
        let lines = MultiLineString([[
            Coordinate3D(latitude: 1.0, longitude: 2.0),
            Coordinate3D(latitude: 3.0, longitude: 4.0),
        ], [
            Coordinate3D(latitude: 5.0, longitude: 6.0),
            Coordinate3D(latitude: 7.0, longitude: 8.0),
        ]])!
        let feature = Feature(lines, id: .int(1))
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let result = try #require(decoded["test"]?.features.first?.geometry as? MultiLineString)
        #expect(result.coordinates.count == 2)
        #expect(result.coordinates[0].count == 2)
        #expect(result.coordinates[1].count == 2)
        #expect(result.coordinates[0][0].x == 2.0)
        #expect(result.coordinates[0][1].x == 4.0)
        #expect(result.coordinates[1][0].x == 6.0)
        #expect(result.coordinates[1][1].x == 8.0)
    }

    @Test
    func polygonRoundtrip() throws {
        let ring = [
            Coordinate3D(x: 100.0, y: 100.0, projection: .noSRID),
            Coordinate3D(x: 500.0, y: 100.0, projection: .noSRID),
            Coordinate3D(x: 300.0, y: 500.0, projection: .noSRID),
            Coordinate3D(x: 100.0, y: 100.0, projection: .noSRID),
        ]
        let poly = try #require(Polygon([ring]))
        let feature = Feature(poly, id: .int(1))
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let result = try #require(decoded["test"]?.features.first?.geometry as? Polygon)
        #expect(result.rings.count == 1)
        #expect(result.rings[0].coordinates.count == ring.count)
        for (a, b) in zip(result.rings[0].coordinates, ring) {
            #expect(abs(a.x - b.x) < 1.0)
            #expect(abs(a.y - b.y) < 1.0)
        }
    }

    @Test
    func polygonWithHoleRoundtrip() throws {
        let outer: [Coordinate3D] = [
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
        ]
        let inner: [Coordinate3D] = [
            Coordinate3D(x: 200.0, y: 200.0, projection: .noSRID),
            Coordinate3D(x: 800.0, y: 200.0, projection: .noSRID),
            Coordinate3D(x: 800.0, y: 800.0, projection: .noSRID),
            Coordinate3D(x: 200.0, y: 800.0, projection: .noSRID),
            Coordinate3D(x: 200.0, y: 200.0, projection: .noSRID),
        ]
        let poly = try #require(Polygon([outer, inner]))
        let feature = Feature(poly, id: .int(1))
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let result = try #require(decoded["test"]?.features.first?.geometry as? Polygon)
        #expect(result.rings.count == 2)
        #expect(result.rings[0].coordinates.count == outer.count)
        #expect(result.rings[1].coordinates.count == inner.count)
    }

    @Test
    func multiPolygonRoundtrip() throws {
        let poly1 = try #require(Polygon([[
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 500.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 250.0, y: 500.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
        ]]))
        let poly2 = try #require(Polygon([[
            Coordinate3D(x: 600.0, y: 600.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 600.0, projection: .noSRID),
            Coordinate3D(x: 800.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 600.0, y: 600.0, projection: .noSRID),
        ]]))
        let mpoly = try #require(MultiPolygon([poly1, poly2]))
        let feature = Feature(mpoly, id: .int(1))
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let result = try #require(decoded["test"]?.features.first?.geometry as? MultiPolygon)
        #expect(result.coordinates.count == 2)
        #expect(result.coordinates[0].count == 1)
        #expect(result.coordinates[1].count == 1)
        #expect(result.coordinates[0][0].count == 4)
        #expect(result.coordinates[1][0].count == 4)
    }

    @Test
    func multiPointRoundtrip() throws {
        let coords = [
            Coordinate3D(latitude: 1.0, longitude: 2.0),
            Coordinate3D(latitude: 3.0, longitude: 4.0),
        ]
        let mp = try #require(MultiPoint(coords))
        let feature = Feature(mp, id: .int(1))

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)

        #expect(feat.geometry is MultiPoint)
    }

    // Regression: a MultiPolygon with a single polygon containing many rings
    // and vertices that fall OUTSIDE the tile extent (negative coords, as
    // happens with buffered PostGIS tiles). The C++ MLT encoder must preserve
    // the ring→vertex mapping so that decoding returns each ring's original
    // vertices in order. This validates the workaround that disables the
    // Morton/Hilbert dictionary vertex encoding in Bridge.cpp.
    @Test
    func multiPolygonManyRingsWithNegativeCoordsRoundtrip() throws {
        // One polygon with 67 rings; ring0 has 5 vertices starting at (-405, 2730).
        // Holes use smaller rings. Coordinates deliberately include negative
        // values (buffer zone) to exercise the space-filling-curve path.
        var rings: [[Coordinate3D]] = []
        // Ring 0 (exterior): a large rectangle spanning the buffer + tile.
        // Winding is chosen so that `normalizePolygonTilespace` does NOT reverse
        // it (negative tile-space area), so expectedRing0 == ring0.
        let ring0 = [
            Coordinate3D(x: -405.0, y: -400.0, projection: .noSRID),
            Coordinate3D(x: 4502.0, y: -400.0, projection: .noSRID),
            Coordinate3D(x: 4502.0, y: 2730.0, projection: .noSRID),
            Coordinate3D(x: -405.0, y: 2730.0, projection: .noSRID),
            Coordinate3D(x: -405.0, y: -400.0, projection: .noSRID),
        ]
        rings.append(ring0)
        // 66 holes, each a small triangle in-tile to vary winding/offsets.
        for i in 0 ..< 66 {
            let base = Double(i * 60) + 10
            rings.append([
                Coordinate3D(x: base, y: base, projection: .noSRID),
                Coordinate3D(x: base + 50, y: base, projection: .noSRID),
                Coordinate3D(x: base + 25, y: base + 50, projection: .noSRID),
                Coordinate3D(x: base, y: base, projection: .noSRID),
            ])
        }
        let poly = try #require(Polygon(rings))
        let mpoly = try #require(MultiPolygon([poly]))
        // Add MANY features with VARIED geometries in the same layer, so the
        // Morton/Hilbert dictionary is built across heterogeneous vertices
        // (this mirrors real tiles like `oceans` where features have different
        // ring counts/sizes and is what triggers the reorder bug).
        var features: [Feature] = []
        features.append(Feature(mpoly, id: .int(0)))
        // Add small varied polygons with different vertex ranges.
        for i in 1 ..< 25 {
            let off = Double(i) * 100.0
            let small = try #require(Polygon([[
                Coordinate3D(x: off, y: off, projection: .noSRID),
                Coordinate3D(x: off + 200, y: off, projection: .noSRID),
                Coordinate3D(x: off + 100, y: off + 200, projection: .noSRID),
                Coordinate3D(x: off, y: off, projection: .noSRID),
            ]]))
            features.append(Feature(try #require(MultiPolygon([small])), id: .int(i)))
        }

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: features, boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let layer = try #require(decoded["test"])
        #expect(layer.features.count == 25, "all 25 features decoded")
        // Find the feature whose ring0 has 67 rings (the big mpoly). Its ring0
        // must come back with its original first vertex.
        let big = try #require(layer.features.first(where: {
            ($0.geometry as? MultiPolygon)?.coordinates.first?.count == 67
        }))
        let result = try #require(big.geometry as? MultiPolygon)
        #expect(result.coordinates.count == 1, "one polygon")
        #expect(result.coordinates[0].count == 67, "67 rings")
        // Ring 0 must come back with its original first vertex (allowing Int rounding).
        // normalizePolygonTilespace keeps ring0 as-is because its tile-space area
        // is negative (exterior), so expected == original.
        let expectedRing0 = ring0
        let decodedRing0 = result.coordinates[0][0]
        #expect(decodedRing0.count == expectedRing0.count)
        #expect(abs(decodedRing0[0].x - expectedRing0[0].x) < 1.0, "ring0 first x preserved (got \(decodedRing0[0].x), want \(expectedRing0[0].x))")
        #expect(abs(decodedRing0[0].y - expectedRing0[0].y) < 1.0, "ring0 first y preserved (got \(decodedRing0[0].y), want \(expectedRing0[0].y))")
        // Diagnostic: dump decoded ring0 vs expected to spot any misalignment.
        if abs(decodedRing0[0].y - expectedRing0[0].y) >= 1.0 {
            print("Expected ring0: \(expectedRing0.map { "(\($0.x),\($0.y))" })")
            print("Decoded   ring0: \(decodedRing0.map { "(\($0.x),\($0.y))" })")
        }
    }

    @Test
    func altitudeIsDropped() throws {
        let coord = Coordinate3D(latitude: 10.0, longitude: 20.0, altitude: 500.0, m: 123.0)
        let feature = Feature(Point(coord), properties: [:] as [String: Sendable])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)
        let pt = try #require(feat.geometry.allCoordinates.first)

        #expect(pt.latitude == 10.0)
        #expect(pt.longitude == 20.0)
        #expect(pt.altitude == nil)
    }

}
