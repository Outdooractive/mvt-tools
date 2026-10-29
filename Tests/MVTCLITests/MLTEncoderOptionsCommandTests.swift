import Foundation
import MVTTools
import Testing

#if EnableMVT && EnableMLT && !EnableMLTCXX
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

    private func exportArguments(_ mltOptions: [String]) -> [String] {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mlt_options_\(UUID().uuidString).mlt")
        return [
            "export", mvtPath,
            "-O", "mlt",
            "-o", outUrl.path,
            "-x", "8716", "-y", "8015", "-z", "14",
            "-oC", "0",
            "--force-overwrite",
        ] + mltOptions
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
        #expect(!defaultResult.output.contains("vertex-dictionaries"))
        #expect(!defaultResult.output.contains("fastpfor"))

        let noFSSTResult = try exportMLT(["--mlt-disable", "fsst"], verbose: true)
        defer { try? FileManager.default.removeItem(at: noFSSTResult.url) }
        #expect(noFSSTResult.output.contains("MLT encoder:"))
        #expect(!noFSSTResult.output.contains("fsst"))

        let vertexResult = try exportMLT(["--mlt-enable", "vertex-dictionaries"], verbose: true)
        defer { try? FileManager.default.removeItem(at: vertexResult.url) }
        #expect(vertexResult.output.contains("vertex-dictionaries"))
    }

    @Test(.timeLimit(.minutes(1)))
    func commaSeparatedFeatureLists() throws {
        let result = try exportMLT(["--mlt-disable", "dictionaries,fsst"], verbose: true)
        defer { try? FileManager.default.removeItem(at: result.url) }
        #expect(result.output.contains("MLT encoder: delta-rle"))

        let enabled = try exportMLT(["--mlt-enable", "fastpfor,vertex-dictionaries"], verbose: true)
        defer { try? FileManager.default.removeItem(at: enabled.url) }
        #expect(enabled.output.contains("fastpfor"))
        #expect(enabled.output.contains("vertex-dictionaries"))
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedFeatureLists() throws {
        let result = try exportMLT(
            ["--mlt-disable", "dictionaries", "--mlt-disable", "vertex-dictionaries"],
            verbose: true)
        defer { try? FileManager.default.removeItem(at: result.url) }
        #expect(result.output.contains("MLT encoder: delta-rle"))
    }

    @Test(.timeLimit(.minutes(1)))
    func plainPresetCanBeExtended() throws {
        let result = try exportMLT(["--mlt-plain", "--mlt-enable", "fastpfor"], verbose: true)
        defer { try? FileManager.default.removeItem(at: result.url) }
        #expect(result.output.contains("MLT encoder: fastpfor"))
    }

    @Test(.timeLimit(.minutes(1)))
    func disablingFeaturesStillProducesDecodableTiles() throws {
        let result = try exportMLT(["--mlt-disable", "dictionaries,vertex-dictionaries"])
        defer { try? FileManager.default.removeItem(at: result.url) }
        let data = try Data(contentsOf: result.url)
        #expect(!data.isEmpty)
        let tile = try VectorTile(mltData: data, x: 8716, y: 8015, z: 14)
        #expect(!tile.layerNames.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidFeatureIsRejected() throws {
        let result = try runCLIWithStderr(args: exportArguments(["--mlt-disable", "nope"]))
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("nope"))
    }

    @Test(.timeLimit(.minutes(1)))
    func conflictingFeaturesAreRejected() throws {
        let result = try runCLIWithStderr(
            args: exportArguments(["--mlt-enable", "fsst", "--mlt-disable", "fsst"]))
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("both enabled and disabled"))
    }

}
#endif
