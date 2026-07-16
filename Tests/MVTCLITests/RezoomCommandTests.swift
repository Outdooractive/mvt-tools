import Foundation
import GISTools
import MVTTools
import Testing

struct RezoomCommandTests {

    // MARK: - Helpers

    /// Path to the real MVT test data tile at z=14/x=8716/y=8015.
    private static let sourceMVT: String = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MVTToolsTests")
            .appendingPathComponent("TestData")
            .appendingPathComponent("14_8716_8015.vector.mvt")
            .path
    }()

    // MARK: - Tests

    @Test(.timeLimit(.minutes(1)))
    func rezoomOverzoom() throws {
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_rezoom_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // Overzoom z=14/8716/8015 → z=15/17432/16030 (NW child)
        let outputFile = outputDir.appendingPathComponent("15_17432_16030.mvt")
        let (_, _, exitCode) = try runCLIWithStderr(args: [
            "rezoom", "--target-z", "15", "--target-x", "17432", "--target-y", "16030",
            "--output", outputFile.path, Self.sourceMVT,
        ])

        #expect(exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: outputFile.path))

        // Verify the output has features by running info on it
        let infoOutput = try runCLI(args: ["info", outputFile.path])
        #expect(infoOutput.contains("test") || infoOutput.contains("road") || infoOutput.contains("building") || infoOutput.contains("landuse"))
    }

    @Test(.timeLimit(.minutes(1)))
    func rezoomUnderzoom() throws {
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_rezoom_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // Underzoom z=14/8716/8015 → z=13/4358/4007 (parent)
        let outputFile = outputDir.appendingPathComponent("13_4358_4007.mvt")
        let (_, _, exitCode) = try runCLIWithStderr(args: [
            "rezoom", "--target-z", "13", "--target-x", "4358", "--target-y", "4007",
            "--output", outputFile.path, Self.sourceMVT,
        ])

        #expect(exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: outputFile.path))

        let infoOutput = try runCLI(args: ["info", outputFile.path])
        #expect(infoOutput.contains("road") || infoOutput.contains("building") || infoOutput.contains("landuse"))
    }

    @Test(.timeLimit(.minutes(1)))
    func rezoomStrictFails() throws {
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_rezoom_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // Non-ancestor: z=14/8716/8015 → z=15/0/0 (not a child)
        let outputFile = outputDir.appendingPathComponent("15_0_0.mvt")
        let (_, stderr, exitCode) = try runCLIWithStderr(args: [
            "rezoom", "--target-z", "15", "--target-x", "0", "--target-y", "0",
            "--strict", "--output", outputFile.path, Self.sourceMVT,
        ])

        #expect(exitCode != 0)
        #expect(stderr.contains("not an ancestor or descendant"))
    }

    @Test(.timeLimit(.minutes(1)))
    func rezoomNonStrictSkips() throws {
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_rezoom_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // Non-ancestor without --strict → should succeed with empty output
        let outputFile = outputDir.appendingPathComponent("15_0_0.mvt")
        let (stdout, _, exitCode) = try runCLIWithStderr(args: [
            "rezoom", "--target-z", "15", "--target-x", "0", "--target-y", "0",
            "--output", outputFile.path, Self.sourceMVT,
        ])

        #expect(exitCode == 0)
        // The output file should exist but be empty (0 features)
        // The stdout/console output for MVT is binary, so just check the file exists
        #expect(FileManager.default.fileExists(atPath: outputFile.path))
        _ = stdout
    }

    @Test(.timeLimit(.minutes(1)))
    func rezoomInferTargetFromOutput() throws {
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_rezoom_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // Output filename 15_17432_16030.mvt → infer target z=15, x=17432, y=16030
        let outputFile = outputDir.appendingPathComponent("15_17432_16030.mvt")
        let (_, _, exitCode) = try runCLIWithStderr(args: [
            "rezoom", "--output", outputFile.path, Self.sourceMVT,
        ])

        #expect(exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: outputFile.path))

        let infoOutput = try runCLI(args: ["info", outputFile.path])
        #expect(infoOutput.contains("road") || infoOutput.contains("building") || infoOutput.contains("landuse"))
    }

    @Test(.timeLimit(.minutes(1)))
    func rezoomMissingTargetErrors() throws {
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_rezoom_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // No --target-x/y/z and output path has no tile coords
        let outputFile = outputDir.appendingPathComponent("output.mvt")
        let (_, stderr, exitCode) = try runCLIWithStderr(args: [
            "rezoom", "--output", outputFile.path, Self.sourceMVT,
        ])

        #expect(exitCode != 0)
        #expect(stderr.contains("Target coordinates") || stderr.contains("z, x and y"))
    }

    @Test(.timeLimit(.minutes(1)))
    func rezoomVerbose() throws {
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mvt_rezoom_out_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let outputFile = outputDir.appendingPathComponent("15_17432_16030.mvt")
        let (stdout, _, exitCode) = try runCLIWithStderr(args: [
            "rezoom", "--output", outputFile.path, "--verbose", Self.sourceMVT,
        ])

        #expect(exitCode == 0)
        #expect(stdout.contains("Target tile:"))
        #expect(stdout.contains("Done."))
    }

}