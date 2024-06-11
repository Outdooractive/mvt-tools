import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    struct Export: AsyncParsableCommand {

        static var configuration = CommandConfiguration(abstract: "Export the vector tile as GeoJSON")

        @Option(name: .shortAndLong, help: "Output file")
        var output: String

        @Option(name: .shortAndLong, help: "Export only the specified layer (can be repeated)")
        var layer: [String] = []

        @Flag(name: .shortAndLong, help: "Format the output GeoJSON")
        var prettyPrint = false

        @OptionGroup
        var options: Options

        mutating func run() async throws {
            let url = try options.parseUrl()

            guard let x = options.x,
                  let y = options.y,
                  let z = options.z
            else { throw CLIError("Something went wrong during argument parsing") }

            let outputUrl = URL(fileURLWithPath: output)
            if (try? outputUrl.checkResourceIsReachable()) ?? false {
                throw CLIError("Output file must not exist")
            }

            let layerWhitelist = layer.nonempty

            guard let tile = VectorTile(contentsOf: url, x: x, y: y, z: z, layerWhitelist: layerWhitelist, logger: options.verbose ? CLI.logger : nil) else {
                throw CLIError("Failed to parse the tile at \(options.path)")
            }

            guard let data = tile.toGeoJson(prettyPrinted: prettyPrint) else {
                throw CLIError("Failed to extract the tile data as GeoJSON")
            }

            try data.write(to: outputUrl, options: .atomic)
        }

    }

}
