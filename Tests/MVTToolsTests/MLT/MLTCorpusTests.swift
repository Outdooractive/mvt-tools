#if EnableMLT
import Foundation
@testable import MVTTools
import Testing

/// Conformance tests against the upstream MLT `0x01` corpus.
struct MLTCorpusTests {

    private static var corpusRoot: URL {
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
    }

    @Test
    func decodesUpstreamCorpus() throws {
        guard FileManager.default.fileExists(atPath: Self.corpusRoot.path) else {
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
            let decoded = try MLTDecoderSwift.decode(
                from: data,
                x: parts[1],
                y: parts[2],
                z: parts[0])

            for (name, container) in decoded {
                #expect(!name.isEmpty)
                #expect(container.features.isNotEmpty)
            }
        }

        #expect(count > 0)
    }

}

#endif
