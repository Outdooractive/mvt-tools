import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    /// A command that merges multiple vector tiles or GeoJSON files into one.
    ///
    /// Supports both MVT and GeoJSON input and output, with layer filtering,
    /// output compression, feature simplification, and customizable buffer sizes.
    struct Merge: AsyncParsableCommand {

        /// The output format for the merged result.
        enum OutputFormat: String, ExpressibleByArgument {

            /// Automatically detect the format from the output file extension or input data.
            case auto

            /// Output in GeoJSON format.
            case geojson

            /// Output in MVT (Mapbox Vector Tile) format.
            case mvt
        }

        static let configuration = CommandConfiguration(
            abstract: "Merge any number of MVTs or GeoJSONs",
            discussion: "Note: Vector tiles should all have the same tile coordinate or strange things will happen.")

        @Option(
            name: [.short, .customLong("output")],
            help: "Output file (optional, default is console).",
            completion: .file(extensions: ["pbf", "mvt", "json", "geojson"]))
        var outputFile: String?

        @Option(
            name: [.customShort("O"), .long],
            help: "Output file format (optional, one of 'auto', 'geojson', 'mvt').")
        var outputFormat: OutputFormat = .auto

        @Option(
            name: [.customLong("oC", withSingleDash: true), .long],
            help: "Output file compression level, between 0=none to 9=best. (default: 9 for mvt, none for geojson)")
        var compressionLevel: Int?

        @Option(
            name: [.customLong("oBe", withSingleDash: true), .long],
            help: "Output buffer extents for tiles of size \(VectorTile.ExportOptions.extent). (default: 512 for mvt, none for geojson)")
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
            help: "Append to an existing 'output' file.")
        var append = false

        @Option(
            name: .shortAndLong,
            help: "Merge the specified layers (can be repeated).")
        var layer: [String] = []

        @Option(
            name: .shortAndLong,
            help: "Drop the specified layer (can be repeated).")
        var dropLayer: [String] = []

        @Option(
            name: [.customShort("P"), .long],
            help: "Feature property to use for the layer name in input and output GeoJSONs. Needed for filtering by layer.")
        var propertyName: String = VectorTile.defaultLayerPropertyName

        @Flag(
            name: [.customLong("Di", withSingleDash: true), .long],
            help: "Don't parse the layer name (option 'property-name') from Feature properties in the input GeoJSONs. Might speed up GeoJSON parsing considerably.")
        var disableInputLayerProperty: Bool = false

        @Flag(
            name: [.customLong("Do", withSingleDash: true), .long],
            help: "Don't add the layer name (option 'property-name') as a Feature property in the output GeoJSONs.")
        var disableOutputLayerProperty: Bool = false

        @Flag(
            name: .shortAndLong,
            help: "Pretty-print the output GeoJSON.")
        var prettyPrint = false

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "Vector tiles or GeoJSONs to merge (file or URL).",
            completion: .file(extensions: ["pbf", "mvt", "json", "geojson"]))
        var other: [String] = []

        mutating func run() async throws {
            let layerAllowlist = layer.asSet.subtracting(dropLayer).asArray.nonempty
            let layerDenylist = dropLayer.asSet.subtracting(layer).asArray.nonempty

            var outputUrl: URL?
            if let outputFile {
                outputUrl = URL(fileURLWithPath: outputFile)
                if let outputUrl, (try? outputUrl.checkResourceIsReachable()) ?? false {
                    if forceOverwrite {
                        if options.verbose {
                            print("Existing file '\(outputUrl.lastPathComponent)' will be overwritten")
                        }
                    }
                    else if append {
                        if options.verbose {
                            print("Existing file '\(outputUrl.lastPathComponent)' will be appended")
                        }
                    }
                    else {
                        throw CLIError("Output file must not exist (use --force-overwrite or --append to overwrite existing files)")
                    }
                }
            }

            var outputFormatToUse: OutputFormat = outputFormat
            var tile: VectorTile?

            let xyz = try? xyzOptions.parseXYZ(fromPaths: [outputFile].trimmed() + other)
            let (x, y, z) = (xyz?.x, xyz?.y, xyz?.z)

            if append,
               let outputUrl,
               (try? outputUrl.checkResourceIsReachable()) ?? false
            {
                if let x,
                   let y,
                   let z,
                   let mvtTile = VectorTile(
                    contentsOfMVT: outputUrl,
                    x: x,
                    y: y,
                    z: z,
                    logger: options.verbose ? CLI.logger : nil)
                {
                    tile = mvtTile

                    if outputFormatToUse == .geojson, !forceOverwrite {
                        throw CLIError("Existing file is 'mvt', but selected output format is 'geojson' (use --force-overwrite to overwrite existing files)")
                    }
                    if outputFormatToUse == .auto {
                        outputFormatToUse = .mvt
                    }
                }
                else if let geoJsonTile = VectorTile(
                    contentsOfGeoJson: outputUrl,
                    layerProperty: disableInputLayerProperty ? nil : propertyName,
                    logger: options.verbose ? CLI.logger : nil)
                {
                    tile = geoJsonTile

                    if outputFormatToUse == .mvt, !forceOverwrite {
                        throw CLIError("Existing file is 'geojson', but selected output format is 'mvt' (use --force-overwrite to overwrite existing files)")
                    }
                    if outputFormatToUse == .auto {
                        outputFormatToUse = .geojson
                    }
                }

                guard tile != nil else { throw CLIError("Failed to load the resource at '\(outputUrl.path)'") }
            }

            if tile == nil {
                tile = VectorTile(
                    x: x ?? 0,
                    y: y ?? 0,
                    z: z ?? 0,
                    logger: options.verbose ? CLI.logger : nil)

                // Assume geoJson if we don't have tile coordinates here
                if x == nil || y == nil || z == nil {
                    outputFormatToUse = .geojson
                }
            }

            guard var tile else { throw CLIError("Failed to create a tile") }

            if options.verbose {
                if let outputUrl {
                    print("Merging into \(tile.origin == .none ? "new" : tile.origin.rawValue) tile '\(outputUrl.lastPathComponent)' [\(tile.x),\(tile.y)]@\(tile.z)")
                }
                else {
                    print("Dumping the merged tile to the console")
                }

                print("Layer property name: \(propertyName)")
                if disableInputLayerProperty {
                    print("  - disable input layer property")
                }
                if disableOutputLayerProperty {
                    print("  - disable output layer property")
                }

                if disableInputLayerProperty,
                   !disableOutputLayerProperty
                {
                    print("  - Warning: Default output layer names will be used with -Di")
                }

                if tile.origin == .mvt
                    || !disableInputLayerProperty
                {
                    if let layerAllowlist {
                        print("Allowed layers: '\(layerAllowlist.sorted().joined(separator: ","))'")
                    }
                    if let layerDenylist {
                        print("Dropped layers: '\(layerDenylist.sorted().joined(separator: ","))'")
                    }
                }
            }

            for path in other {
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

                var otherTile: VectorTile?
                if let x,
                   let y,
                   let z,
                   let other = VectorTile(
                    contentsOfMVT: otherUrl,
                    x: x,
                    y: y,
                    z: z,
                    layerAllowlist: layerAllowlist)
                {
                    otherTile = other
                }
                else if let other = VectorTile(
                    contentsOfGeoJson: otherUrl,
                    layerProperty: disableInputLayerProperty ? nil : propertyName,
                    layerAllowlist: disableInputLayerProperty ? nil : layerAllowlist)
                {
                    otherTile = other
                }

                if otherTile != nil, let layerDenylist {
                    for droppedLayer in layerDenylist {
                        otherTile?.removeLayer(droppedLayer)
                    }
                }

                guard let otherTile else { throw CLIError("Failed to parse the tile at '\(path)'") }

                if outputFormatToUse == .auto {
                    switch otherTile.origin {
                    case .geoJson, .gpx: outputFormatToUse = .geojson
                    case .mvt, .mlt, .shapefile, .none: outputFormatToUse = .mvt
                    }
                }

                if options.verbose {
                    print("- \(otherUrl.lastPathComponent) (\(otherTile.origin))")
                }

                tile.merge(otherTile, ignoreTileCoordinateMismatch: true)
            }

            // Export

            var exportOptions = VectorTile.ExportOptions()

            if let bufferPixels, bufferPixels > 0 {
                exportOptions.bufferSize = .pixel(bufferPixels)
            }
            else if let bufferExtents, bufferExtents > 0 {
                exportOptions.bufferSize = .extent(bufferExtents)
            }
            else if outputFormatToUse == .geojson {
                exportOptions.bufferSize = .extent(0)
            }
            else {
                exportOptions.bufferSize = .extent(512)
            }

            if outputUrl != nil { // don't gzip output to the console
                if let compressionLevel {
                    if compressionLevel > 0 {
                        exportOptions.compression = .level(max(0, min(9, compressionLevel)))
                    }
                }
                else if outputFormatToUse == .mvt {
                    exportOptions.compression = .level(9)
                }
            }

            if let simplifyMeters, simplifyMeters > 0 {
                exportOptions.simplifyFeatures = .meters(Double(simplifyMeters))
            }
            else if let simplifyExtents, simplifyExtents > 0 {
                exportOptions.simplifyFeatures = .extent(simplifyExtents)
            }

            if options.verbose {
                print("Output options:")
                if outputFormatToUse == .geojson || outputUrl == nil {
                    print("  - Pretty print: \(prettyPrint)")
                }
                print("  - File format: \(outputFormatToUse)")
                print("  - Buffer size: \(exportOptions.bufferSize)")
                print("  - Compression: \(exportOptions.compression)")
                print("  - Simplification: \(exportOptions.simplifyFeatures)")
            }

            if let outputUrl {
                if outputFormatToUse == .geojson {
                    if let data = tile.toGeoJson(
                        prettyPrinted: prettyPrint,
                        layerProperty: disableOutputLayerProperty ? nil : propertyName,
                        options: exportOptions)
                    {
                        try data.write(to: outputUrl, options: .atomic)
                    }
                }
                else {
                    tile.writeMVT(
                        to: outputUrl,
                        options: exportOptions)
                }
            }
            else if let resultGeoJson = tile.toGeoJson(
                prettyPrinted: prettyPrint,
                layerProperty: disableOutputLayerProperty ? nil : propertyName,
                options: exportOptions)
            {
                print(String(data: resultGeoJson, encoding: .utf8) ?? "", terminator: "")
                print()
            }

            if options.verbose {
                print("Done.")
            }
        }

    }

}
