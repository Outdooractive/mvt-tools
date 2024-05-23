import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    struct Merge: AsyncParsableCommand {

        static var configuration = CommandConfiguration(abstract: "Merge two or more vector tiles")

        @Option(name: .shortAndLong, help: "Output file")
        var output: String

        @Option(name: .shortAndLong, help: "Merge only the specified layer (can be repeated)")
        var layer: [String] = []

        @OptionGroup
        var options: Options

        @Argument(
            help: "Additional MVT resources to merge (file or URL)",
            completion: .file(extensions: ["pbf", "mvt"]))
        var other: [String] = []

        mutating func run() async throws {
            let url = try options.parseUrl()

            guard let x = options.x,
                  let y = options.y,
                  let z = options.z
            else { throw "Something went wrong during argument parsing" }

            let outputUrl = URL(fileURLWithPath: output)
            if (try? outputUrl.checkResourceIsReachable()) ?? false {
                throw "Output file must not exist"
            }

            let layerWhitelist = layer.nonempty

            guard var tile = VectorTile(contentsOf: url, x: x, y: y, z: z, layerWhitelist: layerWhitelist, logger: options.verbose ? CLI.logger : nil) else {
                throw "Failed to parse the tile at \(options.path)"
            }

            for path in other {
                let otherUrl: URL
                if path.hasPrefix("http") {
                    guard let parsedUrl = URL(string: path) else {
                        throw "\(path) is not a valid URL"
                    }
                    otherUrl = parsedUrl
                }
                else {
                    otherUrl = URL(fileURLWithPath: path)
                    guard try otherUrl.checkResourceIsReachable() else {
                        throw "The file '\(path)' doesn't exist."
                    }
                }

                guard let otherTile = VectorTile(contentsOf: otherUrl, x: x, y: y, z: z, layerWhitelist: layerWhitelist, logger: options.verbose ? CLI.logger : nil) else {
                    throw "Failed to parse the tile at \(path)"
                }

                tile.merge(otherTile)
            }

            let exportOptions = VectorTileExportOptions(
                bufferSize: .extent(512),
                compression: .level(9),
                simplifyFeatures: .no)
            tile.write(to: outputUrl, options: exportOptions)
        }

    }

}
