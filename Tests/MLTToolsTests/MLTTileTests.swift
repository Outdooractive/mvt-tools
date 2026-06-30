import CMLT
import Foundation
import GISTools
import MLTTools
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
        // Use a small tile to keep test fast
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

    /// Tests round-trip: decode and inspect coordinate counts.
    @Test
    func coordinateAccess() throws {
        let url = testFixturesDir.appendingPathComponent("9_264_342.mlt")
        let data = try Data(contentsOf: url)
        let tile = try MLTTile.decode(from: data)

        for layer in tile.layers {
            for fi in 0 ..< min(layer.featureCount, 5) {
                let feat = layer.feature(at: fi)
                let gt = Int(feat.geometryType)

                // All geometry types except Point should have multiple coordinates
                let geom = feat.toGISToolsGeometry()
                if let geom, gt != kMLTGeometryPoint {
                    #expect(geom.allCoordinates.count > 0)
                }
            }
        }
    }

}
