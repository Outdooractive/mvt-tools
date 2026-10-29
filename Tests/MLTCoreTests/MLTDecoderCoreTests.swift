#if EnableMLT
import Foundation
@testable import MLTCore
import Testing

struct MLTDecoderCoreTests {

    private static var v2Tile: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Dependencies")
            .appendingPathComponent("maplibre-tile-spec")
            .appendingPathComponent("test")
            .appendingPathComponent("expected")
            .appendingPathComponent("0x02")
            .appendingPathComponent("omt")
            .appendingPathComponent("0_0_0.mlt")
    }

    @Test
    func rejectsExperimentalV2Tile() throws {
        guard FileManager.default.fileExists(atPath: Self.v2Tile.path) else {
            return
        }

        let data = try Data(contentsOf: Self.v2Tile)
        #expect(throws: MLTError.unsupported("MLT tag 0x02")) {
            _ = try MLTDecoderCore.decode(data)
        }
    }

}
#endif
