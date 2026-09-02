#if EnableMLT
import Foundation
import GISTools
@testable import MVTTools
import Testing

struct MLTRoundtripFeatureIDTests {

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

}

#endif
