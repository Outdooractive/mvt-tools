import Foundation
import MVTTools
import Testing

struct QueryCommandTests {

    // MARK: Across all formats

    @Test(.timeLimit(.minutes(1)))
    func queryMvtByText() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["query", mvtPath, "zzz_nonexistent"])
        #expect(output.contains("features") || output.contains("Nothing found"))
    }

    @Test(.timeLimit(.minutes(1)))
    func queryGeoJsonByText() throws {
        let path = try generateSmallGeoJson().path
        let output = try runCLI(args: ["query", path, "A"])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func queryGpxByText() throws {
        let path = try generateSmallGpx().path
        let output = try runCLI(args: ["query", path, "PointA"])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func queryShapefileByText() throws {
        let path = try generateSmallShapefile().path
        let output = try runCLI(args: ["query", path, "nothing"])
        #expect(output.contains("features") || output.contains("Nothing found"))
    }

    @Test(.timeLimit(.minutes(1)))
    func queryGeoPackageByText() async throws {
        let path = try await generateSmallGeoPackage().path
        let output = try runCLI(args: ["query", path, "A"])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func queryMltByText() throws {
        let path = try generateSmallMlt().path
        let output = try runCLI(args: ["query", "-x", "0", "-y", "0", "-z", "0", path, "A"])
        #expect(output.contains("FeatureCollection"))
    }

    // MARK: Parameter variants

    @Test(.timeLimit(.minutes(1)))
    func queryByCoordinate() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["query", mvtPath, "3.870163,11.518585,100"])
        #expect(output.contains("FeatureCollection") || output.contains("Nothing found"))
    }

    @Test(.timeLimit(.minutes(1)))
    func queryWithPropertyFilter() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["query", mvtPath, ".class=='hospital'"])
        #expect(output.contains("FeatureCollection") || output.contains("Nothing found"))
    }

    @Test(.timeLimit(.minutes(1)))
    func queryWithOutputFile() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let outUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("q_\(UUID().uuidString).geojson")
        defer { try? FileManager.default.removeItem(at: outUrl) }
        let output = try runCLI(args: ["query", "--output", outUrl.path, "--verbose", mvtPath, "road"])
        #expect(output.contains("Found"))
        try assertGeoJsonFile(at: outUrl)
    }

    @Test(.timeLimit(.minutes(1)))
    func queryWithLayerFilter() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["query", "--layer", "road", mvtPath, "road"])
        #expect(output.contains("FeatureCollection") || output.contains("Nothing found"))
    }

}
