import Foundation
import GISTools
import MVTTools
import Testing

struct MergeCommandTests {

    // MARK: Output to stdout

    #if EnableMVT
    @Test(.timeLimit(.minutes(1)))
    func mergeMvtFiles() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["merge", mvtPath, mvtPath])
        #expect(output.contains("\"type\":\"FeatureCollection\""))
    }
    #endif

    #if EnableMVT
    @Test(.timeLimit(.minutes(1)))
    func mergeMvtAndGeoJson() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let geojsonPath = testDataDir.appendingPathComponent("14_8716_8015.geojson").path
        let output = try runCLI(args: ["merge", mvtPath, geojsonPath])
        #expect(output.contains("\"type\":\"FeatureCollection\""))
    }
    #endif

    // MARK: Output formats

    #if EnableMVT
    @Test(.timeLimit(.minutes(1)))
    func mergeToMvt() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).mvt")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", "-x", "0", "-y", "0", "-z", "0", input.path])
        try assertMvtFile(at: outUrl)
    }
    #endif

    #if EnableMLT
    @Test(.timeLimit(.minutes(1)))
    func mergeToMlt() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).mlt")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", "-x", "0", "-y", "0", "-z", "0", input.path])
        #expect(FileManager.default.fileExists(atPath: outUrl.path))
    }
    #endif

    @Test(.timeLimit(.minutes(1)))
    func mergeToGeoJson() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", input.path])
        let fc = try assertGeoJsonFile(at: outUrl)
        #expect(!fc.features.isEmpty)
    }

    #if EnableGPX
    @Test(.timeLimit(.minutes(1)))
    func mergeToGpx() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", input.path])
        #expect(FileManager.default.fileExists(atPath: outUrl.path))
    }
    #endif

    #if EnableShapefile
    @Test(.timeLimit(.minutes(1)))
    func mergeToShapefile() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).shp")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", input.path])
        #expect(FileManager.default.fileExists(atPath: outUrl.path))
    }
    #endif

    #if EnableGeoPackage
    @Test(.timeLimit(.minutes(1)))
    func mergeToGeoPackage() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).gpkg")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", input.path])
        #expect(FileManager.default.fileExists(atPath: outUrl.path))
    }
    #endif

    // MARK: Multi-format merge

    #if EnableGPX
    @Test(.timeLimit(.minutes(1)))
    func mergeGeoJsonAndGpxToGeoJson() throws {
        let gj = try generateSmallGeoJson()
        let gpx = try generateSmallGpx()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", gj.path, gpx.path])
        let fc = try assertGeoJsonFile(at: outUrl)
        #expect(!fc.features.isEmpty)
    }
    #endif

    // MARK: Parameters

    #if EnableMVT
    @Test(.timeLimit(.minutes(1)))
    func mergeWithLayerFilter() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["merge", "--layer", "road", mvtPath, mvtPath])
        #expect(output.contains("FeatureCollection"))
    }
    #endif

    #if EnableMVT
    @Test(.timeLimit(.minutes(1)))
    func mergeWithDropLayer() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["merge", "--drop-layer", "water", mvtPath])
        #expect(output.contains("FeatureCollection"))
    }
    #endif

    @Test(.timeLimit(.minutes(1)))
    func mergeWithPrettyPrint() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", "--pretty-print", input.path])
        let data = try Data(contentsOf: outUrl)
        #expect(!data.isEmpty)
    }

}

// MARK: - Projection options

struct MergeProjectionTests {

    @Test(.timeLimit(.minutes(1)))
    func mergeWithInputAndOutputProjection() throws {
        let input = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merge_projection_\(UUID().uuidString).geojson")
        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merge_projection_\(UUID().uuidString).geojson")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }

        let json = """
        {"type":"FeatureCollection","features":[{"type":"Feature","properties":{},"geometry":{"type":"Point","coordinates":[1281000,6125000]}}]}
        """
        try Data(json.utf8).write(to: input)

        let (_, stderr, exitCode) = try runCLIWithStderr(args: [
            "merge",
            "-ip", "3857",
            "-op", "4326",
            "--output", output.path,
            input.path,
        ])
        #expect(exitCode == 0, "stderr: \(stderr)")

        let collection = try #require(FeatureCollection(jsonData: try Data(contentsOf: output)))
        let point = try #require(collection.features.first?.geometry as? Point)
        #expect(point.coordinate.projection == .epsg4326)
        #expect(abs(point.coordinate.longitude - 11.5) < 0.01)
        #expect(abs(point.coordinate.latitude - 48.1) < 0.01)
    }

}
