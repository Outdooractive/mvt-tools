import Foundation
import GISTools
import Testing

struct ReprojectCommandTests {

    private func temporaryURL(_ ext: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_reproject_\(UUID().uuidString).\(ext)")
    }

    @Test(.timeLimit(.minutes(1)))
    func reprojectGeoJSONInputProjection() throws {
        let input = temporaryURL("geojson")
        let output = temporaryURL("geojson")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }

        let json = """
        {"type":"FeatureCollection","features":[{"type":"Feature","properties":{},"geometry":{"type":"Point","coordinates":[1281000,6125000]}}]}
        """
        try Data(json.utf8).write(to: input)

        let (_, stderr, exitCode) = try runCLIWithStderr(args: [
            "reproject",
            "-ip", "3857",
            "-op", "4326",
            "--output", output.path,
            input.path,
        ])

        #expect(exitCode == 0, "stderr: \(stderr)")
        let result = try #require(FeatureCollection(jsonData: try Data(contentsOf: output)))
        let point = try #require(result.features.first?.geometry as? Point)
        #expect(point.coordinate.projection == .epsg4326)
        #expect(abs(point.coordinate.longitude - 11.5) < 0.01)
        #expect(abs(point.coordinate.latitude - 48.1) < 0.01)
    }

    #if EnableCSV
    @Test(.timeLimit(.minutes(1)))
    func reprojectCSVInputProjection() throws {
        let input = temporaryURL("csv")
        let output = temporaryURL("geojson")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }

        try Data("id,x,y\n1,1281000,6125000\n".utf8).write(to: input)

        let (_, stderr, exitCode) = try runCLIWithStderr(args: [
            "reproject",
            "-ip", "3857",
            "-op", "4326",
            "--output", output.path,
            input.path,
        ])

        #expect(exitCode == 0, "stderr: \(stderr)")
        let result = try #require(FeatureCollection(jsonData: try Data(contentsOf: output)))
        let point = try #require(result.features.first?.geometry as? Point)
        #expect(abs(point.coordinate.longitude - 11.5) < 0.01)
        #expect(abs(point.coordinate.latitude - 48.1) < 0.01)
    }
    #endif

    #if EnableMVT
    @Test(.timeLimit(.minutes(1)))
    func reprojectFiltersLayers() throws {
        let input = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt")
        let output = temporaryURL("geojson")
        defer { try? FileManager.default.removeItem(at: output) }

        let (_, stderr, exitCode) = try runCLIWithStderr(args: [
            "reproject",
            "-op", "4326",
            "-x", "8716", "-y", "8015", "-z", "14",
            "--layer", "road",
            "--output", output.path,
            input.path,
        ])

        #expect(exitCode == 0, "stderr: \(stderr)")
        let result = try #require(FeatureCollection(jsonData: try Data(contentsOf: output)))
        #expect(result.features.isEmpty == false)
        #expect(result.features.allSatisfy {
            $0.properties["vt_layer"] as? String == "road"
        })
    }
    #endif

    @Test(.timeLimit(.minutes(1)))
    func reprojectRequiresOutputProjection() throws {
        let input = temporaryURL("geojson")
        let output = temporaryURL("geojson")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }

        try Data(#"{"type":"Point","coordinates":[11.5,48.1]}"#.utf8).write(to: input)
        let (_, stderr, exitCode) = try runCLIWithStderr(args: [
            "reproject",
            "--output", output.path,
            input.path,
        ])

        #expect(exitCode != 0)
        #expect(stderr.contains("output-projection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func reprojectRejectsInvalidProjection() throws {
        let input = temporaryURL("geojson")
        let output = temporaryURL("geojson")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }

        try Data(#"{"type":"Point","coordinates":[11.5,48.1]}"#.utf8).write(to: input)
        let (_, _, exitCode) = try runCLIWithStderr(args: [
            "reproject",
            "-op", "not-a-crs",
            "--output", output.path,
            input.path,
        ])

        #expect(exitCode != 0)
    }

}
