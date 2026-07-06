import Foundation
import MVTTools
import Testing

struct ExportCommandTests {

    @Test(.timeLimit(.minutes(1)))
    func exportMvtToGeoJson() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("exp_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["export", mvtPath, "--output", outUrl.path, "--force-overwrite"])
        let fc = try assertGeoJsonFile(at: outUrl)
        #expect(!fc.features.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func exportGeoJsonToGeoJson() throws {
        let path = try generateSmallGeoJson().path
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("exp_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["export", path, "--output", outUrl.path, "--force-overwrite"])
        let fc = try assertGeoJsonFile(at: outUrl)
        #expect(!fc.features.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func exportGpxToGeoJson() throws {
        let path = try generateSmallGpx().path
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("exp_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["export", path, "--output", outUrl.path, "--force-overwrite"])
        let fc = try assertGeoJsonFile(at: outUrl)
        #expect(!fc.features.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func exportShapefileToGeoJson() throws {
        let path = try generateSmallShapefile().path
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("exp_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["export", path, "--output", outUrl.path, "--force-overwrite"])
        let fc = try assertGeoJsonFile(at: outUrl)
        #expect(!fc.features.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func exportGeoPackageToGeoJson() async throws {
        let path = try await generateSmallGeoPackage().path
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("exp_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["export", path, "--output", outUrl.path, "--force-overwrite"])
        let fc = try assertGeoJsonFile(at: outUrl)
        #expect(!fc.features.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func exportMltToGeoJson() throws {
        let path = try generateSmallMlt().path
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("exp_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["export", "-x", "0", "-y", "0", "-z", "0", path, "--output", outUrl.path, "--force-overwrite"])
        let fc = try assertGeoJsonFile(at: outUrl)
        #expect(!fc.features.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func exportWithCompression() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("exp_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["export", mvtPath, "--output", outUrl.path, "--force-overwrite", "-oC", "5"])
        let data = try Data(contentsOf: outUrl)
        #expect(!data.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func exportWithSimplify() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("exp_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["export", mvtPath, "--output", outUrl.path, "--force-overwrite", "--simplify-meters", "100"])
        let fc = try assertGeoJsonFile(at: outUrl)
        #expect(!fc.features.isEmpty)
    }

}
