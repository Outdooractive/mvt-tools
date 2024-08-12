import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    struct Dump: AsyncParsableCommand {

        static let configuration = CommandConfiguration(abstract: "Print the input file (mvt or GeoJSON) as pretty-printed GeoJSON to the console")

        @Option(name: .shortAndLong, help: "Dump only the specified layer (can be repeated)")
        var layer: [String] = []

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "The vector tile or GeoJSON (file or URL)",
            completion: .file(extensions: ["pbf", "mvt", "geojson", "json"]))
        var path: String

        mutating func run() async throws {
            let layerAllowlist = layer.nonempty
            let url = try options.parseUrl(fromPath: path)

            var tile = VectorTile(contentsOfGeoJson: url, layerWhitelist: layerAllowlist, logger: options.verbose ? CLI.logger : nil)
            if tile == nil,
               let (x, y, z) = try? xyzOptions.parseXYZ(fromPaths: [path])
            {
                tile = VectorTile(contentsOf: url, x: x, y: y, z: z, layerWhitelist: layerAllowlist, logger: options.verbose ? CLI.logger : nil)
            }

            guard let tile else {
                throw CLIError("Failed to parse the resource at '\(path)'")
            }

            if options.verbose {
                print("Dumping tile '\(url.lastPathComponent)' [\(tile.x),\(tile.y)]@\(tile.z)")

                if let layerAllowlist {
                    print("Layers: '\(layerAllowlist.joined(separator: ","))'")
                }
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
