#if EnableMLT
import Foundation
import GISTools
@testable import MVTTools
import Testing

struct MLTRoundtripLayerTests {

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

}

#endif
