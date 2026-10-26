import ArgumentParser
import Foundation
import GISTools
import GISToolsCSV
import Logging
import MVTTools

/// Supported vector tile file formats.
enum TileFormat: Equatable {

    case mvt(x: Int, y: Int, z: Int)
    case mlt(x: Int, y: Int, z: Int)
    case geoJson(layerProperty: String?)
    case fit
    case gpx
    case csv
    case shapefile
    case geopackage

    /// Detect the format from a file URL's extension.
    /// Returns `nil` for formats that require explicit tile coordinates (MVT, MLT).
    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "geojson", "json":
            self = .geoJson(layerProperty: nil)
        case "gpx":
            self = .gpx
        case "csv":
            self = .csv
        case "fit":
            self = .fit
        case "shp":
            self = .shapefile
        case "gpkg":
            self = .geopackage
        default:
            return nil
        }
    }

    /// The file extensions associated with this format.
    var fileExtensions: [String] {
        switch self {
        case .mvt: return ["mvt", "pbf"]
        case .mlt: return ["mlt"]
        case .geoJson: return ["geojson", "json"]
        case .fit: return ["fit"]
        case .gpx: return ["gpx"]
        case .csv: return ["csv"]
        case .shapefile: return ["shp"]
        case .geopackage: return ["gpkg"]
        }
    }

    /// Whether this format supports named layers on input.
    var supportsInputLayers: Bool {
        switch self {
        case .mvt, .mlt, .geoJson, .fit, .gpx, .csv, .geopackage: true
        case .shapefile: false
        }
    }

    /// Whether this format can use the layer property for input routing.
    var supportsInputLayerProperty: Bool {
        switch self {
        case .geoJson, .gpx, .csv: true
        default: false
        }
    }

}

// MARK: - Loading

extension TileFormat {

    /// Load a `VectorTile` from the given URL using this format.
    ///
    /// - Parameters:
    ///   - url: The input file URL.
    ///   - layerAllowlist: Optional list of layer names to include.
    ///   - layerProperty: Property name used for layer routing (GeoJSON/GPX).
    ///   - geopackageTable: When set, only this table is loaded from a GeoPackage.
    ///   - csvReadOptions: Options controlling CSV input.
    ///   - inputProjection: Optional source CRS override.
    ///   - logger: Optional logger instance.
    /// - Returns: A loaded tile.
    /// - Throws: ``VectorTileError``, ``GeoPackageError``, or ``CLIError``.
    func loadTile(
        from url: URL,
        layerAllowlist: [String]? = nil,
        layerProperty: String? = VectorTile.defaultLayerPropertyName,
        geopackageTable: String? = nil,
        csvReadOptions: CSVReadOptions = CSVReadOptions(),
        inputProjection: Projection? = nil,
        logger: Logger? = nil
    ) async throws -> VectorTile {
        switch self {
        case .mvt(let x, let y, let z):
            return try VectorTile(
                contentsOfMVT: url,
                x: x, y: y, z: z,
                projection: inputProjection ?? .epsg4326,
                layerAllowlist: layerAllowlist,
                logger: logger)

        case .mlt(let x, let y, let z):
            #if EnableMLT
            return try VectorTile(
                contentsOfMLT: url,
                x: x, y: y, z: z,
                projection: inputProjection ?? .epsg4326,
                layerAllowlist: layerAllowlist,
                logger: logger)
            #else
            throw unavailableError
            #endif

        case .geoJson(let defaultLayerProperty):
            return try VectorTile(
                contentsOfGeoJson: url,
                layerProperty: layerProperty ?? defaultLayerProperty,
                layerAllowlist: layerAllowlist,
                projection: inputProjection,
                logger: logger)

        case .fit:
            #if EnableFIT
            guard inputProjection == nil || inputProjection == .epsg4326 else {
                throw CLIError("FIT input is always EPSG:4326; use --output-projection to reproject")
            }
            return try VectorTile(
                contentsOfFIT: url,
                layerProperty: layerProperty,
                layerAllowlist: layerAllowlist,
                logger: logger)
            #else
            throw unavailableError
            #endif

        case .gpx:
            #if EnableGPX
            guard inputProjection == nil || inputProjection == .epsg4326 else {
                throw CLIError("GPX input is always EPSG:4326; use --output-projection to reproject")
            }
            return try VectorTile(
                contentsOfGPX: url,
                layerProperty: layerProperty,
                layerAllowlist: layerAllowlist,
                logger: logger)
            #else
            throw unavailableError
            #endif

        case .csv:
            #if EnableCSV
            var readOptions = csvReadOptions
            if let inputProjection {
                readOptions.projection = inputProjection
            }
            return try VectorTile(
                contentsOfCSV: url,
                readOptions: readOptions,
                layerProperty: layerProperty,
                layerAllowlist: layerAllowlist,
                logger: logger)
            #else
            throw unavailableError
            #endif

        case .shapefile:
            #if EnableShapefile
            let tile = try VectorTile(
                shapefile: url,
                logger: logger)
            if let inputProjection, inputProjection != tile.projection {
                return try tile.retagged(to: inputProjection)
            }
            return tile
            #else
            throw unavailableError
            #endif

        case .geopackage:
            #if EnableGeoPackage
            let tile = try await VectorTile(
                geopackage: url,
                table: geopackageTable,
                logger: logger)
            if let inputProjection, inputProjection != tile.projection {
                return try tile.retagged(to: inputProjection)
            }
            return tile
            #else
            throw unavailableError
            #endif
        }
    }

}

// MARK: - Resolution

extension TileFormat {

    /// Resolve the input format from a URL and available tile coordinates.
    ///
    /// - Parameters:
    ///   - url: The input file URL.
    ///   - xyzOptions: Tile coordinate options (may be mutated to fill in path-derived values).
    ///   - verbose: When `true`, prints diagnostic info.
    /// - Returns: The resolved tile format.
    /// - Throws: `CLIError` if the format cannot be determined.
    static func resolve(
        url: URL,
        xyzOptions: inout XYZOptions,
        verbose: Bool = false
    ) throws -> TileFormat {
        // Step 1: try extension-based detection
        if let format = TileFormat(url: url) {
            if verbose {
                print("Detected format: \(format)")
            }
            return format
        }

        // Step 2: try to get tile coordinates from path or explicit flags
        let xyz = try xyzOptions.parseXYZ(fromPaths: [url.path])

        switch url.pathExtension.lowercased() {
        case "mvt", "pbf":
            return .mvt(x: xyz.x, y: xyz.y, z: xyz.z)
        case "mlt":
            return .mlt(x: xyz.x, y: xyz.y, z: xyz.z)
        default:
            throw CLIError(
                "Unrecognized file extension '.\(url.pathExtension)'. "
                + "Supported: mvt, pbf, mlt, geojson, json, fit, gpx, csv, shp, gpkg")
        }
    }

}

// MARK: - Build availability

extension TileFormat {

    /// The error thrown when the receiver's format is not compiled into this build.
    ///
    /// Optional formats are gated behind package traits (see `Package.swift`).
    /// A format may still be recognized on the command line — e.g. via its file
    /// extension or `--output-format` — even though its coder was left out of
    /// the build; reading or writing it then fails with this error.
    var unavailableError: CLIError {
        CLIError(
            "Format '\(self)' is not available in this build "
            + "(enable the corresponding package trait)")
    }

}

// MARK: - CustomStringConvertible

extension TileFormat: CustomStringConvertible {

    var description: String {
        switch self {
        case .mvt: return "mvt"
        case .mlt: return "mlt"
        case .geoJson: return "geojson"
        case .fit: return "fit"
        case .gpx: return "gpx"
        case .csv: return "csv"
        case .shapefile: return "shapefile"
        case .geopackage: return "geopackage"
        }
    }

}

// MARK: - ExpressibleByArgument (for `--output-format` flags)

// Coordinates are placeholder values — they are not used when writing output.
extension TileFormat: ExpressibleByArgument {

    init?(argument: String) {
        switch argument.lowercased() {
        case "mvt": self = .mvt(x: 0, y: 0, z: 0)
        case "mlt": self = .mlt(x: 0, y: 0, z: 0)
        case "geojson", "json": self = .geoJson(layerProperty: nil)
        case "fit": self = .fit
        case "gpx": self = .gpx
        case "csv": self = .csv
        case "shp", "shapefile": self = .shapefile
        case "gpkg", "geopackage": self = .geopackage
        default: return nil
        }
    }

}
