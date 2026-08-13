import ArgumentParser
import Foundation
import MVTTools

// MARK: - Shared options for merge / import

extension CLI {

    /// Options shared by the ``Merge`` and ``Import`` commands.
    ///
    /// CSV input and output are configured with the `--csv-*` options.
    struct MergeOptions: ParsableArguments {

        @Option(
            name: [.short, .customLong("output")],
            help: "Output file (optional, default is console).",
            completion: .file(extensions: ["pbf", "mvt", "mlt", "json", "geojson", "fit", "gpx", "csv", "shp", "gpkg"]))
        var outputFile: String?

        @Option(
            name: [.customShort("O"), .long],
            help: "Output file format (optional, one of 'auto', 'geojson', 'mvt', 'mlt', 'fit', 'gpx', 'csv', 'shapefile', 'geopackage').")
        var outputFormat: TileFormat?

        @Option(
            name: [.customLong("oC", withSingleDash: true), .long],
            help: "Output file compression level, between 0=none to 9=best. (default: 9 for mvt/mlt, none for geojson)")
        var compressionLevel: Int?

        @Option(
            name: [.customLong("oBe", withSingleDash: true), .long],
            help: "Output buffer extents for tiles of size \(VectorTile.ExportOptions.extent). (default: 512 for mvt/mlt, none for geojson)")
        var bufferExtents: Int?

        @Option(
            name: [.customLong("oBp", withSingleDash: true), .long],
            help: "Output buffer pixels for tiles of size \(VectorTile.ExportOptions.tileSize). Overrides 'buffer-extents'.")
        var bufferPixels: Int?

        @Option(
            name: [.customLong("oSe", withSingleDash: true), .long],
            help: "Simplify output features using tile extents. (default: no simplification)")
        var simplifyExtents: Int?

        @Option(
            name: [.customLong("oSm", withSingleDash: true), .long],
            help: "Simplify output features using meters. Overrides 'simplify-extents'.")
        var simplifyMeters: Int?

        @Flag(
            name: .shortAndLong,
            help: "Force overwrite an existing 'output' file.")
        var forceOverwrite = false

        @Flag(
            name: .shortAndLong,
            help: "Append to an existing 'output' file (MVT/MLT only).")
        var append = false

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
            help: """
            Feature property to use for the layer name in input and output GeoJSONs/GPX. \
            For GPX input, defaults to "gpx_type" (splits waypoints/routes/tracks).
            """)
        var propertyName: String = VectorTile.defaultLayerPropertyName

        @Option(
            name: [.customShort("L"), .long],
            help: """
            Fallback layer name for imported features. Used when 'property-name' is \
            not set on a feature or when --disable-input-layer-property is active.
            """)
        var layerName: String?

        @Flag(
            name: [.customLong("Di", withSingleDash: true), .long],
            help: "Don't parse the layer name (option 'property-name') from Feature properties in the input GeoJSONs/GPX.")
        var disableInputLayerProperty = false

        @Flag(
            name: [.customLong("Do", withSingleDash: true), .long],
            help: "Don't add the layer name (option 'property-name') as a Feature property in the output GeoJSONs.")
        var disableOutputLayerProperty = false

        @Flag(
            name: .shortAndLong,
            help: "Pretty-print the output GeoJSON.")
        var prettyPrint = false

        @Argument(
            help: "Files to merge (file or URL).",
            completion: .file(extensions: ["pbf", "mvt", "mlt", "geojson", "json", "fit", "gpx", "csv", "shp", "gpkg"]))
        var other: [String] = []

        @OptionGroup
        var csvReadOptions: CSVReadCLIOptions

        @OptionGroup
        var csvWriteOptions: CSVWriteCLIOptions

    }

}

extension CLI.MergeOptions {

    /// Shared execution logic for ``CLI.Merge`` and ``CLI.Import``.
    static func run(
        _ mergeOptions: CLI.MergeOptions,
        xyzOptions: inout XYZOptions,
        cliOptions: Options
    ) async throws {
        let layerAllowlist = mergeOptions.layer.asSet.subtracting(mergeOptions.dropLayer).asArray.nonempty
        let layerDenylist = mergeOptions.dropLayer.asSet.subtracting(mergeOptions.layer).asArray.nonempty

        var outputUrl: URL?
        if let outputFile = mergeOptions.outputFile {
            outputUrl = URL(fileURLWithPath: outputFile)
            if let outputUrl, (try? outputUrl.checkResourceIsReachable()) ?? false {
                if mergeOptions.forceOverwrite {
                    if cliOptions.verbose {
                        print("Existing file '\(outputUrl.lastPathComponent)' will be overwritten")
                    }
                }
                else if mergeOptions.append {
                    if cliOptions.verbose {
                        print("Existing file '\(outputUrl.lastPathComponent)' will be appended")
                    }
                }
                else {
                    throw CLIError("Output file must not exist (use --force-overwrite or --append to overwrite existing files)")
                }
            }
        }

        var resolvedOutputFormat: TileFormat = mergeOptions.outputFormat ?? .geoJson(layerProperty: nil)
        var tile: VectorTile?

        let xyz = try? xyzOptions.parseXYZ(fromPaths: [mergeOptions.outputFile].trimmed() + mergeOptions.other)
        let (x, y, z) = (xyz?.x, xyz?.y, xyz?.z)

        // When appending, load the existing output file
        if mergeOptions.append,
           let outputUrl,
           (try? outputUrl.checkResourceIsReachable()) ?? false
        {
            let existingFormat = TileFormat(url: outputUrl) ?? resolvedOutputFormat
            tile = try? await existingFormat.loadTile(
                from: outputUrl,
                csvReadOptions: mergeOptions.csvReadOptions.options,
                logger: cliOptions.verbose ? CLI.logger : nil)
        }

        // Create an empty tile if nothing was loaded yet
        if tile == nil {
            tile = try VectorTile(
                x: x ?? 0,
                y: y ?? 0,
                z: z ?? 0,
                logger: cliOptions.verbose ? CLI.logger : nil)

            // If no tile coords and output is to console, default to GeoJSON output
            if x == nil || y == nil || z == nil {
                if case .geoJson = resolvedOutputFormat {} else {
                    resolvedOutputFormat = .geoJson(layerProperty: nil)
                }
            }
        }

        guard var tile else { throw CLIError("Failed to create a tile") }

        if cliOptions.verbose {
            if let outputUrl {
                print("Merging into \(tile.origin == .none ? "new" : tile.origin.rawValue) tile '\(outputUrl.lastPathComponent)' [\(tile.x),\(tile.y)]@\(tile.z)")
            }
            else {
                print("Dumping the merged tile to the console")
            }

            print("Layer property name: \(mergeOptions.propertyName)")
            if mergeOptions.disableInputLayerProperty {
                print("  - disable input layer property")
            }
            if mergeOptions.disableOutputLayerProperty {
                print("  - disable output layer property")
            }
            if let layerName = mergeOptions.layerName {
                print("Fallback layer name: \(layerName)")
            }

            if let layerAllowlist {
                print("Allowed layers: '\(layerAllowlist.sorted().joined(separator: ","))'")
            }
            if let layerDenylist {
                print("Dropped layers: '\(layerDenylist.sorted().joined(separator: ","))'")
            }
        }

        // Load and merge each input file
        for path in mergeOptions.other {
            let otherUrl: URL
            if path.hasPrefix("http") {
                guard let parsedUrl = URL(string: path) else {
                    throw CLIError("\(path) is not a valid URL")
                }
                otherUrl = parsedUrl
            }
            else {
                otherUrl = URL(fileURLWithPath: path)
                guard try otherUrl.checkResourceIsReachable() else {
                    throw CLIError("The file '\(path)' doesn't exist.")
                }
            }

            let inputFormat = try TileFormat.resolve(url: otherUrl, xyzOptions: &xyzOptions)
            let effectiveAllowlist: [String]? = inputFormat.supportsInputLayerProperty && mergeOptions.disableInputLayerProperty
            ? nil
            : layerAllowlist

            var otherTile = try await inputFormat.loadTile(
                from: otherUrl,
                layerAllowlist: effectiveAllowlist,
                layerProperty: mergeOptions.disableInputLayerProperty ? nil : mergeOptions.propertyName,
                csvReadOptions: mergeOptions.csvReadOptions.options,
                logger: cliOptions.verbose ? CLI.logger : nil)

            if let layerDenylist {
                for droppedLayer in layerDenylist {
                    otherTile.removeLayer(droppedLayer)
                }
            }

            // Auto-detect output format if no explicit output format was given
            if mergeOptions.outputFormat == nil {
                if let outputUrl {
                    if let extFormat = TileFormat(url: outputUrl) {
                        resolvedOutputFormat = extFormat
                    }
                    else {
                        switch outputUrl.pathExtension.lowercased() {
                        case "mvt", "pbf": resolvedOutputFormat = .mvt(x: x ?? 0, y: y ?? 0, z: z ?? 0)
                        case "mlt":       resolvedOutputFormat = .mlt(x: x ?? 0, y: y ?? 0, z: z ?? 0)
                        default: break
                        }
                    }
                }
                else if x != nil, y != nil, z != nil {
                    resolvedOutputFormat = .mvt(x: x!, y: y!, z: z!)
                }
            }

            if cliOptions.verbose {
                print("- \(otherUrl.lastPathComponent) (\(otherTile.origin))")
            }

            tile.merge(otherTile, ignoreTileCoordinateMismatch: true)
        }

        // Export

        var exportOptions = VectorTile.ExportOptions()

        if let bufferPixels = mergeOptions.bufferPixels, bufferPixels > 0 {
            exportOptions.bufferSize = .pixel(bufferPixels)
        }
        else if let bufferExtents = mergeOptions.bufferExtents, bufferExtents > 0 {
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

        if outputUrl != nil { // don't gzip output to the console
            if let compressionLevel = mergeOptions.compressionLevel {
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
        }

        if let simplifyMeters = mergeOptions.simplifyMeters, simplifyMeters > 0 {
            exportOptions.simplifyFeatures = .meters(Double(simplifyMeters))
        }
        else if let simplifyExtents = mergeOptions.simplifyExtents, simplifyExtents > 0 {
            exportOptions.simplifyFeatures = .extent(simplifyExtents)
        }

        if cliOptions.verbose {
            print("Output options:")
            if case .geoJson = resolvedOutputFormat, outputUrl == nil {
                print("  - Pretty print: \(mergeOptions.prettyPrint)")
            }
            print("  - File format: \(resolvedOutputFormat)")
            print("  - Buffer size: \(exportOptions.bufferSize)")
            print("  - Compression: \(exportOptions.compression)")
            print("  - Simplification: \(exportOptions.simplifyFeatures)")
        }

        if let outputUrl {
            try await CLI.writeTile(
                tile,
                format: resolvedOutputFormat,
                to: outputUrl,
                options: exportOptions,
                csvWriteOptions: mergeOptions.csvWriteOptions.options(
                    delimiter: mergeOptions.csvReadOptions.delimiter.value),
                prettyPrint: mergeOptions.prettyPrint,
                propertyName: mergeOptions.disableOutputLayerProperty ? nil : mergeOptions.propertyName)
        }
        else if let resultGeoJson = tile.toGeoJson(
            prettyPrinted: mergeOptions.prettyPrint,
            layerProperty: mergeOptions.disableOutputLayerProperty ? nil : mergeOptions.propertyName,
            options: exportOptions)
        {
            print(String(data: resultGeoJson, encoding: .utf8) ?? "", terminator: "")
            print()
        }

        if cliOptions.verbose {
            print("Done.")
        }
    }

}
