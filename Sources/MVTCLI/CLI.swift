import ArgumentParser
import Foundation
import Logging
import MVTTools

/// The main entry point for the `mvt` command line tool.
///
/// Provides subcommands for inspecting, converting, and working with
/// MVT/MLT vector tiles, GeoJSON, GPX, Shapefile, and GeoPackage files.
@main
struct CLI: AsyncParsableCommand {

    /// A shared logger instance used by CLI commands when verbose mode is enabled.
    static let logger = Logger(label: "mvt")

    static let configuration = CommandConfiguration(
        commandName: "mvt",
        abstract: "A utility for inspecting and working with vector tiles (MVT/MLT), GeoJSON, GPX, FIT, CSV, Shapefile, and GeoPackage files.",
        discussion: """
        A x/y/z tile coordinate is needed for encoding/decoding MVT/MLT tiles.
        This tile coordinate can be extracted from the path/URL if it's either in the form '/z/x/y' or 'z_x_y'.
        Tile coordinates are not necessary for GeoJSON, GPX, FIT, CSV, Shapefile, and GeoPackage files (a tile coordinate will be calculated from the bounding box).

        Examples:
        - Tests/MVTToolsTests/TestData/14_8716_8015.vector.mvt
        - https://demotiles.maplibre.org/tiles/2/2/1.pbf
        """,
        version: cliVersion,
        subcommands: [
            Dump.self,
            Info.self,
            Query.self,
            Merge.self,
            Import.self,
            Export.self,
            Load.self,
            Rezoom.self,
        ],
        defaultSubcommand: Dump.self)

}

/// An error type used to represent recoverable CLI operation failures.
struct CLIError: LocalizedError {

    /// A human-readable description of the error.
    let errorDescription: String?

    /// Creates a CLI error with the given description.
    /// - Parameter errorDescription: A description of the error.
    init(_ errorDescription: String) {
        self.errorDescription = errorDescription
    }
}

/// Parsable arguments that capture optional x, y, and z tile coordinates.
///
/// Coordinates can be supplied directly via `--x`, `--y`, `--z` options, or
/// extracted automatically from file paths or URLs using `parseXYZ(fromPaths:)`.
struct XYZOptions: ParsableArguments {

    @Option(
        name: .short,
        help: "Tile x coordinate, if it can't be extracted from the path.")
    var x: Int?

    @Option(
        name: .short,
        help: "Tile y coordinate, if it can't be extracted from the path.")
    var y: Int?

    @Option(
        name: .short,
        help: "Tile zoom level, if it can't be extracted from the path.")
    var z: Int?

    /// Extracts x, y, and z tile coordinates from file paths or URLs when
    /// they were not provided explicitly on the command line.
    ///
    /// This method searches each path for patterns like `/z/x/y` or `z_x_y`
    /// and fills in any missing coordinate values. If coordinates are still
    /// missing after scanning all paths, validation is performed to ensure
    /// they are within valid tile range for the given zoom level.
    ///
    /// - Parameter paths: An array of file paths or URLs to scan for tile
    ///   coordinate patterns.
    /// - Returns: A tuple `(x, y, z)` of validated tile coordinates.
    /// - Throws: `CLIError` if coordinates cannot be determined or are
    ///   outside the valid range for the given zoom level.
    mutating func parseXYZ(
        fromPaths paths: [String]
    ) throws -> (x: Int, y: Int, z: Int) {
        for path in paths {
            guard x == nil
                    || y == nil
                    || z == nil
            else { break }

            let urlParts = path.extractingGroupsUsingPattern("\\/(\\d+)\\/(\\d+)\\/(\\d+)(?:\\/|\\.)", caseInsensitive: false)
            if urlParts.count >= 3 {
                if let partX = Int(urlParts[1]),
                   let partY = Int(urlParts[2]),
                   let partZ = Int(urlParts[0])
                {
                    x = partX
                    y = partY
                    z = partZ
                }
            }
            else {
                let pathParts = path.extractingGroupsUsingPattern("(\\d+)_(\\d+)_(\\d+)", caseInsensitive: false)
                if pathParts.count >= 3 {
                    if let partX = Int(pathParts[1]),
                       let partY = Int(pathParts[2]),
                       let partZ = Int(pathParts[0])
                    {
                        x = partX
                        y = partY
                        z = partZ
                    }
                }
            }
        }

        guard let x, let y, let z else {
            throw CLIError("Need z, x and y")
        }

        guard x >= 0 else { throw CLIError("x must be >= 0") }
        guard y >= 0 else { throw CLIError("y must be >= 0") }
        guard z >= 0 else { throw CLIError("z must be >= 0") }

        let maximumTileCoordinate = 1 << z
        if x >= maximumTileCoordinate { throw CLIError("x at zoom \(z) must be smaller than \(maximumTileCoordinate)") }
        if y >= maximumTileCoordinate { throw CLIError("y at zoom \(z) must be smaller than \(maximumTileCoordinate)") }

        return (x, y, z)
    }

}

/// Parsable arguments shared across CLI subcommands.
///
/// Provides common options such as `--verbose` and a helper for parsing
/// file or URL paths.
struct Options: ParsableArguments {

    @Flag(
        name: .shortAndLong,
        help: "Print some debug info.")
    var verbose = false

    /// Parses a path string into a `URL`, handling both remote URLs and
    /// local file paths.
    ///
    /// - Parameters:
    ///   - path: A string containing either an HTTP/HTTPS URL or a local
    ///     file path.
    ///   - checkPathExistence: When `true` (the default), verifies that a
    ///     local file path refers to an existing resource.
    /// - Returns: A `URL` representing the parsed location.
    /// - Throws: `CLIError` if the URL is malformed or the file does not
    ///   exist (when `checkPathExistence` is `true`).
    func parseUrl(
        fromPath path: String,
        checkPathExistence: Bool = true
    ) throws -> URL {
        let url: URL
        if path.hasPrefix("http") {
            guard let parsedUrl = URL(string: path) else {
                throw CLIError("\(path) is not a valid URL")
            }
            url = parsedUrl
        }
        else {
            url = URL(fileURLWithPath: path)
            if checkPathExistence {
                guard try url.checkResourceIsReachable() else {
                    throw CLIError("The file '\(path)' doesn't exist.")
                }
            }
        }

        return url
    }

}
