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
        let layer = try #require(try MLTDecoderCore.decode(data).first)
        for index in 0 ..< features.count {
            #expect(layer.properties["rank"]?[index] == .uint32(UInt32(index % 5)))
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
