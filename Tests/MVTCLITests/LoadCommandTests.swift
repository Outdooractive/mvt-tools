import Foundation
import GISTools
import MVTTools
import Testing

struct LoadCommandTests {

    // MARK: - Fixtures

    /// Creates a temp directory of "tile" files named `<z>_<x>_<y>.pbf`
    /// for all tiles at zoom `2` (4x4 = 16 tiles), each containing a
    /// small sentinel payload identifying the tile.
    ///
    /// The returned URL can be used as a `file://` base for `mvt load`.
    private func makeTileSource() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_src_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for x in 0 ..< 4 {
            for y in 0 ..< 4 {
                let tileFile = dir.appendingPathComponent("2_\(x)_\(y).pbf")
                let payload = "tile-2-\(x)-\(y)".data(using: .utf8) ?? Data()
                try payload.write(to: tileFile)
            }
        }
        return dir
    }

    /// A WGS84 bounding box that covers six tiles at zoom 2:
    /// (x=1..3, y=1..2). Longitudes -90 to 90 span three x-tiles
    /// (each 90° wide at z=2), latitudes -45 to 45 span two y-tiles
    /// (y is flipped: y=1 covers 0..-85, y=2 covers 85..0).
    private static let bbox = "-90,-45,90,45"

    /// Builds the `file://` URL template for a source directory, using a
    /// literal `2_` zoom prefix in the filename so zoom can be inferred.
    private func fileTemplate(sourceDir: URL) -> String {
        "file://\(sourceDir.path)/2_{x}_{y}.pbf"
    }

    /// The six tiles expected to be downloaded for `bbox` at zoom 2.
    private static let expectedTiles: [(x: Int, y: Int)] = [
        (1, 1), (1, 2), (2, 1), (2, 2), (3, 1), (3, 2),
    ]

    /// The set of expected flat-layout filenames for `bbox` at zoom 2.
    private static let expectedFlatNames: Set<String> = Set(
        expectedTiles.map { "2_\($0.x)_\($0.y).pbf" })

    // MARK: - Tests

    @Test(.timeLimit(.minutes(1)))
    func loadFlatLayout() throws {
        let sourceDir = try makeTileSource()
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let template = fileTemplate(sourceDir: sourceDir)
        let (stdout, _, exitCode) = try runCLIWithStderr(args: [
            "load", "--bbox=\(Self.bbox)", "--output-dir", outputDir.path, template,
        ])

        #expect(exitCode == 0)
        #expect(stdout.contains("Loaded 6 tiles"))

        // Expect six files in flat layout
        let actualFiles = Set((try? FileManager.default.contentsOfDirectory(atPath: outputDir.path)) ?? [])
        #expect(actualFiles.intersection(Self.expectedFlatNames).count == 6)

        // Verify content of one tile
        if FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("2_2_1.pbf").path) {
            let tile = outputDir.appendingPathComponent("2_2_1.pbf")
            let data = try Data(contentsOf: tile)
            #expect(String(data: data, encoding: .utf8) == "tile-2-2-1")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func loadTreeLayout() throws {
        let sourceDir = try makeTileSource()
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let template = fileTemplate(sourceDir: sourceDir)
        let (stdout, _, exitCode) = try runCLIWithStderr(args: [
            "load", "--bbox=\(Self.bbox)", "--output-dir", outputDir.path,
            "--layout", "tree", template,
        ])

        #expect(exitCode == 0)
        #expect(stdout.contains("Loaded 6 tiles"))

        // Expect tree structure: 2/<x>/<y>.pbf for each expected tile
        for (x, y) in Self.expectedTiles {
            let tile = outputDir
                .appendingPathComponent("2")
                .appendingPathComponent("\(x)")
                .appendingPathComponent("\(y).pbf")
            #expect(FileManager.default.fileExists(atPath: tile.path), "Missing tree tile \(x)/\(y)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func loadSkipsExisting() throws {
        let sourceDir = try makeTileSource()
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_out_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // Pre-create one destination tile with sentinel content
        let sentinelFile = outputDir.appendingPathComponent("2_2_1.pbf")
        try Data("SENTINEL".utf8).write(to: sentinelFile)

        let template = fileTemplate(sourceDir: sourceDir)
        let (stdout, _, exitCode) = try runCLIWithStderr(args: [
            "load", "--bbox=\(Self.bbox)", "--output-dir", outputDir.path, template,
        ])

        #expect(exitCode == 0)
        // 1 skipped (the sentinel), 5 downloaded
        #expect(stdout.contains("Loaded 5 tiles"))
        #expect(stdout.contains("1 skipped"))

        // Sentinel content must be preserved
        let data = try Data(contentsOf: sentinelFile)
        #expect(String(data: data, encoding: .utf8) == "SENTINEL")

        // The other 5 tiles should be downloaded
        let otherNames = Self.expectedFlatNames.subtracting(["2_2_1.pbf"])
        for name in otherNames {
            let tile = outputDir.appendingPathComponent(name)
            #expect(FileManager.default.fileExists(atPath: tile.path), "Missing \(name)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func loadOverwriteExisting() throws {
        let sourceDir = try makeTileSource()
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_out_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // Pre-create one destination tile with sentinel content
        let sentinelFile = outputDir.appendingPathComponent("2_2_1.pbf")
        try Data("SENTINEL".utf8).write(to: sentinelFile)

        let template = fileTemplate(sourceDir: sourceDir)
        let (stdout, _, exitCode) = try runCLIWithStderr(args: [
            "load", "--bbox=\(Self.bbox)", "--output-dir", outputDir.path,
            "--overwrite-existing", template,
        ])

        #expect(exitCode == 0)
        // All 6 downloaded, none skipped
        #expect(stdout.contains("Loaded 6 tiles"))
        #expect(stdout.contains("0 skipped"))

        // Sentinel content must be replaced with the real tile content
        let data = try Data(contentsOf: sentinelFile)
        #expect(String(data: data, encoding: .utf8) == "tile-2-2-1")
    }

    @Test(.timeLimit(.minutes(1)))
    func loadMissingZoomErrors() throws {
        let sourceDir = try makeTileSource()
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // URL with only {z}/{x}/{y} placeholders and no --zoom
        let template = "file://\(sourceDir.path)/{z}_{x}_{y}.pbf"
        let (_, stderr, exitCode) = try runCLIWithStderr(args: [
            "load", "--bbox=\(Self.bbox)", "--output-dir", outputDir.path, template,
        ])

        #expect(exitCode != 0)
        #expect(stderr.contains("Could not infer zoom level") || stderr.contains("zoom"))
    }

    @Test(.timeLimit(.minutes(1)))
    func loadZoomFallback() throws {
        let sourceDir = try makeTileSource()
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // URL with {z} placeholder — rely on --zoom fallback
        let template = "file://\(sourceDir.path)/{z}_{x}_{y}.pbf"
        let (stdout, _, exitCode) = try runCLIWithStderr(args: [
            "load", "--bbox=\(Self.bbox)", "--output-dir", outputDir.path,
            "--zoom", "2", template,
        ])

        #expect(exitCode == 0)
        #expect(stdout.contains("Loaded 6 tiles"))

        let actualFiles = Set((try? FileManager.default.contentsOfDirectory(atPath: outputDir.path)) ?? [])
        #expect(actualFiles.intersection(Self.expectedFlatNames).count == 6)
    }

    @Test(.timeLimit(.minutes(1)))
    func loadSoftFailureVerbose() throws {
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // Use a template that points to a non-existent source directory to
        // force all tile downloads to fail.
        let badTemplate = "file:///tmp/mvt_nonexistent_\(UUID().uuidString)/2_{x}_{y}.pbf"

        // Without verbose: stderr should be silent about soft failures
        let (stdout, stderrSilent, exitCodeSilent) = try runCLIWithStderr(args: [
            "load", "--bbox=\(Self.bbox)", "--output-dir", outputDir.path, badTemplate,
        ])
        #expect(exitCodeSilent == 0)
        #expect(stdout.contains("Loaded 0 tiles"))
        #expect(stdout.contains("6 failed"))
        // Without verbose, soft-failure details go to stderr only when verbose — here stderr should be empty
        #expect(stderrSilent.isEmpty)

        // With verbose: stderr should contain "Failed" messages
        let (_, stderrVerbose, _) = try runCLIWithStderr(args: [
            "load", "--bbox=\(Self.bbox)", "--output-dir", outputDir.path,
            "--verbose", badTemplate,
        ])
        #expect(stderrVerbose.contains("Failed"))
    }

    @Test(.timeLimit(.minutes(1)))
    func loadInvalidBbox() throws {
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // Too few values
        let (_, _, exitCode1) = try runCLIWithStderr(args: [
            "load", "--bbox=1,2,3", "--output-dir", outputDir.path,
            "file:///tmp/2_{x}_{y}.pbf",
        ])
        #expect(exitCode1 != 0)

        // Out-of-range longitude
        let (_, stderr2, exitCode2) = try runCLIWithStderr(args: [
            "load", "--bbox=-190,-45,90,45", "--output-dir", outputDir.path,
            "file:///tmp/2_{x}_{y}.pbf",
        ])
        #expect(exitCode2 != 0)
        #expect(stderr2.contains("Longitude"))

        // Out-of-range latitude
        let (_, stderr3, exitCode3) = try runCLIWithStderr(args: [
            "load", "--bbox=-90,-95,90,45", "--output-dir", outputDir.path,
            "file:///tmp/2_{x}_{y}.pbf",
        ])
        #expect(exitCode3 != 0)
        #expect(stderr3.contains("Latitude"))
    }

    @Test(.timeLimit(.minutes(1)))
    func loadProgressVerbose() throws {
        let sourceDir = try makeTileSource()
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let template = fileTemplate(sourceDir: sourceDir)
        let (_, stderr, exitCode) = try runCLIWithStderr(args: [
            "load", "--bbox=\(Self.bbox)", "--output-dir", outputDir.path,
            "--verbose", template,
        ])

        #expect(exitCode == 0)
        // Verbose mode prints progress lines to stderr with percentage,
        // runtime, and ETA.
        #expect(stderr.contains("Loading tiles:"))
        #expect(stderr.contains("%)"))
        #expect(stderr.contains("eta "))
        #expect(stderr.contains("Loaded 6 tiles"))
    }

    @Test(.timeLimit(.minutes(1)))
    func loadZoomInferenceIgnoresNumericDirPrefix() throws {
        // Simulates a macOS CI temp directory path like
        // /var/folders/8j/.../T/ that has a leading digit in a directory
        // name. The zoom must be inferred from the filename's `2_` prefix,
        // not from the `8j` directory.
        let sourceDir = try makeTileSource()
        // Create a nested directory with a numeric prefix to mimic CI paths
        let trickyDir = sourceDir
            .deletingLastPathComponent()
            .appendingPathComponent("8j")
            .appendingPathComponent("T")
        try FileManager.default.createDirectory(at: trickyDir, withIntermediateDirectories: true)
        // Copy tile files into the tricky directory
        for x in 0 ..< 4 {
            for y in 0 ..< 4 {
                let src = sourceDir.appendingPathComponent("2_\(x)_\(y).pbf")
                let dst = trickyDir.appendingPathComponent("2_\(x)_\(y).pbf")
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }

        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_out_\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: trickyDir)
        }

        let template = "file://\(trickyDir.path)/2_{x}_{y}.pbf"
        let (stdout, _, exitCode) = try runCLIWithStderr(args: [
            "load", "--bbox=\(Self.bbox)", "--output-dir", outputDir.path, template,
        ])

        #expect(exitCode == 0)
        // Must infer z=2 from the filename, not z=8 from the "8j" directory
        #expect(stdout.contains("Loaded 6 tiles"))
    }

}