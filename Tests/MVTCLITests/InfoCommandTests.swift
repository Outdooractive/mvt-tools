import Foundation
import MVTTools
import Testing

struct InfoCommandTests {

    #if EnableMVT
    @Test(.timeLimit(.minutes(1)))
    func infoOnMvt() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["info", mvtPath])
        #expect(output.contains("Name"))
        #expect(output.contains("road"))
    }
    #endif

    @Test(.timeLimit(.minutes(1)))
    func infoOnGeoJson() throws {
        let path = try generateSmallGeoJson().path
        let output = try runCLI(args: ["info", path])
        #expect(output.contains("Name"))
    }

    #if EnableGPX
    @Test(.timeLimit(.minutes(1)))
    func infoOnGpx() throws {
        let path = try generateSmallGpx().path
        let output = try runCLI(args: ["info", path])
        #expect(output.contains("Name"))
    }
    #endif

    #if EnableShapefile
    @Test(.timeLimit(.minutes(1)))
    func infoOnShapefile() throws {
        let path = try generateSmallShapefile().path
        let output = try runCLI(args: ["info", path])
        #expect(output.contains("Name"))
    }
    #endif

    #if EnableGeoPackage
    @Test(.timeLimit(.minutes(1)))
    func infoOnGeoPackage() async throws {
        let path = try await generateSmallGeoPackage().path
        let output = try runCLI(args: ["info", path])
        #expect(output.contains("Name"))
    }
    #endif

    #if EnableMLT
    @Test(.timeLimit(.minutes(1)))
    func infoOnMlt() throws {
        let path = try generateSmallMlt().path
        let output = try runCLI(args: ["info", "-x", "0", "-y", "0", "-z", "0", path])
        #expect(output.contains("Name"))
    }
    #endif

    #if EnableMVT
    @Test(.timeLimit(.minutes(1)))
    func infoWithProperty() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["info", "-p", "class", mvtPath])
        #expect(output.contains("class"))
    }
    #endif

    #if EnableMVT
    @Test(.timeLimit(.minutes(1)))
    func infoTablesAcceptWhitespace() throws {
        let mvtPath = testDataDir.appendingPathComponent("14_8716_8015.vector.mvt").path
        let output = try runCLI(args: ["info", "-i", "features, property=class", mvtPath])
        #expect(output.contains("Features"))
        #expect(output.contains("Property"))
        #expect(output.contains("hospital"))
    }
    #endif

}
