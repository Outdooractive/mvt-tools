import Foundation
import MVTTools
import Testing

struct MergeCommandTests {

    // MARK: Output to stdout

    @Test(.timeLimit(.minutes(1)))
    func mergeMvtFiles() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["merge", mvtPath, mvtPath])
        #expect(output.contains("\"type\":\"FeatureCollection\""))
    }

    @Test(.timeLimit(.minutes(1)))
    func mergeMvtAndGeoJson() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let geojsonPath = testDataDir.appendingPathComponent("14_8716_8015.geojson").path
        let output = try runCLI(args: ["merge", mvtPath, geojsonPath])
        #expect(output.contains("\"type\":\"FeatureCollection\""))
    }

    // MARK: Output formats

    @Test(.timeLimit(.minutes(1)))
    func mergeToMvt() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).mvt")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", "-x", "0", "-y", "0", "-z", "0", input.path])
        try assertMvtFile(at: outUrl)
    }

    @Test(.timeLimit(.minutes(1)))
    func mergeToMlt() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).mlt")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", "-x", "0", "-y", "0", "-z", "0", input.path])
        #expect(FileManager.default.fileExists(atPath: outUrl.path))
    }

    @Test(.timeLimit(.minutes(1)))
    func mergeToGeoJson() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", input.path])
        let fc = try assertGeoJsonFile(at: outUrl)
        #expect(!fc.features.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func mergeToGpx() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", input.path])
        #expect(FileManager.default.fileExists(atPath: outUrl.path))
    }

    @Test(.timeLimit(.minutes(1)))
    func mergeToShapefile() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).shp")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", input.path])
        #expect(FileManager.default.fileExists(atPath: outUrl.path))
    }

    @Test(.timeLimit(.minutes(1)))
    func mergeToGeoPackage() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("merge_\(UUID().uuidString).gpkg")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["merge", "--output", outUrl.path, "--force-overwrite", input.path])
        #expect(FileManager.default.fileExists(atPath: outUrl.path))
    }

    // MARK: Multi-format merge

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

    // MARK: Parameters

    @Test(.timeLimit(.minutes(1)))
    func mergeWithLayerFilter() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["merge", "--layer", "road", mvtPath, mvtPath])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func mergeWithDropLayer() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["merge", "--drop-layer", "water", mvtPath])
        #expect(output.contains("FeatureCollection"))
    }

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
