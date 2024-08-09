import ArgumentParser
import Foundation
import GISTools
import MVTTools

extension CLI {

    struct Import: AsyncParsableCommand {

        static let configuration = CommandConfiguration(abstract: "Import some GeoJSONs into a vector tile")

        @Option(name: .shortAndLong, help: "Output file")
        var output: String

        @Flag(name: .shortAndLong, help: "Force overwrite an existing --output file")
        var forceOverwrite = false

        @Flag(name: .shortAndLong, help: "Append to an existing --output file")
        var append = false

        @Option(name: .shortAndLong, help: "Layer name in the vector tile. Can be used with --property-name as a fallback name")
        var layerName: String?

        @Option(name: .shortAndLong, help: "Feature property to use for the layer name in the vector tile. Fallback to --layer-name or a default. Will slow down things considerably")
        var propertyName: String?

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "GeoJSON resources to import (file or URL)",
            completion: .file(extensions: ["json", "geojson"]))
        var other: [String] = []

        mutating func run() async throws {
            let (x, y, z) = try xyzOptions.parseXYZ(fromPath: output)

            let outputUrl = URL(fileURLWithPath: output)
            if (try? outputUrl.checkResourceIsReachable()) ?? false {
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

            var tile: VectorTile?
            if append,
               (try? outputUrl.checkResourceIsReachable()) ?? false
            {
                tile = VectorTile(contentsOf: outputUrl, x: x, y: y, z: z, logger: options.verbose ? CLI.logger : nil)
            }
            if tile == nil {
                tile = VectorTile(x: x, y: y, z: z, logger: options.verbose ? CLI.logger : nil)
            }
            guard var tile else {
                throw CLIError("Failed to create a tile [\(x),\(y)]@\(z)")
            }

            if options.verbose {
                print("Import into tile '\(outputUrl.lastPathComponent)' [\(x),\(y)]@\(z)")
            }

            if options.verbose {
                if let layerName {
                    print("Import layer: \(layerName)")
                }
                if let propertyName {
                    print("Import layer feature property: \(propertyName)")
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

                guard let otherGeoJSON = FeatureCollection(contentsOf: otherUrl) else {
                    throw CLIError("Failed to parse the GeoJSON at '\(path)'")
                }

                print("- \(otherUrl.lastPathComponent)")

                tile.addGeoJson(geoJson: otherGeoJSON, layerName: layerName, propertyName: propertyName)
            }

            tile.write(
                to: outputUrl,
                options: .init(
                    bufferSize: .extent(512),
                    compression: .level(9),
                    simplifyFeatures: .no))

            if options.verbose {
                print("Done.")
            }
        }

    }

}
