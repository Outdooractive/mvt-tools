#if EnableMLT && EnableMLTCXX
import Foundation
import GISTools
@testable import MVTTools
import Testing

/// Cross-backend tests. These only run when both the pure Swift and the C++
/// implementations are compiled (`EnableMLTCXX` implies `EnableMLT`).
struct MLTCrossBackendTests {

    private static var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Dependencies")
            .appendingPathComponent("maplibre-tile-spec")
            .appendingPathComponent("test")
            .appendingPathComponent("expected")
            .appendingPathComponent("0x01")
            .appendingPathComponent("omt")
    }

    @Test
    func fixtureDecodeParity() throws {
        let url = Self.fixtureDirectory.appendingPathComponent("0_0_0.mlt")
        let data = try Data(contentsOf: url)

        let swift = try MLTDecoderSwift.decode(from: data, x: 0, y: 0, z: 0)
        let cxx = try MLTDecoderCXX.decode(from: data, x: 0, y: 0, z: 0)

        #expect(swift.keys.sorted() == cxx.keys.sorted())
        for name in swift.keys.sorted() {
            let swiftFeatures = try #require(swift[name]?.features)
            let cxxFeatures = try #require(cxx[name]?.features)
            #expect(swiftFeatures.count == cxxFeatures.count)
            for (swiftFeature, cxxFeature) in zip(swiftFeatures, cxxFeatures) {
                #expect(swiftFeature == cxxFeature)
            }
        }
    }

    @Test
    func swiftEncodeCXXDecode() throws {
        let layers = Self.syntheticLayers()
        let data = try #require(MLTEncoderSwift.encode(
            layers: layers,
            x: 0, y: 0, z: 0,
            projection: .noSRID))
        let decoded = try MLTDecoderCXX.decode(
            from: data, x: 0, y: 0, z: 0, projection: .noSRID)

        try Self.compare(original: layers, decoded: decoded)
    }

    @Test
    func cxxEncodeSwiftDecode() throws {
        let layers = Self.syntheticLayers()
        let data = try #require(MLTEncoderCXX.encode(
            layers: layers,
            x: 0, y: 0, z: 0,
            projection: .noSRID))
        let decoded = try MLTDecoderSwift.decode(
            from: data, x: 0, y: 0, z: 0, projection: .noSRID)

        try Self.compare(original: layers, decoded: decoded)
    }

    // MARK: - Helpers

    private static func syntheticLayers() -> [String: VectorTile.LayerContainer] {
        let point = Feature(
            Point(Coordinate3D(x: 10.0, y: 20.0, projection: .noSRID)),
            id: .uint(1),
            properties: [
                "string": "hello",
                "int": 42,
                "int32": Int32(123),
                "int64": Int64(9_000_000_000),
                "uint32": UInt32(456),
                "uint64": UInt64(9_000_000_000),
                "double": 3.25,
                "bool": true,
            ] as [String: Sendable])

        let line = Feature(
            LineString([
                Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
                Coordinate3D(x: 100.0, y: 100.0, projection: .noSRID),
                Coordinate3D(x: 200.0, y: 50.0, projection: .noSRID),
            ])!,
            id: .uint(2),
            properties: ["class": "road"] as [String: Sendable])

        let polygon = Feature(
            Polygon([
                [
                    Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
                    Coordinate3D(x: 100.0, y: 0.0, projection: .noSRID),
                    Coordinate3D(x: 100.0, y: 100.0, projection: .noSRID),
                    Coordinate3D(x: 0.0, y: 100.0, projection: .noSRID),
                    Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
                ],
                [
                    Coordinate3D(x: 25.0, y: 25.0, projection: .noSRID),
                    Coordinate3D(x: 75.0, y: 25.0, projection: .noSRID),
                    Coordinate3D(x: 75.0, y: 75.0, projection: .noSRID),
                    Coordinate3D(x: 25.0, y: 75.0, projection: .noSRID),
                    Coordinate3D(x: 25.0, y: 25.0, projection: .noSRID),
                ],
            ])!,
            id: .uint(3),
            properties: ["area": 10_000] as [String: Sendable])

        let multiPolygon = Feature(
            MultiPolygon([
                [
                    [
                        Coordinate3D(x: 200.0, y: 200.0, projection: .noSRID),
                        Coordinate3D(x: 300.0, y: 200.0, projection: .noSRID),
                        Coordinate3D(x: 300.0, y: 300.0, projection: .noSRID),
                        Coordinate3D(x: 200.0, y: 300.0, projection: .noSRID),
                        Coordinate3D(x: 200.0, y: 200.0, projection: .noSRID),
                    ],
                ],
                [
                    [
                        Coordinate3D(x: 400.0, y: 400.0, projection: .noSRID),
                        Coordinate3D(x: 500.0, y: 400.0, projection: .noSRID),
                        Coordinate3D(x: 500.0, y: 500.0, projection: .noSRID),
                        Coordinate3D(x: 400.0, y: 500.0, projection: .noSRID),
                        Coordinate3D(x: 400.0, y: 400.0, projection: .noSRID),
                    ],
                ],
            ])!,
            id: .uint(4))

        let noID = Feature(
            Point(Coordinate3D(x: 55.0, y: 66.0, projection: .noSRID)),
            properties: ["nullable": true] as [String: Sendable])

        let classes = ["alpha", "beta", "gamma"]
        let dictionaryFeatures = (0 ..< 200).map { index -> Feature in
            let x = Double(index * 10)
            let y = Double(index * 5)
            let polygon = Polygon([[
                Coordinate3D(x: x, y: y, projection: .noSRID),
                Coordinate3D(x: x + 5, y: y, projection: .noSRID),
                Coordinate3D(x: x + 5, y: y + 5, projection: .noSRID),
                Coordinate3D(x: x, y: y + 5, projection: .noSRID),
                Coordinate3D(x: x, y: y, projection: .noSRID),
            ]])!
            return Feature(
                polygon,
                properties: [
                    "class": classes[index % classes.count],
                    "name": "Name \(index % 4)",
                    "name_de": "Name DE \(index % 3)",
                    "name_en": "Name EN \(index % 5)",
                    "rank32": Int32(index % 5),
                    "rank64": Int64(index % 7),
                    "count64": UInt64(index % 3),
                ] as [String: Sendable])
        }

        let sharedVertexPolygon = Polygon([[
            Coordinate3D(x: 1000.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 1100.0, y: 1000.0, projection: .noSRID),
            Coordinate3D(x: 1100.0, y: 1100.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 1100.0, projection: .noSRID),
            Coordinate3D(x: 1000.0, y: 1000.0, projection: .noSRID),
        ]])!
        let sharedVertexFeatures = (0 ..< 50).map { index in
            Feature(
                sharedVertexPolygon,
                properties: ["rank": Int32(index)] as [String: Sendable])
        }

        let fastPFORFeatures = (0 ..< 512).map { index -> Feature in
            let x = Double((index % 32) * 20)
            let y = Double((index / 32) * 20)
            let square = Polygon([[
                Coordinate3D(x: x, y: y, projection: .noSRID),
                Coordinate3D(x: x + 10, y: y, projection: .noSRID),
                Coordinate3D(x: x + 10, y: y + 10, projection: .noSRID),
                Coordinate3D(x: x, y: y + 10, projection: .noSRID),
                Coordinate3D(x: x, y: y, projection: .noSRID),
            ]])!
            let value = UInt32(1_000_000_000) &+ UInt32(truncatingIfNeeded: index &* 2_654_435_761)
            return Feature(
                square,
                properties: [
                    "value": value,
                    "label": "highway_classification_\(index)_with_a_common_prefix",
                ] as [String: Sendable])
        }

        return [
            "mixed": VectorTile.LayerContainer(
                features: [point, line, polygon, multiPolygon, noID],
                boundingBox: nil),
            "dictionary": VectorTile.LayerContainer(
                features: dictionaryFeatures,
                boundingBox: nil),
            "shared_vertices": VectorTile.LayerContainer(
                features: sharedVertexFeatures,
                boundingBox: nil),
            "fastpfor": VectorTile.LayerContainer(
                features: fastPFORFeatures,
                boundingBox: nil),
        ]
    }

    private static func compare(
        original: [String: VectorTile.LayerContainer],
        decoded: [String: VectorTile.LayerContainer]
    ) throws {
        #expect(original.keys.sorted() == decoded.keys.sorted())
        for name in original.keys.sorted() {
            let originalFeatures = try #require(original[name]?.features)
            let decodedFeatures = try #require(decoded[name]?.features)
            #expect(originalFeatures.count == decodedFeatures.count)
            for (originalFeature, decodedFeature) in zip(originalFeatures, decodedFeatures) {
                #expect(originalFeature.geometry?.type == decodedFeature.geometry?.type)
                try Self.compareGeometry(originalFeature.geometry, decodedFeature.geometry)
                #expect(originalFeature.id == decodedFeature.id)
                #expect(Self.propertiesEqual(originalFeature.properties, decodedFeature.properties))
            }
        }
    }

    private static func compareGeometry(
        _ lhs: GeoJsonGeometry?,
        _ rhs: GeoJsonGeometry?
    ) throws {
        guard let lhs, let rhs else {
            #expect(lhs == nil && rhs == nil)
            return
        }

        switch (lhs, rhs) {
        case let (lhs as Polygon, rhs as Polygon):
            #expect(lhs.rings.count == rhs.rings.count)
            #expect(canonicalRings(lhs.rings.map(\.coordinates)) == canonicalRings(rhs.rings.map(\.coordinates)))

        case let (lhs as MultiPolygon, rhs as MultiPolygon):
            #expect(lhs.coordinates.count == rhs.coordinates.count)
            for (lhsPolygon, rhsPolygon) in zip(lhs.coordinates, rhs.coordinates) {
                #expect(lhsPolygon.count == rhsPolygon.count)
                #expect(canonicalRings(lhsPolygon) == canonicalRings(rhsPolygon))
            }

        default:
            #expect(lhs.allCoordinates == rhs.allCoordinates)
        }
    }

    private static func canonicalRings(
        _ rings: [[Coordinate3D]]
    ) -> [[String]] {
        rings.map(canonicalRing).sorted { $0.joined() < $1.joined() }
    }

    private static func canonicalRing(_ ring: [Coordinate3D]) -> [String] {
        var coordinates = ring
        if coordinates.count > 1, coordinates.first == coordinates.last {
            coordinates.removeLast()
        }
        guard !coordinates.isEmpty else { return [] }

        let keys = coordinates.map { "\($0.x),\($0.y)" }
        let count = keys.count
        let start = keys.indices.min { keys[$0] < keys[$1] } ?? 0
        let forward = (0 ..< count).map { keys[(start + $0) % count] }
        let backward = (0 ..< count).map { keys[(start - $0 + count) % count] }
        return forward.lexicographicallyPrecedes(backward) ? forward : backward
    }

    private static func numericValue(_ value: any Sendable) -> Double? {
        switch value {
        case let value as Int: return Double(value)
        case let value as Int8: return Double(value)
        case let value as Int16: return Double(value)
        case let value as Int32: return Double(value)
        case let value as Int64: return Double(value)
        case let value as UInt: return Double(value)
        case let value as UInt8: return Double(value)
        case let value as UInt16: return Double(value)
        case let value as UInt32: return Double(value)
        case let value as UInt64: return Double(value)
        case let value as Float: return Double(value)
        case let value as Double: return value
        default: return nil
        }
    }

    private static func propertiesEqual(
        _ lhs: [String: Sendable],
        _ rhs: [String: Sendable]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (key, lhsValue) in lhs {
            guard let rhsValue = rhs[key] else { return false }
            if let lhsValue = lhsValue as? Bool, let rhsValue = rhsValue as? Bool {
                if lhsValue != rhsValue { return false }
            }
            else if let lhsValue = lhsValue as? String, let rhsValue = rhsValue as? String {
                if lhsValue != rhsValue { return false }
            }
            else if let lhsNumber = numericValue(lhsValue), let rhsNumber = numericValue(rhsValue) {
                if lhsNumber != rhsNumber { return false }
            }
            else {
                return false
            }
        }
        return true
    }

}

#endif
