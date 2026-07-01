import Foundation
import GISTools
import MLT
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

struct MLTDecoderTests {

    /// Parses tile coordinates from a fixture filename like "9_264_342.mlt".
    private static func parseTileCoords(from url: URL) -> (z: Int, x: Int, y: Int) {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "_").map { Int($0)! }
        return (parts[0], parts[1], parts[2])
    }

    /// Returns the bounding boxes of the tile and all valid adjacent neighbours.
    /// MLT buffer zones can extend coordinates into adjacent tiles.
    /// At z=0 the single tile covers the whole world, so only its own box is used.
    private static func tileBoxes(
        x: Int, y: Int, z: Int, projection: Projection
    ) -> [BoundingBox] {
        let tile = MapTile(x: x, y: y, z: z)
        if z == 0 {
            return [tile.boundingBox(projection: projection)]
        }
        return tile.neighbours.map {
            $0.boundingBox(projection: projection)
        }
    }

    /// Checks every coordinate of `features` lies within at least one `boxes`.
    private static func expectAllCoordsInBounds(
        _ features: [Feature],
        boxes: [BoundingBox]
    ) {
        for feat in features {
            for coord in feat.geometry.allCoordinates {
                let ok = boxes.contains { $0.contains(coord) }
                #expect(ok)
            }
        }
    }

    /// Decodes a real MLT tile with layers and features.
    @Test
    func decodeRealTile() throws {
        let url = testFixturesDir.appendingPathComponent("0_0_0.mlt")
        let data = try Data(contentsOf: url)
        #expect(data.isEmpty == false)

        let (z, x, y) = Self.parseTileCoords(from: url)
        let decoded = try MLTDecoder.decode(
            from: data, x: x, y: y, z: z, projection: .epsg4326)
        #expect(decoded.isEmpty == false)

        let boxes = Self.tileBoxes(x: x, y: y, z: z, projection: .epsg4326)
        for (name, features) in decoded {
            #expect(name.isEmpty == false)
            #expect(features.isEmpty == false)
            Self.expectAllCoordsInBounds(features, boxes: boxes)
        }
    }

    /// First feature in each layer has valid geometry and properties.
    @Test
    func firstFeatureProperties() throws {
        let url = testFixturesDir.appendingPathComponent("9_264_342.mlt")
        let data = try Data(contentsOf: url)

        let (z, x, y) = Self.parseTileCoords(from: url)
        let decoded = try MLTDecoder.decode(
            from: data, x: x, y: y, z: z, projection: .epsg4326)
        let boxes = Self.tileBoxes(x: x, y: y, z: z, projection: .epsg4326)

        for (_, features) in decoded {
            let feat = try #require(features.first)
            #expect(feat.geometry.type != .invalid)
            #expect(feat.properties.isEmpty == false)
            Self.expectAllCoordsInBounds([feat], boxes: boxes)
        }
    }

    /// All features in real tiles decode to valid GISTools features.
    @Test
    func convertAllToGISTools() throws {
        let url = testFixturesDir.appendingPathComponent("7_66_84.mlt")
        let data = try Data(contentsOf: url)

        let (z, x, y) = Self.parseTileCoords(from: url)
        let decoded = try MLTDecoder.decode(
            from: data, x: x, y: y, z: z, projection: .epsg4326)
        let boxes = Self.tileBoxes(x: x, y: y, z: z, projection: .epsg4326)

        var totalFeatures = 0
        for (_, features) in decoded {
            for feat in features {
                totalFeatures += 1
                #expect(feat.geometry.type != .invalid)
                Self.expectAllCoordsInBounds([feat], boxes: boxes)
            }
        }
        #expect(totalFeatures > 0)
    }

    /// Decoding invalid data throws.
    @Test
    func invalidDataFails() throws {
        let data = Data([0x00, 0x01, 0x02, 0x03])
        #expect(throws: MLTDecoderError.decodeFailed) {
            try MLTDecoder.decode(from: data, x: 0, y: 0, z: 0)
        }
    }

    /// Decoding empty data returns an empty dictionary.
    @Test
    func emptyDataFails() throws {
        let decoded = try MLTDecoder.decode(from: Data(), x: 0, y: 0, z: 0)
        #expect(decoded.isEmpty)
    }

    /// A layer allowlist restricts which layers are returned.
    @Test
    func layerAllowlistFiltersCorrectly() throws {
        let url = testFixturesDir.appendingPathComponent("7_66_84.mlt")
        let data = try Data(contentsOf: url)
        let (z, x, y) = Self.parseTileCoords(from: url)

        let all = try MLTDecoder.decode(from: data, x: x, y: y, z: z, projection: .noSRID)
        #expect(all.isEmpty == false)

        let filtered = try MLTDecoder.decode(
            from: data, x: x, y: y, z: z, projection: .noSRID,
            layerAllowlist: [all.keys.first!])
        #expect(filtered.count == 1)
        #expect(filtered.keys.first == all.keys.first)
    }

    /// An empty allowlist returns no layers.
    @Test
    func emptyAllowlistReturnsNoLayers() throws {
        let url = testFixturesDir.appendingPathComponent("7_66_84.mlt")
        let data = try Data(contentsOf: url)
        let (z, x, y) = Self.parseTileCoords(from: url)

        let decoded = try MLTDecoder.decode(
            from: data, x: x, y: y, z: z, projection: .noSRID,
            layerAllowlist: [])
        #expect(decoded.isEmpty)
    }

}
