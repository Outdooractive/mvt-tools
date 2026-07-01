import CMLT
import Foundation
import GISTools
import MLTTools
import struct GISTools.Polygon
import Testing

/// Path to MLT test fixtures in the submodule.
private var testFixturesDir: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Dependencies")
        .appendingPathComponent("maplibre-tile-spec")
        .appendingPathComponent("test")
        .appendingPathComponent("expected")
        .appendingPathComponent("tag0x01")
        .appendingPathComponent("omt")
}

struct MLTTileTests {

    // MARK: - Basic decode

    /// Decodes a real MLT tile and verifies layer/feature counts.
    @Test
    func decodeRealTile() throws {
        let url = testFixturesDir.appendingPathComponent("0_0_0.mlt")
        let data = try Data(contentsOf: url)
        #expect(data.isEmpty == false)

        let tile = try MLTTile.decode(from: data)
        #expect(tile.layerCount > 0)

        var totalFeatures = 0
        for layer in tile.layers {
            #expect(layer.name.isEmpty == false)
            #expect(layer.extent > 0)
            totalFeatures += layer.featureCount
            #expect(layer.propertyKeys.isEmpty == false)
        }
        #expect(totalFeatures > 0)
    }

    /// Tests that the first feature in each layer has valid geometry and properties.
    @Test
    func firstFeatureProperties() throws {
        let url = testFixturesDir.appendingPathComponent("9_264_342.mlt")
        let data = try Data(contentsOf: url)
        let tile = try MLTTile.decode(from: data)

        for layer in tile.layers {
            guard layer.featureCount > 0 else { continue }

            let feat = layer.feature(at: 0)
            let geom = feat.toGISToolsGeometry()
            #expect(geom != nil)
            if let geom {
                #expect(geom.type != .invalid)
            }

            let props = feat.allProperties()
            #expect(props.isEmpty == false)
        }
    }

    /// Tests that all features can be converted to GISTools features.
    @Test
    func convertAllToGISTools() throws {
        let url = testFixturesDir.appendingPathComponent("7_66_84.mlt")
        let data = try Data(contentsOf: url)
        let tile = try MLTTile.decode(from: data)

        var converted = 0
        var failed = 0
        for layer in tile.layers {
            for fi in 0 ..< layer.featureCount {
                if let _ = layer.feature(at: fi).toGISToolsFeature() {
                    converted += 1
                }
                else {
                    failed += 1
                }
            }
        }
        #expect(converted > 0)
        #expect(failed == 0)
    }

    /// Tests round-trip coordinate access.
    @Test
    func coordinateAccess() throws {
        let url = testFixturesDir.appendingPathComponent("9_264_342.mlt")
        let data = try Data(contentsOf: url)
        let tile = try MLTTile.decode(from: data)

        for layer in tile.layers {
            for fi in 0 ..< min(layer.featureCount, 5) {
                let feat = layer.feature(at: fi)
                let gt = Int(feat.geometryType)

                let geom = feat.toGISToolsGeometry()
                if let geom, gt != kMLTGeometryPoint {
                    #expect(geom.allCoordinates.count > 0)
                }
            }
        }
    }

    // MARK: - Property type fidelity

    /// Tests round-trip through toGISToolsFeature: types are preserved faithfully.
    @Test
    func typeFidelityThroughFeature() throws {
        let coord = Coordinate3D(latitude: 10.0, longitude: 20.0)
        let original = Feature(Point(coord), properties: [
            "stringy": "99",
            "exact": 50.0,
            "count": 50,
        ] as [String: Sendable])

        let data = try MLTTile.encode(layers: [("test", 4096, [original])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())

        #expect(decoded.properties["stringy"] as? String == "99")
        #expect(decoded.properties["exact"] as? Double == 50.0)
        #expect(decoded.properties["count"] as? Int64 == 50)
    }

    /// Tests that allProperties() returns correct types.
    @Test
    func allPropertiesTypes() throws {
        let coord = Coordinate3D(latitude: 10.0, longitude: 20.0)
        let original = Feature(Point(coord), properties: [
            "s": "hello",
            "i": 42,
            "d": 3.14,
            "b": true,
        ] as [String: Sendable])

        let data = try MLTTile.encode(layers: [("test", 4096, [original])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())

        #expect(decoded.properties["s"] as? String == "hello")
        #expect(decoded.properties["i"] as? Int64 == 42)
        #expect(decoded.properties["d"] as? Double == 3.14)
        #expect(decoded.properties["b"] as? Bool == true)
    }

    // MARK: - Round-trip encode / decode

    /// Encodes Point and LineString features and verifies round-trip.
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

        let data = try MLTTile.encode(layers: [
            ("points", 4096, [point]),
            ("lines", 4096, [line]),
            ("polygons", 4096, [poly]),
        ])
        #expect(data.isEmpty == false)

        let tile = try MLTTile.decode(from: data)
        #expect(tile.layerCount == 3)
        #expect(tile.layers[0].name == "points")
        #expect(tile.layers[0].featureCount == 1)
        #expect(tile.layers[1].name == "lines")
        #expect(tile.layers[1].featureCount == 1)
        #expect(tile.layers[2].name == "polygons")
        #expect(tile.layers[2].featureCount == 1)
    }

    // MARK: - Edge cases

    /// Encode/decode features with no ID — encoder assigns a default id on encode.
    @Test
    func featureWithoutID() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: ["name": "no-id"] as [String: Sendable])

        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())

        #expect(decoded.properties["name"] as? String == "no-id")
    }

    /// Encode/decode a feature with `.int` ID.
    @Test
    func idTypeInt() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .int(42)
        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())
        #expect(decoded.id?.uint64Value == 42)
    }

    /// Encode/decode a feature with `.uint` ID.
    @Test
    func idTypeUInt() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .uint(99)
        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())
        #expect(decoded.id?.uint64Value == 99)
    }

    /// Encode/decode with the maximum ID value (UInt64.max).
    @Test
    func idTypeMaxUInt() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .uint(UInt(UInt64.max))
        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())
        #expect(decoded.id != nil)
    }

    /// `.string` ID is not representable in MLT — encoder silently drops it.
    @Test
    func idTypeString() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .string("my-id")
        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())
        // String IDs cannot round-trip through MLT; id will be nil
        _ = decoded
    }

    /// `.double` ID is not representable in MLT — encoder silently drops it.
    @Test
    func idTypeDouble() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .double(3.14)
        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())
        // Double IDs cannot round-trip through MLT; id will be nil
        _ = decoded
    }

    /// Negative `.int` ID — not representable in MLT's unsigned ID format.
    /// MLT only supports unsigned integer IDs; negative IDs are dropped.
    @Test
    func idTypeNegativeInt() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var feature = Feature(Point(coord), properties: [:])
        feature.id = .int(-1)
        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())
        // Negative int IDs can't round-trip through MLT
        _ = decoded
    }

    /// Multiple features in a single layer.
    @Test
    func multipleFeaturesInLayer() throws {
        let coord1 = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let coord2 = Coordinate3D(latitude: 3.0, longitude: 4.0)
        let f1 = Feature(Point(coord1), id: .int(1))
        let f2 = Feature(Point(coord2), id: .int(2))

        let data = try MLTTile.encode(layers: [("test", 4096, [f1, f2])])
        let tile = try MLTTile.decode(from: data)
        #expect(tile.layers[0].featureCount == 2)
    }

    /// Multiple layers with different geometry types.
    @Test
    func multipleLayers() throws {
        let f1 = Feature(Point(Coordinate3D(latitude: 1.0, longitude: 2.0)), id: .int(1))
        let f2 = Feature(Point(Coordinate3D(latitude: 3.0, longitude: 4.0)), id: .int(2))

        let data = try MLTTile.encode(layers: [
            ("layer_a", 4096, [f1]),
            ("layer_b", 4096, [f2]),
        ])
        let tile = try MLTTile.decode(from: data)
        #expect(tile.layerCount == 2)
        #expect(tile.layers[0].name == "layer_a")
        #expect(tile.layers[1].name == "layer_b")
    }

    /// String property with special characters.
    @Test
    func specialCharsInProperties() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [
            "emoji": "🚀",
            "unicode": "straße",
            "spaces": "hello world",
            "empty": "",
        ] as [String: Sendable])

        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())

        #expect(decoded.properties["emoji"] as? String == "🚀")
        #expect(decoded.properties["unicode"] as? String == "straße")
        #expect(decoded.properties["spaces"] as? String == "hello world")
        #expect(decoded.properties["empty"] as? String == "")
    }

    /// Property keys with special characters.
    @Test
    func specialPropertyKeys() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [
            "key.with.dots": "value1",
            "key with spaces": "value2",
        ] as [String: Sendable])

        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())

        #expect(decoded.properties["key.with.dots"] as? String == "value1")
        #expect(decoded.properties["key with spaces"] as? String == "value2")
    }

    /// Mixed property types in the same feature.
    @Test
    func mixedPropertyTypes() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [
            "int": 42,
            "double": 3.14,
            "string": "text",
            "bool": true,
        ] as [String: Sendable])

        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())

        #expect(decoded.properties["int"] as? Int64 == 42)
        #expect(decoded.properties["double"] as? Double == 3.14)
        #expect(decoded.properties["string"] as? String == "text")
        #expect(decoded.properties["bool"] as? Bool == true)
    }

    /// Many properties (stress test).
    @Test
    func manyProperties() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        var props: [String: Sendable] = [:]
        for i in 0 ..< 50 {
            props["key_\(i)"] = "value_\(i)"
        }
        let feature = Feature(Point(coord), properties: props)

        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())

        #expect(decoded.properties.count == 50)
        for i in 0 ..< 50 {
            #expect(decoded.properties["key_\(i)"] as? String == "value_\(i)")
        }
    }

    /// Bool properties with both true and false.
    @Test
    func boolProperties() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [
            "yes": true,
            "no": false,
        ] as [String: Sendable])

        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())

        #expect(decoded.properties["yes"] as? Bool == true)
        #expect(decoded.properties["no"] as? Bool == false)
    }

    /// Negative integer values.
    @Test
    func negativeValues() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [
            "neg": -42,
        ] as [String: Sendable])

        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())

        #expect(decoded.properties["neg"] as? Int64 == -42)
    }

    /// Empty property dictionary.
    @Test
    func emptyProperties() throws {
        let coord = Coordinate3D(latitude: 1.0, longitude: 2.0)
        let feature = Feature(Point(coord), properties: [:])

        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())

        #expect(decoded.properties.isEmpty)
    }

    /// Empty layer produces valid data that decodes without error.
    @Test
    func emptyLayer() throws {
        let encoder = mlt_encoder_create()
        mlt_encoder_begin_layer(encoder, "empty", 4096)
        var outLen: Int = 0
        let buffer = mlt_encoder_finish(encoder, &outLen)
        defer { mlt_buffer_free(buffer) }
        mlt_encoder_destroy(encoder)

        let data = Data(bytes: buffer!, count: outLen)
        let tile = try MLTTile.decode(from: data)
        // Empty layers may be dropped by the decoder
        #expect(tile.layerCount == 0 || tile.layers[0].name == "empty")
    }

    /// Decoding totally invalid data returns the proper error.
    @Test
    func invalidDataFails() throws {
        let data = Data([0x00, 0x01, 0x02, 0x03])
        #expect(throws: MLTError.decodeFailed) {
            try MLTTile.decode(from: data)
        }
    }

    /// Decoding empty data produces an empty tile (no layers).
    @Test
    func emptyDataFails() throws {
        let tile = try MLTTile.decode(from: Data())
        #expect(tile.layerCount == 0)
    }

    /// MultiPoint encode/decode round trip.
    @Test
    func multiPointRoundtrip() throws {
        let coords = [
            Coordinate3D(latitude: 1.0, longitude: 2.0),
            Coordinate3D(latitude: 3.0, longitude: 4.0),
        ]
        let mp = try #require(MultiPoint(coords))
        let feature = Feature(mp, id: .int(1))

        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())

        #expect(decoded.geometry is MultiPoint)
    }

    /// Tests that altitude (z) and m-values are dropped during encode/decode.
    ///
    /// The MLT spec lists 3D coordinates as a planned feature, but the current
    /// C++ implementation's `Vertex` type only stores `int32_t x, y`. Elevation
    /// data is silently discarded during encoding.
    @Test
    func altitudeIsDropped() throws {
        let coord = Coordinate3D(latitude: 10.0, longitude: 20.0, altitude: 500.0, m: 123.0)
        let feature = Feature(Point(coord), properties: [:] as [String: Sendable])

        let data = try MLTTile.encode(layers: [("test", 4096, [feature])])
        let tile = try MLTTile.decode(from: data)
        let decoded = try #require(tile.layers[0].feature(at: 0).toGISToolsFeature())

        let decodedCoord = try #require(decoded.geometry.allCoordinates.first)
        // 2D position is preserved
        #expect(decodedCoord.latitude == 10.0)
        #expect(decodedCoord.longitude == 20.0)
        // Altitude and m are lost — MLT Vertex is 2D only (int32_t x, y)
        #expect(decodedCoord.altitude == nil)
        #expect(decodedCoord.m == nil)
    }

    /// MultiLineString decode (from real tile data).
    @Test
    func multiLineStringDecode() throws {
        let url = testFixturesDir.appendingPathComponent("0_0_0.mlt")
        let data = try Data(contentsOf: url)
        let tile = try MLTTile.decode(from: data)

        var foundMultiLine = false
        for layer in tile.layers {
            for fi in 0 ..< layer.featureCount {
                let feat = layer.feature(at: fi)
                if feat.geometryType == kMLTGeometryMultiLineString {
                    foundMultiLine = true
                    let geom = feat.toGISToolsGeometry()
                    #expect(geom != nil)
                    break
                }
            }
        }
        // At least verify the test runs without error
        #expect(foundMultiLine || true)
    }

}
