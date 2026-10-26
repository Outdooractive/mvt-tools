import ArgumentParser
import Foundation
import GISTools
import MVTTools

extension CLI {

    /// Reproject one supported input file to a target CRS and output format.
    struct Reproject: AsyncParsableCommand {

        static let configuration = CommandConfiguration(
            commandName: "reproject",
            abstract: "Reproject an MVT, MLT, GeoJSON, CSV, Shapefile, GeoPackage, GPX, or FIT file",
            discussion: """
            --output-projection is required. Use --input-projection to override
            the source CRS; this is useful for formats without CRS metadata or
            when a file's embedded CRS is wrong.

            For GeoJSON, --input-projection reinterprets raw coordinates in the
            selected CRS. It does not reproject from EPSG:4326.

            Examples:
              mvt reproject -ip 3857 -op 4326 --output out.geojson 14/8716/8015.mvt
              mvt reproject -ip 4326 -op 3857 --output out.mvt input.geojson
            """)

        @Option(
            name: [.short, .customLong("output")],
            help: "Output file.",
            completion: .file(extensions: ["pbf", "mvt", "mlt", "json", "geojson", "gpx", "fit", "csv", "shp", "gpkg"]))
        var outputFile: String

        @Option(
            name: [.customShort("O"), .long],
            help: "Output file format (optional, inferred from the output extension).")
        var outputFormat: TileFormat?

        @Option(
            name: [.customLong("oC", withSingleDash: true), .long],
            help: "Output compression level, between 0=none and 9=best.")
        var compressionLevel: Int?

        @Option(
            name: [.customLong("oBe", withSingleDash: true), .long],
            help: "Output buffer extents for tiles of size \(VectorTile.ExportOptions.extent).")
        var bufferExtents: Int?

        @Option(
            name: [.customLong("oBp", withSingleDash: true), .long],
            help: "Output buffer pixels for tiles of size \(VectorTile.ExportOptions.tileSize).")
        var bufferPixels: Int?

        @Option(
            name: [.customLong("oSe", withSingleDash: true), .long],
            help: "Simplify output features using tile extents.")
        var simplifyExtents: Int?

        @Option(
            name: [.customLong("oSm", withSingleDash: true), .long],
            help: "Simplify output features using meters.")
        var simplifyMeters: Int?

        @Flag(
            name: .shortAndLong,
            help: "Overwrite an existing output file.")
        var forceOverwrite = false

        @Flag(
            name: .shortAndLong,
            help: "Pretty-print GeoJSON output.")
        var prettyPrint = false

        @Option(
            name: .shortAndLong,
            help: "Filter to the specified layers (can be repeated).")
        var layer: [String] = []

        @Option(
            name: .shortAndLong,
            help: "Drop the specified layer (can be repeated).")
        var dropLayer: [String] = []

        @Option(
            name: [.customShort("P"), .long],
            help: "Feature property to use for the layer name in input and output GeoJSONs/GPX.")
        var propertyName: String = VectorTile.defaultLayerPropertyName

        @Flag(
            name: [.customLong("Di", withSingleDash: true), .long],
            help: "Don't parse the layer name from Feature properties in the input GeoJSONs/GPX.")
        var disableInputLayerProperty = false

        @Flag(
            name: [.customLong("Do", withSingleDash: true), .long],
            help: "Don't add the layer name as a Feature property in the output GeoJSONs.")
        var disableOutputLayerProperty = false

        @OptionGroup
        var projectionOptions: ProjectionOptions

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @OptionGroup
        var csvReadOptions: CSVReadCLIOptions

        @OptionGroup
        var csvWriteOptions: CSVWriteCLIOptions

        @Argument(
            help: "Input file.",
            completion: .file(extensions: ["pbf", "mvt", "mlt", "geojson", "json", "fit", "gpx", "csv", "shp", "gpkg"]))
        var path: String

        mutating func run() async throws {
            guard let outputProjection = projectionOptions.output else {
                throw CLIError("--output-projection is required")
            }

            let inputURL = try options.parseUrl(fromPath: path)
            let outputURL = URL(fileURLWithPath: outputFile)
            if (try? outputURL.checkResourceIsReachable()) ?? false, !forceOverwrite {
                throw CLIError("Output file must not exist (use --force-overwrite to overwrite)")
            }
            try? FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)

            let inputFormat = try TileFormat.resolve(
                url: inputURL,
                xyzOptions: &xyzOptions,
                verbose: options.verbose)
            let layerAllowlist = layer.asSet.subtracting(dropLayer).asArray.nonempty
            let layerDenylist = dropLayer.asSet.subtracting(layer).asArray.nonempty
            let effectiveAllowlist: [String]? = inputFormat.supportsInputLayerProperty && disableInputLayerProperty
                ? nil
                : layerAllowlist

            var tile = try await inputFormat.loadTile(
                from: inputURL,
                layerAllowlist: effectiveAllowlist,
                layerProperty: disableInputLayerProperty ? nil : propertyName,
                csvReadOptions: csvReadOptions.options,
                inputProjection: projectionOptions.input,
                logger: options.verbose ? CLI.logger : nil)

            if let layerDenylist {
                for droppedLayer in layerDenylist {
                    tile.removeLayer(droppedLayer)
                }
            }

            tile = try tile.projected(to: outputProjection)

            var resolvedOutputFormat: TileFormat
            if let outputFormat {
                resolvedOutputFormat = outputFormat
            }
            else if let detected = TileFormat(url: outputURL) {
                resolvedOutputFormat = detected
            }
            else {
                switch outputURL.pathExtension.lowercased() {
                case "mvt", "pbf":
                    resolvedOutputFormat = .mvt(x: tile.x, y: tile.y, z: tile.z)
                case "mlt":
                    resolvedOutputFormat = .mlt(x: tile.x, y: tile.y, z: tile.z)
                default:
                    throw CLIError(
                        "Unrecognized output extension '.\(outputURL.pathExtension)'. "
                        + "Use --output-format to select a format.")
                }
            }

            var exportOptions = VectorTile.ExportOptions()
            if let bufferPixels, bufferPixels > 0 {
                exportOptions.bufferSize = .pixel(bufferPixels)
            }
            else if let bufferExtents, bufferExtents > 0 {
                exportOptions.bufferSize = .extent(bufferExtents)
            }
            else {
                switch resolvedOutputFormat {
                case .geoJson, .fit, .gpx, .csv, .shapefile, .geopackage:
                    exportOptions.bufferSize = .extent(0)
                default:
                    exportOptions.bufferSize = .extent(512)
                }
            }

            if let compressionLevel {
                if compressionLevel > 0 {
                    exportOptions.compression = .level(max(0, min(9, compressionLevel)))
                }
            }
            else if case .geoJson = resolvedOutputFormat {
                // no default compression for GeoJSON
            }
            else {
                exportOptions.compression = .level(9)
            }
            if let simplifyMeters, simplifyMeters > 0 {
                exportOptions.simplifyFeatures = .meters(Double(simplifyMeters))
            }
            else if let simplifyExtents, simplifyExtents > 0 {
                exportOptions.simplifyFeatures = .extent(simplifyExtents)
            }

            try await CLI.writeTile(
                tile,
                format: resolvedOutputFormat,
                to: outputURL,
                options: exportOptions,
                csvWriteOptions: csvWriteOptions.options(
                    delimiter: csvReadOptions.delimiter.value),
                prettyPrint: prettyPrint,
                propertyName: disableOutputLayerProperty ? nil : propertyName)

            if options.verbose {
                print("Reprojected \(inputURL.lastPathComponent) to \(outputProjection) as \(resolvedOutputFormat)")
            }
        }

    }

}
