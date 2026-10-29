#if EnableMLT
import Foundation
@testable import MLTCore
import Testing

struct MLTEncoderCoreTests {

    @Test
    func repeatedStringsUseDictionaryAndRoundTrip() throws {
        let strings = (0 ..< 120).map { index -> String? in
            switch index % 4 {
            case 0: return "motorway"
            case 1: return "primary"
            case 2: return "residential"
            default: return nil
            }
        }

        let data = try encode(strings: strings)
        let layers = try MLTDecoderCore.decode(data)
        let layer = try #require(layers.first)

        #expect(layer.name == "test")
        #expect(layer.featureCount == strings.count)
        #expect(layer.properties["class"]?.count == strings.count)

        for (index, expected) in strings.enumerated() {
            if let expected {
                #expect(layer.properties["class"]?[index] == .string(expected))
            }
            else {
                #expect(layer.properties["class"]?[index] == nil)
            }
        }
    }

    @Test
    func dictionaryIsSmallerThanPlainStrings() throws {
        let repeated = (0 ..< 200).map { index -> String? in
            ["alpha", "beta", "gamma"][index % 3]
        }
        let unique = (0 ..< 200).map { index -> String? in
            "value-\(index)"
        }

        let repeatedData = try encode(strings: repeated)
        let uniqueData = try encode(strings: unique)
        #expect(repeatedData.count < uniqueData.count)
    }

    @Test
    func plainEncoderOptionsRoundTrip() throws {
        let features = (0 ..< 300).map { index -> MLTEncodableFeature in
            let x = Int32(index % 10)
            let y = Int32(index / 10)
            let ring = [
                MLTTileCoordinate(x: x, y: y),
                MLTTileCoordinate(x: x + 5, y: y),
                MLTTileCoordinate(x: x + 5, y: y + 5),
                MLTTileCoordinate(x: x, y: y + 5),
                MLTTileCoordinate(x: x, y: y),
            ]
            let properties: [String: any Sendable] = [
                "name": "common_prefix_\(index)_with_a_suffix",
                "value": UInt32(1_000_000 + index),
            ]
            return MLTEncodableFeature(
                id: nil,
                hasNumericID: false,
                geometry: .polygon([ring]),
                properties: properties)
        }

        let layers = [
            MLTEncodableLayer(name: "test", extent: 4096, features: features),
        ]
        let data = try MLTEncoderCore.encode(layers: layers, options: .plain)
        let decoded = try MLTDecoderCore.decode(data)
        guard let layer = decoded.first else {
            Issue.record("Missing decoded layer")
            return
        }
        #expect(layer.featureCount == features.count)
        #expect(layer.properties["name"]?.count == features.count)
        #expect(layer.properties["value"]?.count == features.count)
    }

    @Test
    func sharedStringFSSTRoundTrip() throws {
        let features = (0 ..< 200).map { index -> MLTEncodableFeature in
            let properties: [String: any Sendable] = [
                "name": "shared_name_prefix_\(index)_with_a_common_suffix",
                "name_de": "shared_name_prefix_de_\(index)_with_a_common_suffix",
                "name_en": "shared_name_prefix_en_\(index)_with_a_common_suffix",
            ]
            return MLTEncodableFeature(
                id: nil,
                hasNumericID: false,
                geometry: .point(MLTTileCoordinate(x: Int32(index), y: 0)),
                properties: properties)
        }

        let data = try MLTEncoderCore.encode(layers: [
            MLTEncodableLayer(name: "test", extent: 4096, features: features),
        ])
        let layer = try #require(MLTDecoderCore.decode(data).first)
        for index in 0 ..< features.count {
            #expect(layer.properties["name"]?[index] == .string("shared_name_prefix_\(index)_with_a_common_suffix"))
            #expect(layer.properties["name_de"]?[index] == .string("shared_name_prefix_de_\(index)_with_a_common_suffix"))
            #expect(layer.properties["name_en"]?[index] == .string("shared_name_prefix_en_\(index)_with_a_common_suffix"))
        }
    }

    @Test
    func repeatedUInt32PropertiesRoundTrip() throws {
        let features = (0 ..< 200).map { index -> MLTEncodableFeature in
            MLTEncodableFeature(
                id: nil,
                hasNumericID: false,
                geometry: .point(MLTTileCoordinate(x: Int32(index), y: 0)),
                properties: ["rank": UInt32(index % 5)])
        }

        let data = try MLTEncoderCore.encode(layers: [
            MLTEncodableLayer(name: "test", extent: 4096, features: features),
        ])
        let layer = try #require(MLTDecoderCore.decode(data).first)
        for index in 0 ..< features.count {
            #expect(layer.properties["rank"]?[index] == .uint32(UInt32(index % 5)))
        }
    }

    @Test
    func repeatedSignedAnd64BitPropertiesRoundTrip() throws {
        let features = (0 ..< 120).map { index -> MLTEncodableFeature in
            let i32 = Int32((index % 5) - 2)
            let i64 = Int64(9_000_000_000) + Int64(index % 7)
            let u64 = UInt64(9_000_000_000) + UInt64(index % 3)
            let properties: [String: any Sendable] = [
                "i32": i32,
                "i64": i64,
                "u64": u64,
            ]
            return MLTEncodableFeature(
                id: nil,
                hasNumericID: false,
                geometry: .point(MLTTileCoordinate(x: Int32(index), y: 0)),
                properties: properties)
        }

        let data = try MLTEncoderCore.encode(layers: [
            MLTEncodableLayer(name: "test", extent: 4096, features: features),
        ])
        let layer = try #require(MLTDecoderCore.decode(data).first)

        for index in 0 ..< features.count {
            #expect(layer.properties["i32"]?[index] == MLTValue.int32(Int32((index % 5) - 2)))
            #expect(layer.properties["i64"]?[index] == MLTValue.int64(Int64(9_000_000_000) + Int64(index % 7)))
            #expect(layer.properties["u64"]?[index] == MLTValue.uint64(UInt64(9_000_000_000) + UInt64(index % 3)))
        }
    }

    @Test
    func fsstEncoderRoundTrip() throws {
        let strings = Array(repeating: [
            "motorway_link",
            "motorway",
            "primary_link",
            "primary",
            "residential",
            "residential_link",
            "secondary",
            "secondary_link",
            "service",
            "tertiary",
        ], count: 50).flatMap { $0 }
        let result = try #require(MLTFSSTEncoder.encode(strings))
        let decoded = try MLTFSST.decode(
            symbols: result.symbols,
            symbolLengths: result.symbolLengths,
            compressedData: result.compressedData,
            decompressedLength: result.decompressedLength)
        #expect(decoded == Array(strings.joined().utf8))
    }

    @Test
    func fastPFORRoundTrip() throws {
        let values = (0 ..< 512).map { UInt32(1_000_000 + $0 * 17) }
        let payload = try #require(MLTFastPFOREncoder.encode(values))
        var reader = MLTByteReader(payload)
        let decoded = try MLTFastPFOR.decode(
            from: &reader,
            byteLength: payload.count,
            numValues: values.count)
        #expect(decoded == values)
        #expect(reader.isAtEnd)
    }

    @Test
    func fastPFORExceptionRoundTrip() throws {
        let values = (0 ..< 512).map { index -> UInt32 in
            index % 100 == 0 ? 0xF000_0000 : UInt32(index)
        }
        let payload = try #require(MLTFastPFOREncoder.encode(values))
        var reader = MLTByteReader(payload)
        let decoded = try MLTFastPFOR.decode(
            from: &reader,
            byteLength: payload.count,
            numValues: values.count)
        #expect(decoded == values)
    }

    @Test
    func mortonCodesRoundTrip() throws {
        let vertices = [
            MLTTileCoordinate(x: 0, y: 0),
            MLTTileCoordinate(x: 10, y: 20),
            MLTTileCoordinate(x: -5, y: 3),
            MLTTileCoordinate(x: 100, y: 200),
        ]
        let settings = try #require(MLTMortonEncoder.settings(for: vertices))
        for vertex in vertices {
            let code = MLTMortonEncoder.code(
                x: vertex.x, y: vertex.y, settings: settings)
            let x = MLTMorton.decode(code, numBits: settings.bits) &- settings.coordinateShift
            let y = MLTMorton.decode(code >> 1, numBits: settings.bits) &- settings.coordinateShift
            #expect(x == vertex.x)
            #expect(y == vertex.y)
        }
    }

    @Test
    func repeatedVerticesRoundTrip() throws {
        let ring = [
            MLTTileCoordinate(x: 0, y: 0),
            MLTTileCoordinate(x: 100, y: 0),
            MLTTileCoordinate(x: 100, y: 100),
            MLTTileCoordinate(x: 0, y: 100),
            MLTTileCoordinate(x: 0, y: 0),
        ]
        let features = (0 ..< 100).map { index in
            MLTEncodableFeature(
                id: nil,
                hasNumericID: false,
                geometry: .polygon([ring]),
                properties: ["rank": Int32(index)])
        }

        let data = try MLTEncoderCore.encode(layers: [
            MLTEncodableLayer(name: "test", extent: 4096, features: features),
        ])
        let layer = try #require(MLTDecoderCore.decode(data).first)
        #expect(layer.featureCount == features.count)
        for geometry in layer.geometries {
            guard case let .polygon(rings) = geometry else {
                Issue.record("Expected a polygon")
                continue
            }
            #expect(rings == [ring])
        }
    }

    @Test
    func relatedStringColumnsUseSharedDictionary() throws {
        let features = (0 ..< 80).map { index -> MLTEncodableFeature in
            MLTEncodableFeature(
                id: nil,
                hasNumericID: false,
                geometry: .point(MLTTileCoordinate(x: Int32(index), y: 0)),
                properties: [
                    "name": "Name \(index % 4)",
                    "name_de": "Name DE \(index % 3)",
                    "name_en": "Name EN \(index % 5)",
                ])
        }

        let data = try MLTEncoderCore.encode(layers: [
            MLTEncodableLayer(name: "test", extent: 4096, features: features),
        ])
        let layers = try MLTDecoderCore.decode(data)
        let layer = try #require(layers.first)

        #expect(layer.properties["name"]?.count == features.count)
        #expect(layer.properties["name_de"]?.count == features.count)
        #expect(layer.properties["name_en"]?.count == features.count)

        for index in 0 ..< features.count {
            #expect(layer.properties["name"]?[index] == .string("Name \(index % 4)"))
            #expect(layer.properties["name_de"]?[index] == .string("Name DE \(index % 3)"))
            #expect(layer.properties["name_en"]?[index] == .string("Name EN \(index % 5)"))
        }
    }

    @Test
    func uniqueStringsRemainRoundTrippable() throws {
        let strings = (0 ..< 100).map { "value-\($0)" }
        let data = try encode(strings: strings)
        let layers = try MLTDecoderCore.decode(data)
        let layer = try #require(layers.first)

        for (index, expected) in strings.enumerated() {
            #expect(layer.properties["class"]?[index] == .string(expected))
        }
    }

    @Test
    func singleStringAndEmptyStringRoundTrip() throws {
        for strings in [["only"], [""], ["", "", ""], ["a", ""]] {
            let data = try encode(strings: strings)
            let layers = try MLTDecoderCore.decode(data)
            let layer = try #require(layers.first)
            for (index, expected) in strings.enumerated() {
                #expect(layer.properties["class"]?[index] == .string(expected))
            }
        }
    }

    private func encode(strings: [String?]) throws -> Data {
        let features = strings.enumerated().map { index, string in
            MLTEncodableFeature(
                id: nil,
                hasNumericID: false,
                geometry: .point(MLTTileCoordinate(x: Int32(index), y: 0)),
                properties: string.map { ["class": $0] } ?? [:])
        }
        return try MLTEncoderCore.encode(layers: [
            MLTEncodableLayer(name: "test", extent: 4096, features: features),
        ])
    }

}

#endif
