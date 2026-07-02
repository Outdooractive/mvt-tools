import Foundation
import GISTools
import MVTTools
import Testing

/// Error thrown when the CLI subprocess fails.
struct CLIProcessError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { self.errorDescription = message }
}

/// Check whether the file at `url` is executable and has the right binary
/// format for the current platform (Mach-O on macOS, ELF on Linux).
private func isNativeExecutable(at url: URL) -> Bool {
    guard FileManager.default.isExecutableFile(atPath: url.path) else { return false }
#if os(macOS)
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    guard let magic = try? handle.read(upToCount: 4) else { return false }
    let machoMagics: Set<[UInt8]> = [
        [0xFE, 0xED, 0xFA, 0xCE],
        [0xCE, 0xFA, 0xED, 0xFE],
        [0xFE, 0xED, 0xFA, 0xCF],
        [0xCF, 0xFA, 0xED, 0xFE],
        [0xCA, 0xFE, 0xBA, 0xBE],
        [0xBE, 0xBA, 0xFE, 0xCA],
    ]
    return machoMagics.contains(Array(magic))
#else
    return true
#endif
}

/// Locate the built `mvt` CLI executable.
private var mvtExec: URL {
    // 1. Xcode BUILT_PRODUCTS_DIR.
    if let builtProducts = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
        let candidate = URL(fileURLWithPath: builtProducts).appendingPathComponent("mvt")
        if isNativeExecutable(at: candidate) { return candidate }
    }

    // 2. Xcode DerivedData on macOS.
#if os(macOS)
    if let library = try? FileManager.default.url(
        for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    {
        let derivedData = library.appendingPathComponent("Developer/Xcode/DerivedData")
        if let enumerator = FileManager.default.enumerator(
            at: derivedData, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        {
            for case let subdir as URL in enumerator {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: subdir.path, isDirectory: &isDir),
                      isDir.boolValue,
                      subdir.lastPathComponent.hasPrefix("mvt-tools-")
                else { continue }
                let candidate = subdir
                    .appendingPathComponent("Build/Products/Debug")
                    .appendingPathComponent("mvt")
                if isNativeExecutable(at: candidate) { return candidate }
            }
        }
    }
#endif

    // 3. SPM build directory.
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let buildRoot = packageRoot.appendingPathComponent(".build")

    // 3a. Follow the debug symlink.
    let debugDir = buildRoot.appendingPathComponent("debug")
    if let linkDest = try? FileManager.default.destinationOfSymbolicLink(atPath: debugDir.path) {
        let resolved = buildRoot.appendingPathComponent(linkDest).appendingPathComponent("mvt")
        if isNativeExecutable(at: resolved) { return resolved }
    }

    // 3b. Host-specific platform triples.
    let hostTriples: [String]
#if arch(arm64)
    hostTriples = ["arm64-apple-macosx", "aarch64-apple-macosx"]
#elseif arch(x86_64)
    hostTriples = ["x86_64-apple-macosx"]
#else
    hostTriples = []
#endif
    for triple in hostTriples {
        let candidate = buildRoot
            .appendingPathComponent(triple)
            .appendingPathComponent("debug")
            .appendingPathComponent("mvt")
        if isNativeExecutable(at: candidate) { return candidate }
    }

    // 3c. Scan all platform subdirectories, preferring macOS over Linux.
    guard let enumerator = FileManager.default.enumerator(
        at: buildRoot, includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles])
    else { return debugDir.appendingPathComponent("mvt") }

    var bestCandidate: URL?
    for case let subdir as URL in enumerator {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: subdir.path, isDirectory: &isDir),
              isDir.boolValue else { continue }
        let candidate = subdir.appendingPathComponent("debug").appendingPathComponent("mvt")
        guard isNativeExecutable(at: candidate) else { continue }
        if subdir.lastPathComponent.contains("macosx") || subdir.lastPathComponent.contains("apple") {
            return candidate
        }
        bestCandidate = candidate
    }

    return bestCandidate ?? debugDir.appendingPathComponent("mvt")
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

    return String(data: try Data(contentsOf: tempUrl), encoding: .utf8) ?? ""
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

    /// Imports a small GeoJSON into a new MVT file with explicit tile coordinates.
    @Test(.timeLimit(.minutes(1)))
    func importGeoJsonToMvt() throws {
        let smallGeoJson = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test_small_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: smallGeoJson) }

        let fc = FeatureCollection(Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1)))
        if let data = fc.asJsonData() { try data.write(to: smallGeoJson) }

        let outputUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test_import_\(UUID().uuidString).mvt")
        defer { try? FileManager.default.removeItem(at: outputUrl) }

        let output = try runCLI(args: ["import", "-x", "5", "-y", "13", "-z", "4", "--output", outputUrl.path, "--force-overwrite", smallGeoJson.path])
        #expect(output.contains(".geojson"))
        #expect(FileManager.default.fileExists(atPath: outputUrl.path))
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
