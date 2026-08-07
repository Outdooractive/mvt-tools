import Foundation
import GISTools
import GISToolsFIT
import GISToolsShapefile
import MVTTools
import Testing

// MARK: - Helpers

struct CLIProcessError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { self.errorDescription = message }
}

func isNativeExecutable(at url: URL) -> Bool {
    guard FileManager.default.isExecutableFile(atPath: url.path) else { return false }
#if os(macOS)
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    guard let magic = try? handle.read(upToCount: 4) else { return false }
    let machoMagics: Set<[UInt8]> = [
        [0xFE, 0xED, 0xFA, 0xCE], [0xCE, 0xFA, 0xED, 0xFE],
        [0xFE, 0xED, 0xFA, 0xCF], [0xCF, 0xFA, 0xED, 0xFE],
        [0xCA, 0xFE, 0xBA, 0xBE], [0xBE, 0xBA, 0xFE, 0xCA],
    ]
    return machoMagics.contains(Array(magic))
#else
    return true
#endif
}

var mvtExec: URL {
    if let builtProducts = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
        let candidate = URL(fileURLWithPath: builtProducts).appendingPathComponent("mvt")
        if isNativeExecutable(at: candidate) { return candidate }
    }
#if os(macOS)
    if let library = try? FileManager.default.url(
        for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    {
        let derivedData = library.appendingPathComponent("Developer/Xcode/DerivedData")
        if let enumerator = FileManager.default.enumerator(
            at: derivedData, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        {
            for case let subdir as URL in enumerator {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: subdir.path, isDirectory: &isDir),
                      isDir.boolValue, subdir.lastPathComponent.hasPrefix("mvt-tools-") else { continue }
                let candidate = subdir.appendingPathComponent("Build/Products/Debug").appendingPathComponent("mvt")
                if isNativeExecutable(at: candidate) { return candidate }
            }
        }
    }
#endif
    let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let buildRoot = packageRoot.appendingPathComponent(".build")
    let debugDir = buildRoot.appendingPathComponent("debug")
    if let linkDest = try? FileManager.default.destinationOfSymbolicLink(atPath: debugDir.path) {
        let resolved = buildRoot.appendingPathComponent(linkDest).appendingPathComponent("mvt")
        if isNativeExecutable(at: resolved) { return resolved }
    }
    let hostTriples: [String]
#if arch(arm64)
    hostTriples = ["arm64-apple-macosx", "aarch64-apple-macosx"]
#elseif arch(x86_64)
    hostTriples = ["x86_64-apple-macosx"]
#else
    hostTriples = []
#endif
    for triple in hostTriples {
        let candidate = buildRoot.appendingPathComponent(triple).appendingPathComponent("debug").appendingPathComponent("mvt")
        if isNativeExecutable(at: candidate) { return candidate }
    }
    guard let enumerator = FileManager.default.enumerator(
        at: buildRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    else { return debugDir.appendingPathComponent("mvt") }
    var bestCandidate: URL?
    for case let subdir as URL in enumerator {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: subdir.path, isDirectory: &isDir), isDir.boolValue else { continue }
        let candidate = subdir.appendingPathComponent("debug").appendingPathComponent("mvt")
        guard isNativeExecutable(at: candidate) else { continue }
        if subdir.lastPathComponent.contains("macosx") || subdir.lastPathComponent.contains("apple") { return candidate }
        bestCandidate = candidate
    }
    return bestCandidate ?? debugDir.appendingPathComponent("mvt")
}

var testDataDir: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("MVTToolsTests").appendingPathComponent("TestData")
}

@discardableResult
func runCLI(args: [String]) throws -> String {
    let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mvt_stdout_\(UUID().uuidString).txt")
    FileManager.default.createFile(atPath: tempUrl.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: tempUrl) }
    let stdoutHandle = try FileHandle(forWritingTo: tempUrl)
    let process = Process()
    process.executableURL = mvtExec
    process.arguments = args
    process.standardOutput = stdoutHandle
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    try stdoutHandle.close()
    return String(data: try Data(contentsOf: tempUrl), encoding: .utf8) ?? ""
}

/// Runs the `mvt` CLI with the given arguments, capturing both stdout and
/// stderr, and returns the combined output plus the exit code.
///
/// Unlike `runCLI`, this helper preserves stderr (useful for verifying
/// `--verbose` output and soft-failure messages) and reports the process
/// exit code so callers can assert on non-zero exits.
///
/// - Parameter args: The command-line arguments to pass to `mvt`.
/// - Returns: A tuple of `(stdout, stderr, exitCode)`.
func runCLIWithStderr(args: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
    let stdoutUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mvt_stdout_\(UUID().uuidString).txt")
    let stderrUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mvt_stderr_\(UUID().uuidString).txt")
    FileManager.default.createFile(atPath: stdoutUrl.path, contents: nil)
    FileManager.default.createFile(atPath: stderrUrl.path, contents: nil)
    defer {
        try? FileManager.default.removeItem(at: stdoutUrl)
        try? FileManager.default.removeItem(at: stderrUrl)
    }
    let stdoutHandle = try FileHandle(forWritingTo: stdoutUrl)
    let stderrHandle = try FileHandle(forWritingTo: stderrUrl)
    let process = Process()
    process.executableURL = mvtExec
    process.arguments = args
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle
    try process.run()
    process.waitUntilExit()
    try stdoutHandle.close()
    try stderrHandle.close()
    let stdout = String(data: try Data(contentsOf: stdoutUrl), encoding: .utf8) ?? ""
    let stderr = String(data: try Data(contentsOf: stderrUrl), encoding: .utf8) ?? ""
    return (stdout, stderr, process.terminationStatus)
}

// MARK: - Test data generators

func generateSmallGeoJson() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_\(UUID().uuidString).geojson")
    let fc = FeatureCollection([
        Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1), properties: ["name": "A"]),
        Feature(Point(Coordinate3D(latitude: 30.0, longitude: 40.0)), id: .int(2), properties: ["name": "B"]),
    ])
    try fc.asJsonData()!.write(to: url)
    return url
}

func generateSmallGpx() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_\(UUID().uuidString).gpx")
    let gpx = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="test">
      <wpt lat="10.0" lon="20.0"><name>PointA</name></wpt>
      <wpt lat="30.0" lon="40.0"><name>PointB</name></wpt>
    </gpx>
    """
    try gpx.data(using: .utf8)!.write(to: url)
    return url
}

func generateSmallFit() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_\(UUID().uuidString).fit")
    let coords: [Coordinate3D] = [
        Coordinate3D(latitude: 10.0, longitude: 20.0, altitude: 100.0),
        Coordinate3D(latitude: 10.001, longitude: 20.001, altitude: 110.0),
        Coordinate3D(latitude: 10.002, longitude: 20.002, altitude: 120.0),
    ]
    let multiLine = MultiLineString(unchecked: [LineString(unchecked: coords)])
    var feature = Feature(multiLine)
    feature.properties["fit_type"] = "record"
    feature.properties["heart_rate"] = 120
    feature.properties["sport"] = "Cycling"
    feature.properties["total_distance"] = Double(100.0)
    feature.properties["total_calories"] = Int(5)
    feature.properties["total_elapsed_time"] = Double(60.0)
    feature.properties["start_time"] = UInt32(1_000_000)
    feature.properties["fit_heart_rates"] = [120, 125, 130]
    feature.properties["fit_cadences"] = [80, 85, 90]
    feature.properties["fit_powers"] = [200, 250, 280]
    feature.properties["fit_speeds"] = [5.0, 5.5, 6.0]
    feature.properties["fit_temperatures"] = [22.0, 23.0, 24.0]
    var fc = FeatureCollection([feature])
    fc.foreignMembers["fit_device"] = ["manufacturer": 1, "product": 0, "type": 4]
    fc.foreignMembers["fit_activity"] = ["type": 0, "num_sessions": 1]
    let data = try fc.fitData()
    try data.write(to: url)
    return url
}

func generateSmallShapefile() throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shp_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let shapefileUrl = dir.appendingPathComponent("points")
    let fc = FeatureCollection([
        Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1)),
        Feature(Point(Coordinate3D(latitude: 30.0, longitude: 40.0)), id: .int(2)),
    ])
    try ShapefileCoder.write(fc, to: shapefileUrl)
    return shapefileUrl.appendingPathExtension("shp")
}

func generateSmallGeoPackage() async throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_\(UUID().uuidString).gpkg")
    var tile = try VectorTile(x: 0, y: 0, z: 0, projection: .epsg4326)
    tile.setFeatures([
        Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1), properties: ["name": "A"]),
    ], for: "layer_a")
    tile.setFeatures([
        Feature(Point(Coordinate3D(latitude: 30.0, longitude: 40.0)), id: .int(2), properties: ["name": "B"]),
    ], for: "layer_b")
    try await tile.writeGeoPackage(to: url)
    return url
}

func generateSmallMlt(coord: Int = 0) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_\(UUID().uuidString).mlt")
    var tile = try VectorTile(x: coord, y: coord, z: 0, projection: .epsg4326)
    tile.setFeatures([
        Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1), properties: ["name": "A"]),
    ], for: "test")
    guard let data = tile.mltData() else { throw CLIProcessError("Failed to encode MLT") }
    try data.write(to: url)
    return url
}

func generateSmallMvt(coord: Int = 0) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_\(UUID().uuidString).mvt")
    var tile = try VectorTile(x: coord, y: coord, z: 0, projection: .epsg4326)
    tile.setFeatures([
        Feature(Point(Coordinate3D(latitude: 10.0, longitude: 20.0)), id: .int(1), properties: ["name": "A"]),
    ], for: "test")
    guard let data = tile.mvtData() else { throw CLIProcessError("Failed to encode MVT") }
    try data.write(to: url)
    return url
}

@discardableResult
func assertGeoJsonFile(at url: URL) throws -> FeatureCollection {
    let data = try Data(contentsOf: url)
    #expect(!data.isEmpty)
    return try #require(FeatureCollection(jsonData: data))
}

func assertMvtFile(at url: URL) throws {
    let data = try Data(contentsOf: url)
    #expect(!data.isEmpty)
}
