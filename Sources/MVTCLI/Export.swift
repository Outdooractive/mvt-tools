import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    struct Export: AsyncParsableCommand {

        static let configuration = CommandConfiguration(abstract: "Export a vector tile as GeoJSON to a file")

        @Option(name: .shortAndLong, help: "Output GeoJSON file.")
        var output: String

        @Flag(name: .shortAndLong, help: "Force overwrite existing files.")
        var forceOverwrite = false

        @Option(name: .shortAndLong, help: "Export only the specified layer (can be repeated).")
        var layer: [String] = []

        @Flag(name: .shortAndLong, help: "Pretty-print the output GeoJSON.")
        var prettyPrint = false

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "The vector tile (file or URL)",
            completion: .file(extensions: ["pbf", "mvt"]))
        var path: String

        mutating func run() async throws {
            let (x, y, z) = try xyzOptions.parseXYZ(fromPaths: [path])
            let url = try options.parseUrl(fromPath: path)
            let layerAllowlist = layer.nonempty

            let outputUrl = URL(fileURLWithPath: output)
            if (try? outputUrl.checkResourceIsReachable()) ?? false {
                if forceOverwrite {
                    print("Existing file '\(outputUrl.lastPathComponent)' will be overwritten")
                }
                else {
                    throw CLIError("Output file must not exist (use --force-overwrite to overwrite existing files)")
                }
            }

            if options.verbose {
                print("Dumping tile '\(url.lastPathComponent)' [\(x),\(y)]@\(z) to '\(outputUrl.lastPathComponent)'")

                if let layerAllowlist {
                    print("Layers: '\(layerAllowlist.joined(separator: ","))'")
                }
            }

            guard let tile = VectorTile(contentsOf: url, x: x, y: y, z: z, layerWhitelist: layerAllowlist, logger: options.verbose ? CLI.logger : nil) else {
                throw CLIError("Failed to parse the resource at '\(path)'")
            }

            guard let data = tile.toGeoJson(prettyPrinted: prettyPrint) else {
                throw CLIError("Failed to extract the tile data as GeoJSON")
            }

            try data.write(to: outputUrl, options: .atomic)

            if options.verbose {
                print("Done.")
            }
        }

    }

}
