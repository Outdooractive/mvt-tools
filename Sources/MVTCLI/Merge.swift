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
            discussion: "Vector tiles should all have the same tile coordinate, or you will get strange results.")

        @Option(name: [.short, .customLong("output")], help: "Output file (optional, default is console).")
        var outputFile: String?

        @Option(name: [.customShort("O"), .long], help: "Output file format (optional, one of 'auto', 'geojson', 'mvt').")
        var outputFormat: OutputFormat = .auto

        @Flag(name: .shortAndLong, help: "Force overwrite an existing --output file.")
        var forceOverwrite = false

        @Flag(name: .shortAndLong, help: "Append to an existing --output file.")
        var append = false

        @Option(name: .shortAndLong, help: "Merge only the specified layers (can be repeated).")
        var layer: [String] = []

        @Option(name: [.customShort("P"), .long], help: "Feature property to use for the layer name in the output GeoJSON.")
        var propertyName: String = VectorTile.defaultLayerPropertyName

        @Flag(name: [.customShort("D"), .long], help: "Don't add the layer name as a property to Features in the output GeoJSON.")
        var disableOutputLayerProperty: Bool = false

        @Flag(name: .shortAndLong, help: "Pretty-print the output GeoJSON.")
        var prettyPrint = false

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "Vector tiles or GeoJSONs to merge (file or URL)",
            completion: .file(extensions: ["pbf", "mvt", "json", "geojson"]))
        var other: [String] = []

        mutating func run() async throws {
            let layerAllowlist = layer.nonempty

            var outputUrl: URL?
            if let outputFile {
                outputUrl = URL(fileURLWithPath: outputFile)
                if let outputUrl, (try? outputUrl.checkResourceIsReachable()) ?? false {
                    if forceOverwrite {
                        print("Existing file '\(outputUrl.lastPathComponent)' will be overwritten")
                    }
                    else if append {
                        print("Existing file '\(outputUrl.lastPathComponent)' will be appended")
                    }
                    else {
                        throw CLIError("Output file must not exist (use --force-overwrite or --append to overwrite existing files)")
                    }
                }
            }

            var outputFormatToUse: OutputFormat = outputFormat
            var tile: VectorTile?

            let xyz = try? xyzOptions.parseXYZ(fromPaths: [outputFile].trimmed() + other)
            var (x, y, z) = (xyz?.x, xyz?.y, xyz?.z)

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
                        throw CLIError("Existing file is MVT, but selected output format is GeoJSON (use --force-overwrite to overwrite existing files)")
                    }
                    if outputFormatToUse == .auto {
                        outputFormatToUse = .mvt
                    }
                }
                else if let geoJsonTile = VectorTile(
                    contentsOfGeoJson: outputUrl,
                    layerProperty: propertyName,
                    logger: options.verbose ? CLI.logger : nil)
                {
                    tile = geoJsonTile
                    x = tile?.x
                    y = tile?.y
                    z = tile?.z

                    if outputFormatToUse == .mvt, !forceOverwrite {
                        throw CLIError("Existing file is GeoJSON, but selected output format is MVT (use --force-overwrite to overwrite existing files)")
                    }
                    if outputFormatToUse == .auto {
                        outputFormatToUse = .geojson
                    }
                }

                guard tile != nil else { throw CLIError("Failed to parse the resource at '\(outputUrl.path())'") }
            }

            guard let x, let y, let z else {
                throw CLIError("Need z, x and y")
            }

            if tile == nil {
                tile = VectorTile(
                    x: x,
                    y: y,
                    z: z,
                    logger: options.verbose ? CLI.logger : nil)
            }

            guard var tile else { throw CLIError("Failed to create a tile [\(x),\(y)]@\(z)") }

            if options.verbose {
                if let outputUrl {
                    print("Merging into \(tile.origin) tile '\(outputUrl.lastPathComponent)' [\(tile.x),\(tile.y)]@\(tile.z)")
                }
                else {
                    print("Dumping the merged tile to the console")
                }

                if let layerAllowlist {
                    print("Layers: '\(layerAllowlist.joined(separator: ","))'")
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

                guard let otherTile =
                        VectorTile(
                            contentsOf: otherUrl,
                            x: x,
                            y: y,
                            z: z,
                            layerWhitelist: layerAllowlist,
                            logger: options.verbose ? CLI.logger : nil)
                        ?? VectorTile(
                            contentsOfGeoJson: otherUrl,
                            layerProperty: propertyName,
                            layerWhitelist: layerAllowlist,
                            logger: options.verbose ? CLI.logger : nil)
                else { throw CLIError("Failed to parse the tile at '\(path)'") }

                if outputFormatToUse == .auto {
                    switch otherTile.origin {
                    case .geoJson: outputFormatToUse = .geojson
                    default: outputFormatToUse = .mvt
                    }
                }

                if options.verbose {
                    print("- \(otherUrl.lastPathComponent) (\(otherTile.origin))")
                }

                tile.merge(otherTile, ignoreTileCoordinateMismatch: true)
            }

            if let outputUrl {
                if outputFormatToUse == .geojson {
                    if let data = tile.toGeoJson(prettyPrinted: prettyPrint) {
                        try data.write(to: outputUrl, options: .atomic)
                    }
                }
                else {
                    tile.write(
                        to: outputUrl,
                        options: .init(
                            bufferSize: .extent(512),
                            compression: .level(9),
                            simplifyFeatures: .no))
                }
            }
            else if let resultGeoJson = tile.toGeoJson(prettyPrinted: prettyPrint) {
                print(resultGeoJson, terminator: "")
                print()
            }

            if options.verbose {
                print("Done.")
            }
        }

    }

}
