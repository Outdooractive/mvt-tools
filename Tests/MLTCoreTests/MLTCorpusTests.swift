#if EnableMLT
import Foundation
@testable import MLTCore
import Testing

/// Conformance tests against the upstream MLT `0x01` corpus.
struct MLTCorpusTests {

    private static var corpusRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Dependencies")
            .appendingPathComponent("maplibre-tile-spec")
            .appendingPathComponent("test")
            .appendingPathComponent("expected")
            .appendingPathComponent("0x01")
    }

    @Test
    func decodesUpstreamCorpusWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["MLT_FULL_CORPUS"] == "1",
              FileManager.default.fileExists(atPath: Self.corpusRoot.path)
        else {
            return
        }

        let enumerator = try #require(
            FileManager.default.enumerator(
                at: Self.corpusRoot,
                includingPropertiesForKeys: nil))

        var count = 0
        for case let url as URL in enumerator where url.pathExtension == "mlt" {
            let parts = url.deletingPathExtension().lastPathComponent
                .split(separator: "_")
                .compactMap { Int($0) }
            guard parts.count >= 3 else { continue }

            count += 1
            let data = try Data(contentsOf: url)
            let layers = try MLTDecoderCore.decode(data)
            for layer in layers {
                #expect(!layer.name.isEmpty)
                #expect(layer.featureCount > 0)
            }
        }

        #expect(count > 0)
    }

}

#endif
