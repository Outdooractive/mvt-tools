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
