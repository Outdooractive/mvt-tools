import Foundation
import GISToolsCSV
import MVTTools

// MARK: - Shared tile writing helper

extension CLI {

    /// Writes a tile to a file in the given format.
    ///
    /// Shared by ``Merge``/``Import``/``Export`` (via ``MergeOptions``) and
    /// ``Rezoom`` to avoid duplicating the format-dispatch logic.
    ///
    /// - Parameters:
    ///   - tile: The tile to write.
    ///   - format: The target file format.
    ///   - url: The destination file URL.
    ///   - options: Export options (buffer, compression, simplification).
    ///   - csvWriteOptions: Options controlling CSV output.
    ///   - prettyPrint: Whether to pretty-print GeoJSON output.
    ///   - propertyName: The layer property name for GeoJSON output, or `nil`
    ///     to omit the layer property.
    static func writeTile(
        _ tile: VectorTile,
        format: TileFormat,
        to url: URL,
        options: VectorTile.ExportOptions,
        csvWriteOptions: CSVWriteOptions = CSVWriteOptions(),
        prettyPrint: Bool,
        propertyName: String?
    ) async throws {
        switch format {
        case .geoJson:
            guard let data = tile.toGeoJson(
                prettyPrinted: prettyPrint,
                layerProperty: propertyName,
                options: options)
            else { throw CLIError("Failed to extract the tile data as GeoJSON") }
            try data.write(to: url, options: .atomic)

        case .mvt:
            tile.writeMVT(to: url, options: options)

        case .mlt:
            tile.writeMLT(to: url, options: options)

        case .fit:
            guard tile.writeFIT(to: url, options: options) else {
                throw CLIError("Failed to write FIT")
            }

        case .gpx:
            guard tile.writeGPX(to: url, options: options) else {
                throw CLIError("Failed to write GPX")
            }

        case .csv:
            guard tile.writeCSV(to: url, writeOptions: csvWriteOptions, options: options) else {
                throw CLIError("Failed to write CSV")
            }

        case .shapefile:
            try tile.writeShapefile(to: url, options: options)

        case .geopackage:
            try await tile.writeGeoPackage(to: url, options: options)
        }
    }

}
