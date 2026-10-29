#if EnableMLT && !EnableMLTCXX
import Foundation
import GISTools
@testable import MVTTools
import Testing

struct MLTEncodingOptionsTests {

    @Test
    func plainMLTEncodingOptionsRoundTrip() throws {
        let ring = [
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 100.0, y: 0.0, projection: .noSRID),
            Coordinate3D(x: 100.0, y: 100.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 100.0, projection: .noSRID),
            Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
        ]
        let polygon = try #require(Polygon([ring]))
        let features = (0 ..< 50).map { index in
            Feature(
                polygon,
                properties: [
                    "class": index % 2 == 0 ? "primary" : "secondary",
                    "rank": Int32(index),
                ] as [String: Sendable])
        }

        let options = VectorTile.ExportOptions(mlt: .plain)
        let data = try #require(MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: features, boundingBox: nil)],
            x: 0, y: 0, z: 0,
            projection: .noSRID,
            options: options))
        let decoded = try MLTDecoder.decode(
            from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        let layer = try #require(decoded["test"])
        #expect(layer.features.count == features.count)
        #expect(layer.features.first?.properties["class"] as? String == "primary")
    }

    @Test
    func disablingFSSTStillRoundTrips() throws {
        let options = VectorTile.ExportOptions(
            mlt: VectorTile.ExportOptions.MLTEncodingOptions(useFSST: false))
        let features = (0 ..< 100).map { index in
            Feature(
                Point(Coordinate3D(x: Double(index), y: 0.0, projection: .noSRID)),
                properties: ["name": "prefix_\(index)_suffix"] as [String: Sendable])
        }

        let data = try #require(MLTEncoder.encode(
            layers: ["test": VectorTile.LayerContainer(features: features, boundingBox: nil)],
            x: 0, y: 0, z: 0,
            projection: .noSRID,
            options: options))
        let decoded = try MLTDecoder.decode(
            from: data, x: 0, y: 0, z: 0, projection: .noSRID)
        #expect(decoded["test"]?.features.count == features.count)
    }

    @Test
    func defaultOptionsMatchCXXEncoderConfig() {
        let options = VectorTile.ExportOptions()
        #expect(options.mlt.useStringDictionaries)
        #expect(options.mlt.useSharedStringDictionaries)
        #expect(options.mlt.useFSST)
        #expect(options.mlt.useFastPFOR == false)
        #expect(options.mlt.useVertexDictionaries)
        #expect(options.mlt.useIntegerDeltaRLE)
    }

    @Test
    func enablingFastPFORStillRoundTrips() throws {
        let options = VectorTile.ExportOptions(
            mlt: VectorTile.ExportOptions.MLTEncodingOptions(useFastPFOR: true))
        let features = (0 ..< 500).map { index in
            Feature(
                Point(Coordinate3D(x: Double(index), y: 0.0, projection: .noSRID)),
                properties: ["rank": Int64(1_000_000_000 + index * 7919)] as [String: Sendable])
        }

        let layers = ["test": VectorTile.LayerContainer(features: features, boundingBox: nil)]
        let defaultData = try #require(MLTEncoder.encode(
            layers: layers,
            x: 0, y: 0, z: 0,
            projection: .noSRID,
            options: VectorTile.ExportOptions()))
        let data = try #require(MLTEncoder.encode(
            layers: layers,
            x: 0, y: 0, z: 0,
            projection: .noSRID,
            options: options))
        let defaultLayer = try #require(try MLTDecoder.decode(
            from: defaultData,
            x: 0, y: 0, z: 0,
            projection: .noSRID)["test"])
        let layer = try #require(try MLTDecoder.decode(
            from: data,
            x: 0, y: 0, z: 0,
            projection: .noSRID)["test"])
        #expect(layer.features == defaultLayer.features)
        #expect(data.count <= defaultData.count)
    }

    @Test
    func disablingFeaturesPreservesContent() throws {
        let polygons = try (0 ..< 20).map { index -> Polygon in
            let x = Double(index * 10)
            let y = Double(index * 10)
            let ring = [
                Coordinate3D(x: x, y: y, projection: .noSRID),
                Coordinate3D(x: x + 8.0, y: y, projection: .noSRID),
                Coordinate3D(x: x + 8.0, y: y + 8.0, projection: .noSRID),
                Coordinate3D(x: x, y: y + 8.0, projection: .noSRID),
                Coordinate3D(x: x, y: y, projection: .noSRID),
            ]
            return try #require(Polygon([ring]))
        }
        let features = (0 ..< 400).map { index -> Feature in
            let properties: [String: Sendable] = [
                "class": index % 3 == 0
                    ? "primary"
                    : (index % 3 == 1 ? "secondary" : "tertiary"),
                "name": "common_name_prefix_\(index)_with_a_long_suffix",
                "rank": Int32(index * 7),
                "@id": Int64(1_000_000 + index),
                "visible": index % 2 == 0,
                "ratio": Double(index) / 400.0,
            ]
            return Feature(polygons[index % polygons.count], properties: properties)
        }

        let layers = ["test": VectorTile.LayerContainer(features: features, boundingBox: nil)]
        let referenceData = try #require(MLTEncoder.encode(
            layers: layers,
            x: 0, y: 0, z: 0,
            projection: .noSRID,
            options: VectorTile.ExportOptions()))
        let reference = try #require(try MLTDecoder.decode(
            from: referenceData,
            x: 0, y: 0, z: 0,
            projection: .noSRID)["test"])

        let variants: [(String, VectorTile.ExportOptions.MLTEncodingOptions)] = [
            ("stringDictionaries", .init(useStringDictionaries: false)),
            ("sharedStringDictionaries", .init(useSharedStringDictionaries: false)),
            ("FSST", .init(useFSST: false)),
            ("vertexDictionaries", .init(useVertexDictionaries: false)),
            ("integerDeltaRLE", .init(useIntegerDeltaRLE: false)),
            ("plain", .plain),
        ]

        for (name, mltOptions) in variants {
            let data = try #require(
                MLTEncoder.encode(
                    layers: layers,
                    x: 0, y: 0, z: 0,
                    projection: .noSRID,
                    options: VectorTile.ExportOptions(mlt: mltOptions)),
                "\(name): encoding failed")
            let layer = try #require(
                try MLTDecoder.decode(
                    from: data,
                    x: 0, y: 0, z: 0,
                    projection: .noSRID)["test"],
                "\(name): missing layer")
            #expect(layer.features == reference.features, "\(name): content changed")
            #expect(referenceData.count <= data.count, "\(name): default encoding is not minimal")
        }
    }

}
#endif
