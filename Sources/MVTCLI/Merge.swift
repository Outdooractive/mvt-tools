import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    struct Merge: AsyncParsableCommand {

        enum OutputFormat: String, ExpressibleByArgument {
            case auto
            case geojson
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
            help: "Merge only the specified layers (can be repeated).")
        var layer: [String] = []

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
            let layerAllowlist = layer.nonempty

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
                    contentsOf: outputUrl,
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

                guard tile != nil else { throw CLIError("Failed to load the resource at '\(outputUrl.path())'") }
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
                    print("Merging into \(tile.origin) tile '\(outputUrl.lastPathComponent)' [\(tile.x),\(tile.y)]@\(tile.z)")
                }
                else {
                    print("Dumping the merged tile to the console")
                }

                print("Property name: \(propertyName)")

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
                    || !disableInputLayerProperty,
                   let layerAllowlist
                {
                    print("Layers: '\(layerAllowlist.joined(separator: ","))'")
                }

                print("Output format: \(outputFormatToUse)")
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
                    contentsOf: otherUrl,
                    x: x,
                    y: y,
                    z: z,
                    layerWhitelist: layerAllowlist,
                    logger: options.verbose ? CLI.logger : nil)
                {
                    otherTile = other
                }
                else if let other = VectorTile(
                    contentsOfGeoJson: otherUrl,
                    layerProperty: disableInputLayerProperty ? nil : propertyName,
                    layerWhitelist: disableInputLayerProperty ? nil : layerAllowlist,
                    logger: options.verbose ? CLI.logger : nil)
                {
                    otherTile = other
                }

                guard let otherTile else { throw CLIError("Failed to parse the tile at '\(path)'") }

                if outputFormatToUse == .auto {
                    switch otherTile.origin {
                    case .geoJson: outputFormatToUse = .geojson
                    case .mvt, .none: outputFormatToUse = .mvt
                    }
                }

                if options.verbose {
                    print("- \(otherUrl.lastPathComponent) (\(otherTile.origin))")
                }

                tile.merge(otherTile, ignoreTileCoordinateMismatch: true)
            }

            // Export

            let bufferSize: VectorTile.ExportOptions.BufferSizeOptions = if let bufferPixels, bufferPixels > 0 {
                .pixel(bufferPixels)
            }
            else if let bufferExtents, bufferExtents > 0 {
                .extent(bufferExtents)
            }
            else if outputFormatToUse == .geojson {
                .extent(0)
            }
            else {
                .extent(512)
            }

            var compression: VectorTile.ExportOptions.CompressionOptions = .no
            if outputUrl != nil { // don't gzip output to the console
                if let compressionLevel {
                    if compressionLevel > 0 {
                        compression = .level(max(0, min(9, compressionLevel)))
                    }
                }
                else if outputFormatToUse == .mvt {
                    compression = .level(9)
                }
            }

            let simplifyFeatures: VectorTile.ExportOptions.SimplifyFeaturesOptions = if let simplifyMeters, simplifyMeters > 0 {
                .meters(Double(simplifyMeters))
            }
            else if let simplifyExtents, simplifyExtents > 0 {
                .extent(simplifyExtents)
            }
            else {
                .no
            }

            if options.verbose {
                print("Output options:")
                print("  - Buffer size: \(bufferSize)")
                print("  - Compression: \(compression)")
                print("  - Simplification: \(simplifyFeatures)")
            }

            let exportOptions: VectorTile.ExportOptions = .init(
                bufferSize: bufferSize,
                compression: compression,
                simplifyFeatures: simplifyFeatures)

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
                    tile.write(
                        to: outputUrl,
                        options: exportOptions)
                }
            }
            else if let resultGeoJson = tile.toGeoJson(
                prettyPrinted: prettyPrint,
                layerProperty: disableOutputLayerProperty ? nil : propertyName,
                options: exportOptions)
            {
                print(resultGeoJson, terminator: "")
                print()
            }

            if options.verbose {
                print("Done.")
            }
        }

    }

}
