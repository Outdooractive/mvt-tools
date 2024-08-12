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

        static let configuration = CommandConfiguration(abstract: "Merge any number of vector tiles or GeoJSONs")

        @Option(name: .shortAndLong, help: "Output file (optional, default is console).")
        var output: String?

        @Option(name: .long, help: "Output file format (optional, one of 'auto', 'geojson', 'mvt').")
        var format: OutputFormat = .auto

        @Flag(name: .shortAndLong, help: "Force overwrite an existing --output file.")
        var forceOverwrite = false

        @Flag(name: .shortAndLong, help: "Append to an existing --output file.")
        var append = false

        @Option(name: .shortAndLong, help: "Merge only the specified layer (can be repeated).")
        var layer: [String] = []

        @Flag(name: .shortAndLong, help: "Pretty-print the output GeoJSON.")
        var prettyPrint = false

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "Vector tiles or GeoJSONs to merge (file or URL)",
            completion: .file(extensions: ["pbf", "mvt"]))
        var other: [String] = []

        mutating func run() async throws {
            let layerAllowlist = layer.nonempty

            let (x, y, z) = try xyzOptions.parseXYZ(fromPaths: [output].trimmed() + other)

            var outputUrl: URL?
            if let output {
                outputUrl = URL(fileURLWithPath: output)
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

            var outputFormatToUse: OutputFormat = format
            var tile: VectorTile?
            if append,
               let outputUrl,
               (try? outputUrl.checkResourceIsReachable()) ?? false
            {
                if let mvtTile = VectorTile(contentsOf: outputUrl, x: x, y: y, z: z, logger: options.verbose ? CLI.logger : nil) {
                    tile = mvtTile

                    if outputFormatToUse == .geojson, !forceOverwrite {
                        throw CLIError("Existing file is mvt, but selected output format is GeoJSON (use --force-overwrite to overwrite existing files)")
                    }
                    if outputFormatToUse == .auto {
                        outputFormatToUse = .mvt
                    }
                }
                else if let geoJsonTile = VectorTile(contentsOfGeoJson: outputUrl, logger: options.verbose ? CLI.logger : nil) {
                    tile = geoJsonTile

                    if outputFormatToUse == .mvt, !forceOverwrite {
                        throw CLIError("Existing file is GeoJSON, but selected output format is mvt (use --force-overwrite to overwrite existing files)")
                    }
                    if outputFormatToUse == .auto {
                        outputFormatToUse = .geojson
                    }
                }
            }
            if tile == nil {
                tile = VectorTile(x: x, y: y, z: z, logger: options.verbose ? CLI.logger : nil)
            }
            guard var tile else {
                throw CLIError("Failed to create a tile [\(x),\(y)]@\(z)")
            }

            if options.verbose {
                if let outputUrl {
                    print("Merging into tile '\(outputUrl.lastPathComponent)' [\(x),\(y)]@\(z)")
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

                guard let otherTile = VectorTile(contentsOf: otherUrl, x: x, y: y, z: z, layerWhitelist: layerAllowlist, logger: options.verbose ? CLI.logger : nil)
                        ?? VectorTile(contentsOfGeoJson: otherUrl, layerWhitelist: layerAllowlist, logger: options.verbose ? CLI.logger : nil)
                else {
                    throw CLIError("Failed to parse the tile at '\(path)'")
                }

                if outputFormatToUse == .auto {
                    switch otherTile.origin {
                    case .geoJson: outputFormatToUse = .geojson
                    default: outputFormatToUse = .mvt
                    }
                }

                if options.verbose {
                    print("- \(otherUrl.lastPathComponent) (\(otherTile.origin)")
                }

                tile.merge(otherTile)
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
