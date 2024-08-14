import ArgumentParser
import Foundation
import GISTools
import MVTTools

extension CLI {

    struct Import: AsyncParsableCommand {

        static let configuration = CommandConfiguration(abstract: "Import some GeoJSONs into a vector tile")

        @Option(name: [.short, .customLong("output")], help: "Output MVT file.")
        var outputFile: String

        @Flag(name: .shortAndLong, help: "Overwrite an existing 'output' file.")
        var forceOverwrite = false

        @Flag(name: .shortAndLong, help: "Append to an existing 'output' file.")
        var append = false

        @Option(name: [.customShort("L"), .long], help: "Layer name in the vector tile for the imported GeoJSON. Can be used with 'property-name' as a fallback name.")
        var layerName: String?

        @Option(name: [.customShort("P"), .long], help: "Feature property to use for the layer name in input GeoJSONs. Fallback to 'layer-name' or a default if the property is not present.")
        var propertyName: String = VectorTile.defaultLayerPropertyName

        @Flag(name: [.customLong("Di", withSingleDash: true), .long], help: "Don't parse the layer name (option 'property-name') from Feature properties in the input GeoJSONs, just use 'layer-name' or a default. Might speed up GeoJSON parsing considerably.")
        var disableInputLayerProperty: Bool = false

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "GeoJSON resources to import (file or URL)",
            completion: .file(extensions: ["json", "geojson"]))
        var other: [String] = []

        mutating func run() async throws {
            let (x, y, z) = try xyzOptions.parseXYZ(fromPaths: [outputFile] + other)

            let outputUrl = URL(fileURLWithPath: outputFile)
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
                tile = VectorTile(
                    contentsOf: outputUrl,
                    x: x,
                    y: y,
                    z: z,
                    logger: options.verbose ? CLI.logger : nil)
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
                print("Import into tile '\(outputUrl.lastPathComponent)' [\(x),\(y)]@\(z)")
            }

            if options.verbose {
                print("Import layer feature property: \(propertyName)")
                if let layerName {
                    print("Fallback layer name: \(layerName)")
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

                tile.addGeoJson(
                    geoJson: otherGeoJSON,
                    layerName: layerName,
                    layerProperty: disableInputLayerProperty ? nil : propertyName)
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
