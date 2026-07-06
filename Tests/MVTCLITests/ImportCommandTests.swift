import Foundation
import MVTTools
import Testing

struct ImportCommandTests {

    // MARK: Input formats

    @Test(.timeLimit(.minutes(1)))
    func importGeoJsonToMvt() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("imp_\(UUID().uuidString).mvt")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        let output = try runCLI(args: ["import", "-x", "5", "-y", "13", "-z", "4", "--output", outUrl.path, "--force-overwrite", "--verbose", input.path])
        #expect(output.contains("mvt"))
        try assertMvtFile(at: outUrl)
    }

    @Test(.timeLimit(.minutes(1)))
    func importGeoJsonToMlt() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("imp_\(UUID().uuidString).mlt")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["import", "-x", "5", "-y", "13", "-z", "4", "--output", outUrl.path, "--force-overwrite", input.path])
        try assertMvtFile(at: outUrl)
    }

    @Test(.timeLimit(.minutes(1)))
    func importGeoJsonToGeoJson() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("imp_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["import", "--output", outUrl.path, "--force-overwrite", input.path])
        let fc = try assertGeoJsonFile(at: outUrl)
        #expect(!fc.features.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func importGeoJsonToGpx() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("imp_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["import", "--output", outUrl.path, "--force-overwrite", input.path])
        #expect(FileManager.default.fileExists(atPath: outUrl.path))
    }

    @Test(.timeLimit(.minutes(1)))
    func importGeoJsonToShapefile() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("imp_\(UUID().uuidString).shp")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["import", "--output", outUrl.path, "--force-overwrite", input.path])
        #expect(FileManager.default.fileExists(atPath: outUrl.path))
    }

    @Test(.timeLimit(.minutes(1)))
    func importGeoJsonToGeoPackage() throws {
        let input = try generateSmallGeoJson()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("imp_\(UUID().uuidString).gpkg")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["import", "--output", outUrl.path, "--force-overwrite", input.path])
        #expect(FileManager.default.fileExists(atPath: outUrl.path))
    }

    // MARK: Input from other formats

    @Test(.timeLimit(.minutes(1)))
    func importGpxToMvt() throws {
        let input = try generateSmallGpx()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("imp_\(UUID().uuidString).mvt")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["import", "-x", "0", "-y", "0", "-z", "0", "--output", outUrl.path, "--force-overwrite", input.path])
        try assertMvtFile(at: outUrl)
    }

    @Test(.timeLimit(.minutes(1)))
    func importShapefileToMvt() throws {
        let input = try generateSmallShapefile()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("imp_\(UUID().uuidString).mvt")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["import", "-x", "0", "-y", "0", "-z", "0", "--output", outUrl.path, "--force-overwrite", input.path])
        try assertMvtFile(at: outUrl)
    }

    @Test(.timeLimit(.minutes(1)))
    func importGeoPackageToMvt() async throws {
        let input = try await generateSmallGeoPackage()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("imp_\(UUID().uuidString).mvt")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["import", "-x", "0", "-y", "0", "-z", "0", "--output", outUrl.path, "--force-overwrite", input.path])
        try assertMvtFile(at: outUrl)
    }

    @Test(.timeLimit(.minutes(1)))
    func importMltToMvt() throws {
        let input = try generateSmallMlt()
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("imp_\(UUID().uuidString).mvt")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        _ = try runCLI(args: ["import", "-x", "0", "-y", "0", "-z", "0", "--output", outUrl.path, "--force-overwrite", input.path])
        try assertMvtFile(at: outUrl)
    }

}
