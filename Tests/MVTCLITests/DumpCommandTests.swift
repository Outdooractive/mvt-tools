import Foundation
import GISTools
import MVTTools
import Testing

struct DumpCommandTests {

    // MARK: Format smoke tests

    @Test(.timeLimit(.minutes(1)))
    func dumpMvt() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["dump", mvtPath])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func dumpGeoJson() throws {
        let path = try generateSmallGeoJson().path
        let output = try runCLI(args: ["dump", path])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func dumpGpx() throws {
        let path = try generateSmallGpx().path
        let output = try runCLI(args: ["dump", path])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func dumpFit() throws {
        let path = try generateSmallFit().path
        let output = try runCLI(args: ["dump", path])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func dumpShapefile() throws {
        let path = try generateSmallShapefile().path
        let output = try runCLI(args: ["dump", path])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func dumpGeoPackage() async throws {
        let path = try await generateSmallGeoPackage().path
        let output = try runCLI(args: ["dump", path])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func dumpMlt() throws {
        let path = try generateSmallMlt().path
        let output = try runCLI(args: ["dump", "-x", "0", "-y", "0", "-z", "0", path])
        #expect(output.contains("FeatureCollection"))
    }

    // MARK: Parameters

    @Test(.timeLimit(.minutes(1)))
    func dumpMvtWithLayerFilter() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["dump", "--layer", "road", mvtPath])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func dumpMvtWithDropLayer() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["dump", "--drop-layer", "water", mvtPath])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func dumpGeoJsonWithLayerProperty() throws {
        let path = try generateSmallGeoJson().path
        let output = try runCLI(args: ["dump", "-P", "name", path])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func dumpWithSimplify() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["dump", "--simplify-meters", "100", mvtPath])
        #expect(output.contains("FeatureCollection"))
    }

    @Test(.timeLimit(.minutes(1)))
    func dumpWithVerbose() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["dump", "--verbose", mvtPath])
        #expect(output.contains("Dumping"))
    }

    @Test(.timeLimit(.minutes(1)))
    func dumpDisableOutputLayer() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["dump", "-Do", mvtPath])
        #expect(output.contains("FeatureCollection"))
    }

    // MARK: CSV options

    @Test(.timeLimit(.minutes(1)))
    func dumpCsvWithTreatAsLineString() throws {
        let path = try generateSmallCsv().path
        let output = try runCLI(args: ["dump", "--csv-linestring", path])
        #expect(output.contains(#""type" : "LineString""#))
        #expect(!output.contains(#""type" : "Point""#))

        // Without the flag, the points stay separate.
        let plainOutput = try runCLI(args: ["dump", path])
        #expect(plainOutput.contains(#""type" : "Point""#))
        #expect(!plainOutput.contains(#""type" : "LineString""#))
    }

}
