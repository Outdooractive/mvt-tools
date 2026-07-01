import Foundation
import GISTools
@testable import MVTTools
import struct GISTools.Polygon
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

    @Test
    func coordinateAccuracy() throws {
        // Test MLT coordinate roundtrip fidelity using noSRID (raw tile-extent).
        // Coordinates pass through Float32 → Int → Double with ~1.0 tolerance.
        let tolerance: Double = 1.0
        let coords = [
            Coordinate3D(x: 100.0, y: 200.0, projection: .noSRID),
            Coordinate3D(x: 1500.0, y: 800.0, projection: .noSRID),
            Coordinate3D(x: 3000.0, y: 3500.0, projection: .noSRID),
        ]

        func roundtrip(_ geom: GeoJsonGeometry) throws -> GeoJsonGeometry {
            let f = Feature(geom)
            let data = try #require(MLTEncoder.encode(
                layers: ["test": VectorTile.LayerContainer(features: [f], boundingBox: nil)],
                x: 0, y: 0, z: 0, projection: .noSRID))
            let decoded = try MLTDecoder.decode(
                from: data, x: 0, y: 0, z: 0, projection: .noSRID)
            return try #require(decoded["test"]?.features.first?.geometry)
        }

        // Point
        do {
            let geom = try roundtrip(Point(coords[0]))
            let pt = try #require(geom as? Point)
            #expect(abs(pt.coordinate.x - coords[0].x) < tolerance)
            #expect(abs(pt.coordinate.y - coords[0].y) < tolerance)
        }

        // MultiPoint
        do {
            let mp = try #require(MultiPoint(coords))
            let geom = try roundtrip(mp)
            let result = try #require(geom as? MultiPoint)
            #expect(result.coordinates.count == coords.count)
            for (a, b) in zip(result.coordinates, coords) {
                #expect(abs(a.x - b.x) < tolerance)
                #expect(abs(a.y - b.y) < tolerance)
            }
        }

        // LineString
        do {
            let ls = try #require(LineString(coords))
            let geom = try roundtrip(ls)
            let result = try #require(geom as? LineString)
            #expect(result.coordinates.count == coords.count)
            for (a, b) in zip(result.coordinates, coords) {
                #expect(abs(a.x - b.x) < tolerance)
                #expect(abs(a.y - b.y) < tolerance)
            }
        }

        // Polygon (closed ring)
        do {
            let ring = coords + [coords[0]]
            let poly = try #require(Polygon([ring]))
            let geom = try roundtrip(poly)
            let result = try #require(geom as? Polygon)
            #expect(result.rings.count == 1)
            #expect(result.rings[0].coordinates.count == ring.count)
            for (a, b) in zip(result.rings[0].coordinates, ring) {
                #expect(abs(a.x - b.x) < tolerance)
                #expect(abs(a.y - b.y) < tolerance)
            }
        }
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

}
