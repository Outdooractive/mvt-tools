import Foundation
import MVTTools
import Testing

#if EnableMLT && !EnableMLTCXX
struct MLTEncoderOptionsCommandTests {

    private func exportMLT(
        _ mltOptions: [String] = [],
        verbose: Bool = false
    ) throws -> (url: URL, output: String) {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mlt_options_\(UUID().uuidString).mlt")
        var args = [
            "export", mvtPath,
            "-O", "mlt",
            "-o", outUrl.path,
            "-x", "8716", "-y", "8015", "-z", "14",
            "-oC", "0",
            "--force-overwrite",
        ]
        args.append(contentsOf: mltOptions)
        if verbose {
            args.append("--verbose")
        }
        let output = try runCLI(args: args)
        return (outUrl, output)
    }

    @Test(.timeLimit(.minutes(1)))
    func plainMLTOutputIsLargerThanDefault() throws {
        let defaultResult = try exportMLT()
        defer { try? FileManager.default.removeItem(at: defaultResult.url) }
        let plainResult = try exportMLT(["--mlt-plain"])
        defer { try? FileManager.default.removeItem(at: plainResult.url) }

        let defaultData = try Data(contentsOf: defaultResult.url)
        let plainData = try Data(contentsOf: plainResult.url)
        #expect(defaultData.count < plainData.count)

        let defaultTile = try VectorTile(mltData: defaultData, x: 8716, y: 8015, z: 14)
        let plainTile = try VectorTile(mltData: plainData, x: 8716, y: 8015, z: 14)
        #expect(defaultTile.layerNames == plainTile.layerNames)
        #expect(
            defaultTile.layerNames.allSatisfy {
                defaultTile.features(for: $0).count == plainTile.features(for: $0).count
            })
    }

    @Test(.timeLimit(.minutes(1)))
    func verboseListsEffectiveMLTEncoderOptions() throws {
        let defaultResult = try exportMLT(verbose: true)
        defer { try? FileManager.default.removeItem(at: defaultResult.url) }
        #expect(defaultResult.output.contains("MLT encoder:"))
        #expect(defaultResult.output.contains("fsst"))

        let noFSSTResult = try exportMLT(["--mlt-no-fsst"], verbose: true)
        defer { try? FileManager.default.removeItem(at: noFSSTResult.url) }
        #expect(noFSSTResult.output.contains("MLT encoder:"))
        #expect(!noFSSTResult.output.contains("fsst"))
    }

    @Test(.timeLimit(.minutes(1)))
    func disablingDictionariesStillProducesDecodableTiles() throws {
        let result = try exportMLT(["--mlt-no-dictionaries", "--mlt-no-vertex-dictionaries"], verbose: true)
        defer { try? FileManager.default.removeItem(at: result.url) }
        #expect(result.output.contains("MLT encoder: delta-rle"))
        let data = try Data(contentsOf: result.url)
        #expect(!data.isEmpty)
        let tile = try VectorTile(mltData: data, x: 8716, y: 8015, z: 14)
        #expect(!tile.layerNames.isEmpty)
    }

}
#endif
