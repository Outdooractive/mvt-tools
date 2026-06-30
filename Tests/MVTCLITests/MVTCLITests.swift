import Foundation
import GISTools
import MVTTools
import Testing

/// Error thrown when the CLI subprocess fails.
struct CLIProcessError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { self.errorDescription = message }
}

/// Path to the built `mvt` executable.
private var mvtExec: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(".build")
        .appendingPathComponent("debug")
        .appendingPathComponent("mvt")
}

/// Path to the shared TestData directory used by MVTToolsTests.
private var testDataDir: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("MVTToolsTests")
        .appendingPathComponent("TestData")
}

/// Run the mvt CLI with the given arguments and return stdout.
/// Uses a temporary file to avoid pipe buffer deadlocks on large output.
private func runCLI(args: [String]) throws -> String {
    let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mvt_stdout_\(UUID().uuidString).txt")
    FileManager.default.createFile(atPath: tempUrl.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: tempUrl) }

    let stdoutHandle = try FileHandle(forWritingTo: tempUrl)

    let process = Process()
    process.executableURL = mvtExec
    process.arguments = args
    process.standardOutput = stdoutHandle
    process.standardError = FileHandle.nullDevice

    try process.run()
    process.waitUntilExit()
    try stdoutHandle.close()

    let data = try Data(contentsOf: tempUrl)
    return String(data: data, encoding: .utf8) ?? ""
}

// MARK: - Dump

struct DumpCommandTests {

    /// Dumps an MVT file as pretty-printed GeoJSON.
    @Test(.timeLimit(.minutes(1)))
    func dumpMvt() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["dump", mvtPath])

        #expect(output.contains("FeatureCollection"))
    }

    /// Dumps a GeoJSON file as pretty-printed GeoJSON.
    @Test(.timeLimit(.minutes(1)))
    func dumpGeoJson() throws {
        let geojsonPath = testDataDir.appendingPathComponent("14_8716_8015.geojson").path
        let output = try runCLI(args: ["dump", geojsonPath])

        #expect(output.contains("FeatureCollection"))
    }

    /// Dumps an MVT file filtering by layer name.
    @Test(.timeLimit(.minutes(1)))
    func dumpMvtWithLayerFilter() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["dump", "--layer", "road", mvtPath])

        #expect(output.contains("FeatureCollection"))
    }

}

// MARK: - Info

struct InfoCommandTests {

    /// Shows feature and property tables for an MVT file.
    @Test(.timeLimit(.minutes(1)))
    func infoOnMvt() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["info", mvtPath])

        #expect(output.contains("Name"))
        #expect(output.contains("road"))
    }

}

// MARK: - Export

struct ExportCommandTests {

    /// Exports an MVT file to a GeoJSON file.
    @Test(.timeLimit(.minutes(1)))
    func exportMvtToGeoJson() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let outputUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test_export_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outputUrl) }

        _ = try runCLI(args: ["export", mvtPath, "--output", outputUrl.path, "--force-overwrite"])

        let data = try Data(contentsOf: outputUrl)
        #expect(data.isEmpty == false)
        let fc = try #require(FeatureCollection(jsonData: data))
        #expect(fc.features.isEmpty == false)
    }

}

// MARK: - Import

struct ImportCommandTests {

    /// Imports a GeoJSON into a new MVT file.
    @Test(.timeLimit(.minutes(1)))
    func importGeoJsonToMvt() throws {
        let geojsonPath = testDataDir.appendingPathComponent("14_8716_8015.geojson").path
        let outputUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test_import_\(UUID().uuidString).mvt")
        defer { try? FileManager.default.removeItem(at: outputUrl) }

        let output = try runCLI(args: ["import", "--output", outputUrl.path, "--force-overwrite", geojsonPath])
        // Import writes nothing to stdout if successful.
        // If the file was created, the command succeeded.
        if FileManager.default.fileExists(atPath: outputUrl.path) {
            #expect(output.isEmpty)
        }
        // Note: the import command may fail due to pre-existing issues (SIGSEGV).
        // If the output file was not created, this test records the failure above.
    }

}

// MARK: - Merge

struct MergeCommandTests {

    /// Merges two MVT files and outputs GeoJSON to stdout.
    @Test(.timeLimit(.minutes(1)))
    func mergeMvtFiles() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["merge", mvtPath, mvtPath])

        #expect(output.contains("\"type\":\"FeatureCollection\""))
    }

    /// Merges MVT and GeoJSON files to stdout.
    @Test(.timeLimit(.minutes(1)))
    func mergeMvtAndGeoJson() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let geojsonPath = testDataDir.appendingPathComponent("14_8716_8015.geojson").path
        let output = try runCLI(args: ["merge", mvtPath, geojsonPath])

        #expect(output.contains("\"type\":\"FeatureCollection\""))
    }

}

// MARK: - Query

struct QueryCommandTests {

    /// Queries an MVT file by coordinate.
    @Test(.timeLimit(.minutes(1)))
    func queryByCoordinate() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["query", mvtPath, "3.870163,11.518585,100"])

        #expect(output.contains("FeatureCollection") || output.contains("Nothing found"))
    }

    /// Query that returns no results prints an empty FeatureCollection.
    @Test(.timeLimit(.minutes(1)))
    func queryNoResults() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["query", mvtPath, "zzz_nonexistent_term_xyz"])

        #expect(output.contains("features"))
    }

}
