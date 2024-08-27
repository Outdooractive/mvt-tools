import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    struct Export: AsyncParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Export a vector tile as GeoJSON to a file")

        @Option(
            name: [.short, .customLong("output")],
            help: "Output GeoJSON file.",
            completion: .file(extensions: ["geojson", "json"]))
        var outputFile: String

        @Option(
            name: [.customLong("oC", withSingleDash: true), .long],
            help: "Output file compression level, between 0=none to 9=best. (default: none)")
        var compressionLevel: Int?

        @Option(
            name: [.customLong("oSm", withSingleDash: true), .long],
            help: "Simplify output features using meters.")
        var simplifyMeters: Int?

        @Flag(
            name: .shortAndLong,
            help: "Overwrite existing files.")
        var forceOverwrite = false

        @Option(
            name: .shortAndLong,
            help: "Export only the specified layer (can be repeated).")
        var layer: [String] = []

        @Option(
            name: [.customShort("P"), .long],
            help: "Feature property to use for the layer name in the output GeoJSON.")
        var propertyName: String = VectorTile.defaultLayerPropertyName

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
            help: "The vector tile (file or URL).",
            completion: .file(extensions: ["pbf", "mvt"]))
        var path: String

        mutating func run() async throws {
            let (x, y, z) = try xyzOptions.parseXYZ(fromPaths: [path])
            let url = try options.parseUrl(fromPath: path)
            let layerAllowlist = layer.nonempty
            let outputUrl = URL(fileURLWithPath: outputFile)

            if (try? outputUrl.checkResourceIsReachable()) ?? false {
                if forceOverwrite {
                    if options.verbose {
                        print("Existing file '\(outputUrl.lastPathComponent)' will be overwritten")
                    }
                }
                else {
                    throw CLIError("Output file must not exist (use --force-overwrite to overwrite existing files)")
                }
            }

            guard let tile = VectorTile(
                contentsOf: url,
                x: x,
                y: y,
                z: z,
                layerWhitelist: layerAllowlist,
                logger: options.verbose ? CLI.logger : nil)
            else { throw CLIError("Failed to parse the resource at '\(path)'") }

            var exportOptions = VectorTile.ExportOptions()
            if let simplifyMeters, simplifyMeters > 0 {
                exportOptions.simplifyFeatures = .meters(Double(simplifyMeters))
            }
            if let compressionLevel, compressionLevel > 0 {
                exportOptions.compression = .level(max(0, min(9, compressionLevel)))
            }

            if options.verbose {
                print("Dumping tile '\(url.lastPathComponent)' [\(x),\(y)]@\(z) to '\(outputUrl.lastPathComponent)'")

                print("Layer property name: \(propertyName)")
                if disableOutputLayerProperty {
                    print("  - disable output layer property")
                }

                if let layerAllowlist {
                    print("Layers: '\(layerAllowlist.joined(separator: ","))'")
                }

                print("Output options:")
                print("  - Pretty print: \(prettyPrint)")
                print("  - Compression: \(exportOptions.compression)")
                print("  - Simplification: \(exportOptions.simplifyFeatures)")
            }

            guard let data = tile.toGeoJson(
                prettyPrinted: prettyPrint,
                layerProperty: disableOutputLayerProperty ? nil : propertyName,
                options: exportOptions)
            else { throw CLIError("Failed to extract the tile data as GeoJSON") }

            try data.write(to: outputUrl, options: .atomic)

            if options.verbose {
                print("Done.")
            }
        }

    }

}
