import Foundation
import GISTools
import MVTTools
import Testing

struct RobustnessCommandTests {

    // MARK: - Query

    @Test(.timeLimit(.minutes(1)))
    func queryNegativeCoordinate() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negative_coordinate_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: url) }

        let collection = FeatureCollection([
            Feature(
                Point(Coordinate3D(latitude: -33.86, longitude: 151.2)),
                id: .int(1),
                properties: ["name": "Sydney"]),
            Feature(
                Point(Coordinate3D(latitude: 48.85, longitude: 2.35)),
                id: .int(2),
                properties: ["name": "Paris"]),
        ])
        try #require(collection.asJsonData()).write(to: url)

        // Negative positional arguments must be separated from options with
        // `--`; after that the CLI must still recognise the coordinate form.
        let output = try runCLI(args: [
            "query", url.path, "--", "-33.86,151.2,1000",
        ])

        #expect(output.contains("FeatureCollection"))
        #expect(output.contains("Sydney"))
        #expect(output.contains("Paris") == false)
    }

    // MARK: - Load

    #if EnableMVT
    @Test(.timeLimit(.minutes(1)))
    func loadBoundingBoxCrossingAntimeridian() throws {
        let sourceDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_am_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_am_out_\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: outputDir)
        }

        for x in 0 ..< 4 {
            for y in 0 ..< 4 {
                try Data("tile".utf8).write(to: sourceDir.appendingPathComponent("2_\(x)_\(y).pbf"))
            }
        }

        let template = "file://\(sourceDir.path)/2_{x}_{y}.pbf"
        let (stdout, stderr, exitCode) = try runCLIWithStderr(args: [
            "load", "--bbox", "170,-10,-170,10", "--output-dir", outputDir.path, template,
        ])

        #expect(exitCode == 0)
        #expect(stderr.isEmpty)
        // The box spans the last and first tile column at z=2, and the two
        // middle rows: (3,1), (3,2), (0,1), (0,2).
        #expect(stdout.contains("Loaded 4 tiles"))

        for (x, y) in [(3, 1), (3, 2), (0, 1), (0, 2)] {
            let file = outputDir.appendingPathComponent("2_\(x)_\(y).pbf")
            #expect(FileManager.default.fileExists(atPath: file.path), "Missing tile \(x)/\(y)")
        }
    }
    #endif

    #if EnableMVT
    @Test(.timeLimit(.minutes(1)))
    func loadZoomOptionOverridesUrlZoom() throws {
        let sourceDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_zoom_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_load_zoom_out_\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: outputDir)
        }

        for x in 0 ..< 4 {
            for y in 0 ..< 4 {
                try Data("tile".utf8).write(to: sourceDir.appendingPathComponent("2_\(x)_\(y).pbf"))
            }
        }

        // The template literally says 2_, but --zoom 1 must win. At z=1 the
        // bounding box covers all four tiles, named 1_0_0 ... 1_1_1.
        let template = "file://\(sourceDir.path)/2_{x}_{y}.pbf"
        let (stdout, _, exitCode) = try runCLIWithStderr(args: [
            "load", "--bbox=-90,-45,90,45", "--zoom", "1",
            "--output-dir", outputDir.path, template,
        ])

        #expect(exitCode == 0)
        #expect(stdout.contains("Loaded 4 tiles"))

        for (x, y) in [(0, 0), (0, 1), (1, 0), (1, 1)] {
            let file = outputDir.appendingPathComponent("1_\(x)_\(y).pbf")
            #expect(FileManager.default.fileExists(atPath: file.path), "Missing tile \(x)/\(y)")
        }
        #expect(FileManager.default.fileExists(
            atPath: outputDir.appendingPathComponent("2_0_0.pbf").path) == false)
    }
    #endif

    // MARK: - Merge

    #if EnableMVT
    @Test(.timeLimit(.minutes(1)))
    func mergeWithoutInputsStillUsesOutputExtension() throws {
        let outputUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_merge_empty_\(UUID().uuidString).mvt")
        defer { try? FileManager.default.removeItem(at: outputUrl) }

        let (_, _, exitCode) = try runCLIWithStderr(args: [
            "merge", "--output", outputUrl.path, "--force-overwrite",
        ])
        #expect(exitCode == 0)

        // The output must be an MVT tile, not GeoJSON written into a .mvt file.
        let tile = try VectorTile(contentsOfMVT: outputUrl, x: 0, y: 0, z: 0)
        #expect(tile.origin == .mvt)
        #expect(tile.isEmpty)
    }
    #endif

}
