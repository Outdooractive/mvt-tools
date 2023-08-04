import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    struct Dump: AsyncParsableCommand {

        static var configuration = CommandConfiguration(abstract: "Print the vector tile as GeoJSON.")

        @OptionGroup
        var options: Options

        @Option(name: .shortAndLong, help: "Dump only the specified layer")
        var layer: String?

        mutating func run() async throws {
            let url = try options.parseUrl()

            guard let x = options.x,
                  let y = options.y,
                  let z = options.z
            else { throw "Something went wrong during argument parsing" }

            var layerWhitelist: [String]?
            if let layer {
                layerWhitelist = [layer]
            }

            guard let tile = VectorTile(contentsOf: url, x: x, y: y, z: z, layerWhitelist: layerWhitelist, logger: options.verbose ? CLI.logger : nil) else {
                throw "Failed to parse the tile at \(options.path)"
            }

            guard let data = tile.toGeoJson(prettyPrinted: true) else {
                throw "Failed to extract the tile data as GeoJSON"
            }

            print(String(data: data, encoding: .utf8) ?? "", terminator: "")
            print()
        }

    }

}
