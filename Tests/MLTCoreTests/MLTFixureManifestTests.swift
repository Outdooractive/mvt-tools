#if EnableMLT
import Foundation
@testable import MLTCore
import Testing

struct MLTFixureManifestTests {

    private struct Manifest: Decodable {
        let upstream: Upstream
        let checksum: String
        let fixtures: [Fixture]

        struct Upstream: Decodable {
            let repository: String
            let revision: String
            let path: String
        }

        struct Fixture: Decodable {
            let file: String
            let bytes: Int
            let checksum: String
            let layers: [String: Int]
        }
    }

    private static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }

    @Test
    func verifiesFixtureManifest() throws {
        let manifestData = try Data(
            contentsOf: Self.fixturesDirectory.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)

        #expect(manifest.checksum == "fnv1a64")
        #expect(!manifest.upstream.revision.isEmpty)
        #expect(!manifest.fixtures.isEmpty)

        for fixture in manifest.fixtures {
            let data = try Data(
                contentsOf: Self.fixturesDirectory.appendingPathComponent(fixture.file))
            #expect(data.count == fixture.bytes)
            #expect(fnv1a64(data) == fixture.checksum)

            let layers = try MLTDecoderCore.decode(data)
            let layerCounts = Dictionary(
                uniqueKeysWithValues: layers.map { ($0.name, $0.featureCount) })
            #expect(layerCounts == fixture.layers)
        }
    }

    private func fnv1a64(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

}
#endif
