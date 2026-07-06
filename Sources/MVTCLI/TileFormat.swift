import ArgumentParser
import Foundation
import Logging
import MVTTools

/// Supported vector tile file formats.
enum TileFormat: Equatable {

    case mvt(x: Int, y: Int, z: Int)
    case mlt(x: Int, y: Int, z: Int)
    case geoJson(layerProperty: String?)
    case gpx
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
        case .gpx: return ["gpx"]
        case .shapefile: return ["shp"]
        case .geopackage: return ["gpkg"]
        }
    }

    /// Whether this format supports named layers on input.
    var supportsInputLayers: Bool {
        switch self {
        case .mvt, .mlt, .geoJson, .gpx, .geopackage: true
        case .shapefile: false
        }
    }

    /// Whether this format can use the layer property for input routing.
    var supportsInputLayerProperty: Bool {
        switch self {
        case .geoJson, .gpx: true
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
    ///   - logger: Optional logger instance.
    /// - Returns: A loaded tile, or `nil` if parsing failed.
    func loadTile(
        from url: URL,
        layerAllowlist: [String]? = nil,
        layerProperty: String? = VectorTile.defaultLayerPropertyName,
        geopackageTable: String? = nil,
        logger: Logger? = nil
    ) async throws -> VectorTile? {
        switch self {
        case .mvt(let x, let y, let z):
            return VectorTile(
                contentsOfMVT: url,
                x: x, y: y, z: z,
                layerAllowlist: layerAllowlist,
                logger: logger)

        case .mlt(let x, let y, let z):
            return VectorTile(
                contentsOfMLT: url,
                x: x, y: y, z: z,
                layerAllowlist: layerAllowlist,
                logger: logger)

        case .geoJson(let defaultLayerProperty):
            return VectorTile(
                contentsOfGeoJson: url,
                layerProperty: layerProperty ?? defaultLayerProperty,
                layerAllowlist: layerAllowlist,
                logger: logger)

        case .gpx:
            return VectorTile(
                contentsOfGPX: url,
                layerProperty: layerProperty,
                layerAllowlist: layerAllowlist,
                logger: logger)

        case .shapefile:
            return VectorTile(
                shapefile: url,
                logger: logger)

        case .geopackage:
            return try await VectorTile(
                geopackage: url,
                table: geopackageTable,
                logger: logger)
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
                + "Supported: mvt, pbf, mlt, geojson, json, gpx, shp, gpkg")
        }
    }

}

// MARK: - CustomStringConvertible

extension TileFormat: CustomStringConvertible {

    var description: String {
        switch self {
        case .mvt: return "mvt"
        case .mlt: return "mlt"
        case .geoJson: return "geojson"
        case .gpx: return "gpx"
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
        case "gpx": self = .gpx
        case "shp", "shapefile": self = .shapefile
        case "gpkg", "geopackage": self = .geopackage
        default: return nil
        }
    }

}
