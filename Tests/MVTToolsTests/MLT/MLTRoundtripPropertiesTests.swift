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

}
