import Foundation
import GISTools
@testable import MVTTools
import Testing

struct MLTRoundtripPropertiesTests {

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

    // MARK: - Integer width: INT_32 vs INT_64 column selection
    //
    // Small integer values MUST be encoded as INT_32 so that the MLT JS/WASM
    // decoder produces JavaScript Numbers (not BigInts).  maplibre-gl-js
    // expression comparisons (`[">", "prop", 10000]`) throw a TypeError when a
    // BigInt is compared with a Number, silently dropping features from
    // rendering.  See https://github.com/maplibre/maplibre-tile-spec for the
    // type mapping: INT_32 → Number, INT_64 → BigInt.

    @Test
    func smallIntegerEncodesAsInt32() throws {
        let coord = Coordinate3D(latitude: 10.0, longitude: 20.0)
        let feature = Feature(Point(coord), properties: [
            "small": 42,
            "boundary": Int(Int32.max),
            "negative": -100,
        ] as [String: Sendable])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)

        // Values round-trip correctly.
        #expect(feat.properties["small"] as? Int64 == 42)
        #expect(feat.properties["boundary"] as? Int64 == Int64(Int32.max))
        #expect(feat.properties["negative"] as? Int64 == -100)

        // Verify the column type in the binary is INT_32 (typeCode 16/17),
        // not INT_64 (typeCode 20/21).  We inspect the raw metadata bytes,
        // filtering out ID (0–3) and GEOMETRY (4) columns.
        let rawData = data.isGzipped ? (try? data.gunzipped()) ?? data : data
        let columnTypes = MLTTestHelper.columnTypeCodes(in: rawData, layerName: "test")
            .filter { $0 >= 10 } // Exclude ID (0–3) and GEOMETRY (4)
        // INT_32 non-nullable = 16, INT_32 nullable = 17
        for typeCode in columnTypes {
            #expect(typeCode == 16 || typeCode == 17, "Expected INT_32 column but got typeCode \(typeCode)")
        }
    }

    @Test
    func largeIntegerEncodesAsInt64() throws {
        let coord = Coordinate3D(latitude: 10.0, longitude: 20.0)
        let largeValue = Int64(Int32.max) + 1
        let feature = Feature(Point(coord), properties: [
            "big": Int(largeValue),
        ] as [String: Sendable])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [feature], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let feat = try #require(decoded["test"]?.features.first)

        #expect(feat.properties["big"] as? Int64 == largeValue)

        // Verify the column type is INT_64 (typeCode 20/21).
        let rawData = data.isGzipped ? (try? data.gunzipped()) ?? data : data
        let columnTypes = MLTTestHelper.columnTypeCodes(in: rawData, layerName: "test")
        // INT_64 non-nullable = 20, INT_64 nullable = 21
        let hasInt64 = columnTypes.contains { $0 == 20 || $0 == 21 }
        #expect(hasInt64, "Expected at least one INT_64 column for large value")
    }

    @Test
    func mixedInt32AndInt64PromotesToInt64() throws {
        let coord = Coordinate3D(latitude: 10.0, longitude: 20.0)
        let f1 = Feature(Point(coord), properties: ["val": 42] as [String: Sendable])
        let f2 = Feature(Point(coord), properties: ["val": Int(Int64(Int32.max) + 1)] as [String: Sendable])

        guard let data = MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: [f1, f2], boundingBox: nil)],
            x: 0, y: 0, z: 0, projection: .noSRID)
        else { return }
        let decoded = try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let features = try #require(decoded["test"]?.features)

        #expect(features.count == 2)
        // The C++ encoder promotes the column to INT_64 when any value is INT_64.
        // Both values should still round-trip correctly.
        #expect(features[0].properties["val"] as? Int64 == 42)
        #expect(features[1].properties["val"] as? Int64 == Int64(Int32.max) + 1)
    }

}
