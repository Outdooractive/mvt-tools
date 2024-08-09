import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    struct Dump: AsyncParsableCommand {

        static let configuration = CommandConfiguration(abstract: "Print the vector tile as pretty-printed GeoJSON to the console")

        @Option(name: .shortAndLong, help: "Dump only the specified layer (can be repeated)")
        var layer: [String] = []

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

            if options.verbose {
                print("Dumping tile '\(url.lastPathComponent)' [\(x),\(y)]@\(z)")

                if let layerAllowlist {
                    print("Layers: '\(layerAllowlist.joined(separator: ","))'")
                }
            }

            guard let tile = VectorTile(contentsOf: url, x: x, y: y, z: z, layerWhitelist: layerAllowlist, logger: options.verbose ? CLI.logger : nil) else {
                throw CLIError("Failed to parse the resource at '\(path)'")
            }

            guard let data = tile.toGeoJson(prettyPrinted: true) else {
                throw CLIError("Failed to extract the tile data as GeoJSON")
            }

            print(String(data: data, encoding: .utf8) ?? "", terminator: "")
            print()

            if options.verbose {
                print("Done.")
            }
        }

    }

}
