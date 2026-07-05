import Foundation
import GISTools
@testable import MVTTools
import struct GISTools.Polygon
import GISToolsShapefile
import GISToolsGeoPackage
import Testing

struct MLTRoundtripTests {

    // MARK: - Property type fidelity

    @Test
    func typeFidelityThroughFeature() throws {
        let coord = Coordinate3D(latitude: 10.0, longitude: 20.0)
        let original = Feature(Point(coord), properties: [
            "stringy": "99",
            "exact": 50.0,
            "count": 50,
        ] as [String: Sendable])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [original], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .epsg4326)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .epsg4326)
        let feat = try #require(decoded["test"]?.features.first)

        #expect(feat.properties["stringy"] as? String == "99")
        #expect(feat.properties["exact"] as? Double == 50.0)
        #expect(feat.properties["count"] as? Int64 == 50)
    }

    @Test
    func allPropertiesTypes() throws {
        let coord = Coordinate3D(latitude: 10.0, longitude: 20.0)
        let original = Feature(Point(coord), properties: [
            "s": "hello",
            "i": 42,
            "d": 3.14,
            "b": true,
        ] as [String: Sendable])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [original], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .epsg4326)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .epsg4326)
        let feat = try #require(decoded["test"]?.features.first)

        #expect(feat.properties["s"] as? String == "hello")
        #expect(feat.properties["i"] as? Int64 == 42)
        #expect(feat.properties["d"] as? Double == 3.14)
        #expect(feat.properties["b"] as? Bool == true)
    }

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
        // Single ring (triangle)
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

    // MARK: - Coordinate accuracy across projections

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

    @Test
    func coordinateAccuracyNoSRID() async throws {
        // Raw tile-extent roundtrip through noSRID (no clipping, no projection).
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
        // Real-world lat/lon at z=0 (world tile).  Tolerance ~0.1° for 4096-extent.
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
        // EPSG:3857 at z=0 (world tile).  Each unit ≈ 9800 m → tolerance 15 km.
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
        // EPSG:4978 at z=0.  Each unit ≈ 3000 m, double projection adds noise → 50 km.
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

    // MARK: - Feature ID round-trips

    @Test
    func idTypeInt() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .int(42)
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let id = try #require(decoded["test"]?.features.first?.id)
        #expect(id.uint64Value == 42)
    }

    @Test
    func idTypeUInt() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .uint(99)
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let id = try #require(decoded["test"]?.features.first?.id)
        #expect(id.uint64Value == 99)
    }

    @Test
    func idTypeMaxUInt() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .uint(UInt(UInt64.max))
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        #expect(decoded["test"]?.features.first?.id != nil)
    }

    @Test
    func idTypeString() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .string("my-id")
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        _ = decoded["test"]?.features.first
    }

    @Test
    func idTypeDouble() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .double(3.14)
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        _ = decoded["test"]?.features.first
    }

    @Test
    func idTypeNegativeInt() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .int(-1)
        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        _ = decoded["test"]?.features.first
    }

    @Test
    func featureWithoutID() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: ["name": "no-id"] as [String: Sendable])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)

        #expect(feat.properties["name"] as? String == "no-id")
    }

    // MARK: - Layer / feature structure

    @Test
    func multipleFeaturesInLayer() throws {
        let f1 = Feature(Point(Coordinate3D(latitude: 1.0, longitude: 2.0)), id: .int(1))
        let f2 = Feature(Point(Coordinate3D(latitude: 3.0, longitude: 4.0)), id: .int(2))

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [f1, f2], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        #expect(decoded["test"]?.features.count == 2)
    }

    @Test
    func multipleLayers() throws {
        let f1 = Feature(Point(Coordinate3D(latitude: 1.0, longitude: 2.0)), id: .int(1))
        let f2 = Feature(Point(Coordinate3D(latitude: 3.0, longitude: 4.0)), id: .int(2))

        guard let data = MLTEncoder.encode(
            layers: [
                "layer_a": VectorTile.LayerContainer(features: [f1], boundingBox: nil),
                "layer_b": VectorTile.LayerContainer(features: [f2], boundingBox: nil),
            ],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        #expect(decoded["layer_a"]?.features.count == 1)
        #expect(decoded["layer_b"]?.features.count == 1)
    }

    // MARK: - Property edge cases

    @Test
    func specialCharsInProperties() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [
            "emoji": "🚀",
            "unicode": "straße",
            "spaces": "hello world",
            "empty": "",
        ] as [String: Sendable])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)

        #expect(feat.properties["emoji"] as? String == "🚀")
        #expect(feat.properties["unicode"] as? String == "straße")
        #expect(feat.properties["spaces"] as? String == "hello world")
        #expect(feat.properties["empty"] as? String == "")
    }

    @Test
    func specialPropertyKeys() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [
            "key.with.dots": "value1",
            "key with spaces": "value2",
        ] as [String: Sendable])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)

        #expect(feat.properties["key.with.dots"] as? String == "value1")
        #expect(feat.properties["key with spaces"] as? String == "value2")
    }

    @Test
    func mixedPropertyTypes() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [
            "int": 42,
            "double": 3.14,
            "string": "text",
            "bool": true,
        ] as [String: Sendable])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)

        #expect(feat.properties["int"] as? Int64 == 42)
        #expect(feat.properties["double"] as? Double == 3.14)
        #expect(feat.properties["string"] as? String == "text")
        #expect(feat.properties["bool"] as? Bool == true)
    }

    @Test
    func manyProperties() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var props: [String: Sendable] = [:]
        for i in 0 ..< 50 {
            props["key_\(i)"] = "value_\(i)"
        }
        let feature = Feature(Point(coord), properties: props)

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)

        #expect(feat.properties.count == 50)
        for i in 0 ..< 50 {
            #expect(feat.properties["key_\(i)"] as? String == "value_\(i)")
        }
    }

    @Test
    func boolProperties() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [
            "yes": true,
            "no": false,
        ] as [String: Sendable])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)

        #expect(feat.properties["yes"] as? Bool == true)
        #expect(feat.properties["no"] as? Bool == false)
    }

    @Test
    func negativeValues() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [
            "neg": -42,
        ] as [String: Sendable])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)

        #expect(feat.properties["neg"] as? Int64 == -42)
    }

    @Test
    func emptyProperties() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [:])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)

        #expect(feat.properties.isEmpty)
    }

    // MARK: - VectorTile+MLT convenience API

    @Test
    func mltDataInitAndExport() throws {
        // Create a tile from MLT data and re-export it.
        let point = Feature(Point(Coordinate3D(latitude: 48.8566, longitude: 2.3522)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 48.8566, longitude: 2.3522),
            Coordinate3D(latitude: 52.5200, longitude: 13.4050),
        ])!, id: .int(2))

        guard let originalData = MLTEncoder.encode(
            layers: [
                "points": VectorTile.LayerContainer(features: [point], boundingBox: nil),
                "lines": VectorTile.LayerContainer(features: [line], boundingBox: nil),
            ],
            x: 0, y: 0, z: 0, projection: .epsg4326)
        else { return }

        let tile = try #require(VectorTile(
            mltData: originalData,
            x: 0, y: 0, z: 0,
            projection: .epsg4326))
        #expect(tile.origin == .mlt)
        #expect(tile.layerNames.count == 2)
        #expect(tile.layerNames.contains("points"))
        #expect(tile.layerNames.contains("lines"))

        let reencoded = try #require(tile.mltData())
        #expect(reencoded.isEmpty == false)

        let decoded = try MLTDecoder.decode(
            from: reencoded, x: 0, y: 0, z: 0, projection: .epsg4326)
        #expect(decoded["points"]?.features.count == 1)
        #expect(decoded["lines"]?.features.count == 1)
    }

    @Test
    func mltContentsOfAndWrite() throws {
        let point = Feature(Point(Coordinate3D(latitude: 48.8566, longitude: 2.3522)), id: .int(1))

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [point], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .epsg4326)
        else { return }

        // Write to a temp file, read it back.
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mlt_\(UUID().uuidString).mlt")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        let writeTile = try #require(VectorTile(
            mltData: data,
            x: 0, y: 0, z: 0,
            projection: .epsg4326))
        #expect(writeTile.writeMLT(to: tempUrl))

        let readTile = try #require(VectorTile(
            contentsOfMLT: tempUrl,
            x: 0, y: 0, z: 0,
            projection: .epsg4326))
        #expect(readTile.origin == .mlt)
        #expect(readTile.layerNames == ["test"])
    }

    @Test
    func mltContentsOfWithTile() throws {
        let point = Feature(Point(Coordinate3D(latitude: 48.8566, longitude: 2.3522)), id: .int(1))

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [point], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .epsg4326)
        else { return }

        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mlt_\(UUID().uuidString).mlt")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        let tile = try #require(VectorTile(
            mltData: data,
            x: 0, y: 0, z: 0,
            projection: .epsg4326))
        #expect(tile.writeMLT(to: tempUrl))

        let mapTile = MapTile(x: 0, y: 0, z: 0)
        let readTile = try #require(VectorTile(
                    contentsOfMLT: tempUrl,
            tile: mapTile,
            projection: .epsg4326))
        #expect(readTile.origin == .mlt)
        #expect(readTile.layerNames == ["test"])
        #expect(readTile.x == 0)
        #expect(readTile.y == 0)
        #expect(readTile.z == 0)
    }

    // MARK: - Cross-format roundtrip (MVT ↔ MLT)

    @Test
    func mvtToMltRoundtrip() throws {
        // Load a real MVT tile, re-encode as MLT, then back to MVT.
        let mvtData = try TestData.dataFromFile(name: "14_8716_8015.vector.mvt")

        let mvtTile = try #require(VectorTile(
            mvtData: mvtData,
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326))
        #expect(mvtTile.origin == .mvt)
        #expect(mvtTile.layers.isEmpty == false)

        // Re-encode as MLT and decode.
        guard let mltData = MLTEncoder.encode(
            layers: mvtTile.layers,
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326)
        else { return }

        let mltTile = try #require(VectorTile(
            mltData: mltData,
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326))
        #expect(mltTile.origin == .mlt)
        #expect(mltTile.layers.isEmpty == false)

        // Re-encode MLT back to MVT.
        let mvt2Data = try #require(mltTile.mvtData())
        let mvt2Tile = try #require(VectorTile(
            mvtData: mvt2Data,
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326))
        #expect(mvt2Tile.origin == .mvt)
        #expect(mvt2Tile.layers.isEmpty == false)
    }

    @Test
    func mltToMvtRoundtrip() throws {
        // Create an MLT-encoded tile, re-encode it as MVT, verify features survive.
        let point = Feature(Point(Coordinate3D(latitude: 48.8566, longitude: 2.3522)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 48.8566, longitude: 2.3522),
            Coordinate3D(latitude: 52.5200, longitude: 13.4050),
        ])!, id: .int(2))

        guard let mltData = MLTEncoder.encode(
            layers: [
                "points": VectorTile.LayerContainer(features: [point], boundingBox: nil),
                "lines": VectorTile.LayerContainer(features: [line], boundingBox: nil),
            ],
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326)
        else { return }

        let mltTile = try #require(VectorTile(
            mltData: mltData,
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326))

        // Re-encode as MVT.
        let mvtData = try #require(mltTile.mvtData())

        let mvtTile = try #require(VectorTile(
            mvtData: mvtData,
            x: 8716, y: 8015, z: 14,
            projection: .epsg4326))
        #expect(mvtTile.origin == .mvt)
        #expect(mvtTile.layers.keys == mltTile.layers.keys)

        for (name, container) in mvtTile.layers {
            let originalContainer = try #require(mltTile.layers[name])
            #expect(container.features.count == originalContainer.features.count,
                    "Layer '\(name)' feature count mismatch")
        }
    }

    // MARK: - VectorTile+GPX convenience API

    private static let gpxWaypoints: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="test">
      <wpt lat="52.518611" lon="13.376111">
        <ele>35.0</ele>
        <name>Berlin</name>
        <sym>City</sym>
      </wpt>
      <wpt lat="48.8566" lon="2.3522">
        <ele>25.0</ele>
        <name>Paris</name>
        <sym>Landmark</sym>
      </wpt>
    </gpx>
    """

    @Test
    func gpxDataInit() throws {
        let data = try #require(Self.gpxWaypoints.data(using: .utf8))
        let tile = try #require(VectorTile(
            gpxData: data,
            indexed: nil))
        #expect(tile.origin == .gpx)
        // Waypoints should be split into a "wpt" layer by default.
        #expect(tile.layers.keys.contains("wpt"),
                "GPX features should be in a 'wpt' layer")
        #expect(tile.layers["wpt"]?.features.count == 2)
    }

    @Test
    func gpxContentsOfAndWrite() throws {
        let data = try #require(Self.gpxWaypoints.data(using: .utf8))
        let tile = try #require(VectorTile(gpxData: data))

        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gpx_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        #expect(tile.writeGPX(to: tempUrl))
        #expect(FileManager.default.fileExists(atPath: tempUrl.path))

        let readTile = try #require(VectorTile(contentsOfGPX: tempUrl))
        #expect(readTile.origin == .gpx)
        #expect(readTile.layers.isEmpty == false)
    }

    @Test
    func gpxToGpxDataRoundtrip() throws {
        let data = try #require(Self.gpxWaypoints.data(using: .utf8))
        let tile = try #require(VectorTile(gpxData: data))

        let exported = try #require(tile.toGpxData())
        #expect(exported.isEmpty == false)

        // Re-import and verify features survive.
        let reimported = try #require(VectorTile(gpxData: exported))
        #expect(reimported.origin == .gpx)
        let reCount = reimported.layers.values.reduce(0) { $0 + $1.features.count }
        #expect(reCount == 2)
    }

    // MARK: - VectorTile+Shapefile convenience API

    @Test
    func shapefileInit() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shp_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shapefileUrl = tempDir.appendingPathComponent("test_points")
        let points = [
            Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1)),
            Feature(Point(Coordinate3D(latitude: 30.0, longitude: 40.0)), id: .int(2)),
        ]
        let fc = FeatureCollection(points)
        try ShapefileCoder.write(fc, to: shapefileUrl)

        let tile = try #require(VectorTile(
            shapefile: shapefileUrl.appendingPathExtension("shp")))
        #expect(tile.origin == .shapefile)
        #expect(tile.layerNames == ["test_points"])
        #expect(tile.features(for: "test_points").count == 2)
    }

    @Test
    func shapefileWriteSingle() throws {
        // Create a tile with features, export as shapefile, read back.
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shp_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var tile = VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)!
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        tile.setFeatures([point], for: "test_layer")

        let outputUrl = tempDir.appendingPathComponent("output")
        try tile.writeShapefile(to: outputUrl, layerName: "test_layer")
        #expect(FileManager.default.fileExists(atPath: outputUrl.appendingPathExtension("shp").path))
        #expect(FileManager.default.fileExists(atPath: outputUrl.appendingPathExtension("dbf").path))

        // Read back and verify.
        let readTile = try #require(VectorTile(shapefile: outputUrl.appendingPathExtension("shp")))
        #expect(readTile.origin == .shapefile)
        #expect(readTile.layers.values.reduce(0) { $0 + $1.features.count } == 1)
    }

    @Test
    func shapefileWritePerLayer() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shp_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var tile = VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)!
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 10.0, longitude: 20.0),
            Coordinate3D(latitude: 30.0, longitude: 40.0),
        ])!, id: .int(2))
        tile.setFeatures([point], for: "points")
        tile.setFeatures([line], for: "lines")

        let outDir = tempDir.appendingPathComponent("layers")
        try tile.writeShapefiles(to: outDir)
        #expect(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("points.shp").path))
        #expect(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("lines.shp").path))
    }

    @Test
    func shapefileMixedGeometryError() throws {
        var tile = VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)!
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 10.0, longitude: 20.0),
            Coordinate3D(latitude: 30.0, longitude: 40.0),
        ])!, id: .int(2))
        tile.setFeatures([point], for: "points")
        tile.setFeatures([line], for: "lines")

        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shp_\(UUID().uuidString)_mixed")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        #expect(throws: ShapefileError.mixedGeometry(types: [.point, .lineString])) {
            try tile.writeShapefile(to: tempUrl)
        }
    }

    // MARK: - VectorTile+GeoPackage convenience API

    @Test
    func geopackageInitTable() async throws {
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gpkg_\(UUID().uuidString).gpkg")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        var tile = VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)!
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        tile.setFeatures([point], for: "test_table")
        try await tile.writeGeoPackage(to: tempUrl, table: "test_table")

        let imported = try await VectorTile(geopackage: tempUrl, table: "test_table")
        #expect(imported.origin == .geopackage)
        #expect(imported.layerNames == ["test_table"])
        #expect(imported.features(for: "test_table").count == 1)
    }

    @Test
    func geopackageInitAll() async throws {
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gpkg_\(UUID().uuidString).gpkg")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        var tile = VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)!
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 10.0, longitude: 20.0),
            Coordinate3D(latitude: 30.0, longitude: 40.0),
        ])!, id: .int(2))
        tile.setFeatures([point], for: "points")
        tile.setFeatures([line], for: "lines")
        try await tile.writeGeoPackage(to: tempUrl)

        let imported = try await VectorTile(geopackage: tempUrl)
        #expect(imported.origin == .geopackage)
        #expect(imported.layerNames.contains("points"))
        #expect(imported.layerNames.contains("lines"))
    }

    @Test
    func geopackageWritePerLayer() async throws {
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gpkg_\(UUID().uuidString).gpkg")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        var tile = VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)!
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 10.0, longitude: 20.0),
            Coordinate3D(latitude: 30.0, longitude: 40.0),
        ])!, id: .int(2))
        tile.setFeatures([point], for: "points")
        tile.setFeatures([line], for: "lines")
        try await tile.writeGeoPackage(to: tempUrl)

        let conn = try GeoPackageConnection(url: tempUrl)
        let contents = try await conn.readContents()
        await conn.close()
        let tables = contents.filter { $0.dataType == "features" }.map(\.tableName)
        #expect(tables.contains("points"))
        #expect(tables.contains("lines"))
    }

    @Test
    func geopackageRoundtripWithGpkgLayer() async throws {
        // Export two layers merged into one table, then import and verify
        // the "gpkg_layer" property restores the original layer structure.
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gpkg_\(UUID().uuidString).gpkg")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        var tile = VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)!
        let point = Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 10.0, longitude: 20.0),
            Coordinate3D(latitude: 30.0, longitude: 40.0),
        ])!, id: .int(2))
        tile.setFeatures([point], for: "points")
        tile.setFeatures([line], for: "lines")

        // Export merged to a single table.
        try await tile.writeGeoPackage(to: tempUrl, table: "merged")

        // Import back — "gpkg_layer" should split into the original layers.
        let imported = try await VectorTile(geopackage: tempUrl, table: "merged")
        #expect(imported.origin == .geopackage)
        #expect(imported.layerNames.contains("points"))
        #expect(imported.layerNames.contains("lines"))
        #expect(imported.features(for: "points").count == 1)
        #expect(imported.features(for: "lines").count == 1)
        // The "gpkg_layer" property should be stripped from the features.
        for feat in imported.features(for: "points") {
            #expect(feat.properties["gpkg_layer"] == nil)
        }
        for feat in imported.features(for: "lines") {
            #expect(feat.properties["gpkg_layer"] == nil)
        }
    }

}
