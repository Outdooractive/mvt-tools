import ArgumentParser
import Foundation
import GISTools
import Logging
import MVTTools

extension CLI {

    /// A command that rezooms (overzooms or underzooms) one or more
    /// source tiles into a single output tile at a target zoom level.
    ///
    /// Each source tile must be an ancestor or descendant of the target
    /// tile. Features are re-projected and clipped to the target tile's
    /// bounding box at encode time.
    struct Rezoom: AsyncParsableCommand {

        static let configuration = CommandConfiguration(
            commandName: "rezoom",
            abstract: "Overzoom or underzoom source tiles into a single output tile at a target zoom level",
            discussion: """
            Each source tile must be an ancestor or descendant of the target tile. \
            Source tiles that are not related to the target are silently skipped \
            (use --strict to abort instead).

            Target tile coordinates can be specified with --target-x, --target-y, \
            and --target-z, or inferred from the --output file path (e.g. \
            '3_2_2.mvt' or '3/2/2.mvt').

            Source tile coordinates are resolved from each file's path or with \
            --x, --y, --z.

            Examples:
              mvt rezoom --output ./tiles/3_2_2.mvt source_2_1_1.mvt
              mvt rezoom --target-z 3 --target-x 2 --target-y 2 \\
                  --output out.mvt --strict source.mvt
            """)

        @Option(
            name: .customLong("target-x"),
            help: "Target tile x coordinate (or inferred from --output path).")
        var targetX: Int?

        @Option(
            name: .customLong("target-y"),
            help: "Target tile y coordinate (or inferred from --output path).")
        var targetY: Int?

        @Option(
            name: .customLong("target-z"),
            help: "Target tile zoom level (or inferred from --output path).")
        var targetZ: Int?

        @Option(
            name: [.short, .customLong("output")],
            help: "Output file.",
            completion: .file(extensions: ["pbf", "mvt", "mlt", "json", "geojson", "gpx", "shp", "gpkg"]))
        var outputFile: String?

        @Option(
            name: [.customShort("O"), .long],
            help: "Output file format (optional, one of 'auto', 'geojson', 'mvt', 'mlt', 'gpx', 'shapefile', 'geopackage').")
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
            name: .customLong("strict"),
            help: "Abort if any source tile is not an ancestor or descendant of the target.")
        var strict = false

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

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "Source tiles to rezoom (file or URL).",
            completion: .file(extensions: ["pbf", "mvt", "mlt", "geojson", "json", "gpx", "shp", "gpkg"]))
        var sources: [String] = []

        mutating func run() async throws {
            // 1. Resolve target coordinates
            var targetXYZOptions = XYZOptions()
            targetXYZOptions.x = targetX
            targetXYZOptions.y = targetY
            targetXYZOptions.z = targetZ

            let targetXYZ: (x: Int, y: Int, z: Int)
            if let outputFile {
                let outputUrl = URL(fileURLWithPath: outputFile)
                targetXYZ = try targetXYZOptions.parseXYZ(fromPaths: [outputUrl.path])
            }
            else {
                guard let x = targetX, let y = targetY, let z = targetZ else {
                    throw CLIError("Target coordinates must be specified with --target-x, --target-y, --target-z or inferred from --output path.")
                }
                targetXYZ = (x: x, y: y, z: z)
            }

            if options.verbose {
                print("Target tile: \(targetXYZ.z)/\(targetXYZ.x)/\(targetXYZ.y)")
            }

            // 2. Validate output file
            var outputUrl: URL?
            if let outputFile {
                outputUrl = URL(fileURLWithPath: outputFile)
                if let outputUrl, (try? outputUrl.checkResourceIsReachable()) ?? false {
                    if forceOverwrite {
                        if options.verbose {
                            print("Existing file '\(outputUrl.lastPathComponent)' will be overwritten")
                        }
                    }
                    else {
                        throw CLIError("Output file must not exist (use --force-overwrite to overwrite existing files)")
                    }
                }
                // Create parent directories if needed
                let parent = outputUrl!.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }

            // 3. Load source tiles
            let layerAllowlist = layer.asSet.subtracting(dropLayer).asArray.nonempty
            let layerDenylist = dropLayer.asSet.subtracting(layer).asArray.nonempty

            var loadedSources: [VectorTile] = []
            for path in sources {
                let sourceUrl = try options.parseUrl(fromPath: path)
                let inputFormat = try TileFormat.resolve(
                    url: sourceUrl,
                    xyzOptions: &xyzOptions,
                    verbose: options.verbose)

                let effectiveAllowlist: [String]? = inputFormat.supportsInputLayerProperty && disableInputLayerProperty
                    ? nil
                    : layerAllowlist

                guard var sourceTile = try await inputFormat.loadTile(
                    from: sourceUrl,
                    layerAllowlist: effectiveAllowlist,
                    layerProperty: disableInputLayerProperty ? nil : propertyName,
                    logger: options.verbose ? CLI.logger : nil)
                else { throw CLIError("Failed to parse the tile at '\(path)'") }

                if let layerDenylist {
                    for droppedLayer in layerDenylist {
                        sourceTile.removeLayer(droppedLayer)
                    }
                }

                // Strict mode: check ancestry before adding
                if strict {
                    let sourceMap = MapTile(x: sourceTile.x, y: sourceTile.y, z: sourceTile.z)
                    let targetMap = MapTile(x: targetXYZ.x, y: targetXYZ.y, z: targetXYZ.z)
                    guard sourceMap.isRelated(to: targetMap) else {
                        throw CLIError("Source tile \(sourceTile.z)/\(sourceTile.x)/\(sourceTile.y) is not an ancestor or descendant of target \(targetXYZ.z)/\(targetXYZ.x)/\(targetXYZ.y) (use --strict to abort, omit to skip).")
                    }
                }

                if options.verbose {
                    print("- \(sourceUrl.lastPathComponent) (\(sourceTile.z)/\(sourceTile.x)/\(sourceTile.y))")
                }

                loadedSources.append(sourceTile)
            }

            // 4. Rezoom
            let result = VectorTile.rezoom(
                loadedSources,
                toTargetX: targetXYZ.x,
                targetY: targetXYZ.y,
                targetZ: targetXYZ.z)

            if options.verbose {
                print("Rezoomed \(loadedSources.count) source(s) into target \(targetXYZ.z)/\(targetXYZ.x)/\(targetXYZ.y) (\(result.layerNames.count) layers)")
            }

            // 5. Determine output format
            var resolvedOutputFormat: TileFormat = outputFormat ?? .geoJson(layerProperty: nil)
            if outputFormat == nil, let outputUrl {
                if let extFormat = TileFormat(url: outputUrl) {
                    resolvedOutputFormat = extFormat
                }
                else {
                    switch outputUrl.pathExtension.lowercased() {
                    case "mvt", "pbf": resolvedOutputFormat = .mvt(x: targetXYZ.x, y: targetXYZ.y, z: targetXYZ.z)
                    case "mlt": resolvedOutputFormat = .mlt(x: targetXYZ.x, y: targetXYZ.y, z: targetXYZ.z)
                    default: break
                    }
                }
            }

            // 6. Build export options
            var exportOptions = VectorTile.ExportOptions()

            if let bufferPixels, bufferPixels > 0 {
                exportOptions.bufferSize = .pixel(bufferPixels)
            }
            else if let bufferExtents, bufferExtents > 0 {
                exportOptions.bufferSize = .extent(bufferExtents)
            }
            else {
                switch resolvedOutputFormat {
                case .geoJson, .gpx, .shapefile, .geopackage:
                    exportOptions.bufferSize = .extent(0)
                default:
                    exportOptions.bufferSize = .extent(512)
                }
            }

            if outputUrl != nil {
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
            }

            if let simplifyMeters, simplifyMeters > 0 {
                exportOptions.simplifyFeatures = .meters(Double(simplifyMeters))
            }
            else if let simplifyExtents, simplifyExtents > 0 {
                exportOptions.simplifyFeatures = .extent(simplifyExtents)
            }

            if options.verbose {
                print("Output options:")
                print("  - File format: \(resolvedOutputFormat)")
                print("  - Buffer size: \(exportOptions.bufferSize)")
                print("  - Compression: \(exportOptions.compression)")
                print("  - Simplification: \(exportOptions.simplifyFeatures)")
            }

            // 7. Write output
            if let outputUrl {
                try await CLI.writeTile(
                    result,
                    format: resolvedOutputFormat,
                    to: outputUrl,
                    options: exportOptions,
                    prettyPrint: prettyPrint,
                    propertyName: disableOutputLayerProperty ? nil : propertyName)
            }
            else if let data = result.toGeoJson(
                prettyPrinted: prettyPrint,
                layerProperty: disableOutputLayerProperty ? nil : propertyName,
                options: exportOptions)
            {
                print(String(data: data, encoding: .utf8) ?? "", terminator: "")
                print()
            }

            if options.verbose {
                print("Done.")
            }
        }

    }

}