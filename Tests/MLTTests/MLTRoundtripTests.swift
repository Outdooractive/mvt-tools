import Foundation
import GISTools
import MLT
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

        let data = try MLTEncoder.encode(layers: [("test", 4096, [original])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.first)

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

        let data = try MLTEncoder.encode(layers: [("test", 4096, [original])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.first)

        #expect(feat.properties["s"] as? String == "hello")
        #expect(feat.properties["i"] as? Int64 == 42)
        #expect(feat.properties["d"] as? Double == 3.14)
        #expect(feat.properties["b"] as? Bool == true)
    }

    // MARK: - Geometry round-trips

    @Test
    func encodePointAndLine() throws {
        let point = Feature(Point(Coordinate3D(latitude: 5.0, longitude: 10.0)), id: .int(1))
        let line = Feature(LineString([
            Coordinate3D(latitude: 1.0, longitude: 2.0),
            Coordinate3D(latitude: 3.0, longitude: 4.0),
        ])!, id: .int(2))
        let poly = Feature(Polygon([[
            Coordinate3D(latitude: 0.0, longitude: 0.0),
            Coordinate3D(latitude: 10.0, longitude: 0.0),
            Coordinate3D(latitude: 10.0, longitude: 10.0),
            Coordinate3D(latitude: 0.0, longitude: 10.0),
            Coordinate3D(latitude: 0.0, longitude: 0.0),
        ]])!, id: .int(3))

        let data = try MLTEncoder.encode(
            layers: [
                ("points", 4096, [point]),
                ("lines", 4096, [line]),
                ("polygons", 4096, [poly]),
            ],
            x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        #expect(decoded.keys.count == 3)
        #expect(decoded["points"]?.count == 1)
        #expect(decoded["lines"]?.count == 1)
        #expect(decoded["polygons"]?.count == 1)
    }

    @Test
    func coordinateAccuracy() throws {
        // Real-world coordinates round-tripped through z=0 (single world tile).
        // At z=0 the 4096-extent covers 360° → ~0.088°/unit, so tolerance is 0.1°.
        let tolerance: Double = 0.1
        let tileZ = 0, tileX = 0, tileY = 0
        let extent: UInt32 = 4096
        let coords = [
            Coordinate3D(latitude: 3.87, longitude: 11.52),
            Coordinate3D(latitude: 48.8566, longitude: 2.3522),
            Coordinate3D(latitude: 40.7128, longitude: -74.0060),
        ]

        // Point
        do {
            let f = Feature(Point(coords[0]))
            let data = try MLTEncoder.encode(
                layers: [("test", extent, [f])],
                x: tileX, y: tileY, z: tileZ,
                projection: .epsg4326)
            let decoded = try MLTDecoder.decode(
                from: data,
                x: tileX, y: tileY, z: tileZ,
                projection: .epsg4326)
            let pt = try #require(decoded["test"]?.first?.geometry as? Point)
            #expect(abs(pt.coordinate.latitude - coords[0].latitude) < tolerance)
            #expect(abs(pt.coordinate.longitude - coords[0].longitude) < tolerance)
        }

        // MultiPoint
        do {
            let mp = try #require(MultiPoint(coords))
            let f = Feature(mp)
            let data = try MLTEncoder.encode(
                layers: [("test", extent, [f])],
                x: tileX, y: tileY, z: tileZ,
                projection: .epsg4326)
            let decoded = try MLTDecoder.decode(
                from: data,
                x: tileX, y: tileY, z: tileZ,
                projection: .epsg4326)
            let result = try #require(decoded["test"]?.first?.geometry as? MultiPoint)
            #expect(result.coordinates.count == coords.count)
            for (a, b) in zip(result.coordinates, coords) {
                #expect(abs(a.latitude - b.latitude) < tolerance)
                #expect(abs(a.longitude - b.longitude) < tolerance)
            }
        }

        // LineString
        do {
            let ls = try #require(LineString(coords))
            let f = Feature(ls)
            let data = try MLTEncoder.encode(
                layers: [("test", extent, [f])],
                x: tileX, y: tileY, z: tileZ,
                projection: .epsg4326)
            let decoded = try MLTDecoder.decode(
                from: data,
                x: tileX, y: tileY, z: tileZ,
                projection: .epsg4326)
            let result = try #require(decoded["test"]?.first?.geometry as? LineString)
            #expect(result.coordinates.count == coords.count)
            for (a, b) in zip(result.coordinates, coords) {
                #expect(abs(a.latitude - b.latitude) < tolerance)
                #expect(abs(a.longitude - b.longitude) < tolerance)
            }
        }

        // Polygon (closed ring)
        do {
            let ring = coords + [coords[0]]
            let poly = try #require(Polygon([ring]))
            let f = Feature(poly)
            let data = try MLTEncoder.encode(
                layers: [("test", extent, [f])],
                x: tileX, y: tileY, z: tileZ,
                projection: .epsg4326)
            let decoded = try MLTDecoder.decode(
                from: data,
                x: tileX, y: tileY, z: tileZ,
                projection: .epsg4326)
            let result = try #require(decoded["test"]?.first?.geometry as? Polygon)
            #expect(result.rings.count == 1)
            #expect(result.rings[0].coordinates.count == ring.count)
            for (a, b) in zip(result.rings[0].coordinates, ring) {
                #expect(abs(a.latitude - b.latitude) < tolerance)
                #expect(abs(a.longitude - b.longitude) < tolerance)
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

        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.first)

        #expect(feat.geometry is MultiPoint)
    }

    @Test
    func altitudeIsDropped() throws {
        let coord = Coordinate3D(latitude: 10.0, longitude: 20.0, altitude: 500.0, m: 123.0)
        let feature = Feature(Point(coord), properties: [:] as [String: Sendable])

        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.first)
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
        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let id = try #require(decoded["test"]?.first?.id)
        #expect(id.uint64Value == 42)
    }

    @Test
    func idTypeUInt() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .uint(99)
        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let id = try #require(decoded["test"]?.first?.id)
        #expect(id.uint64Value == 99)
    }

    @Test
    func idTypeMaxUInt() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .uint(UInt(UInt64.max))
        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        #expect(decoded["test"]?.first?.id != nil)
    }

    @Test
    func idTypeString() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .string("my-id")
        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        _ = decoded["test"]?.first
    }

    @Test
    func idTypeDouble() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .double(3.14)
        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        _ = decoded["test"]?.first
    }

    @Test
    func idTypeNegativeInt() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .int(-1)
        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        _ = decoded["test"]?.first
    }

    @Test
    func featureWithoutID() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: ["name": "no-id"] as [String: Sendable])

        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.first)

        #expect(feat.properties["name"] as? String == "no-id")
    }

    // MARK: - Layer / feature structure

    @Test
    func multipleFeaturesInLayer() throws {
        let f1 = Feature(Point(Coordinate3D(latitude: 1.0, longitude: 2.0)), id: .int(1))
        let f2 = Feature(Point(Coordinate3D(latitude: 3.0, longitude: 4.0)), id: .int(2))

        let data = try MLTEncoder.encode(layers: [("test", 4096, [f1, f2])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        #expect(decoded["test"]?.count == 2)
    }

    @Test
    func multipleLayers() throws {
        let f1 = Feature(Point(Coordinate3D(latitude: 1.0, longitude: 2.0)), id: .int(1))
        let f2 = Feature(Point(Coordinate3D(latitude: 3.0, longitude: 4.0)), id: .int(2))

        let data = try MLTEncoder.encode(
            layers: [
                ("layer_a", 4096, [f1]),
                ("layer_b", 4096, [f2]),
            ],
            x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        #expect(decoded["layer_a"]?.count == 1)
        #expect(decoded["layer_b"]?.count == 1)
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

        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.first)

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

        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.first)

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

        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.first)

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

        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.first)

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

        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.first)

        #expect(feat.properties["yes"] as? Bool == true)
        #expect(feat.properties["no"] as? Bool == false)
    }

    @Test
    func negativeValues() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [
            "neg": -42,
        ] as [String: Sendable])

        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.first)

        #expect(feat.properties["neg"] as? Int64 == -42)
    }

    @Test
    func emptyProperties() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [:])

        let data = try MLTEncoder.encode(layers: [("test", 4096, [feature])], x: 0, y: 0, z: 0, projection: .noSRID)
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.first)

        #expect(feat.properties.isEmpty)
    }

}
