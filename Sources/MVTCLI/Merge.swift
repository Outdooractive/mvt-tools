import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    struct Merge: AsyncParsableCommand {

        static let configuration = CommandConfiguration(abstract: "Merge two or more vector tiles")

        @Option(name: .shortAndLong, help: "Output file")
        var output: String

        @Flag(name: .shortAndLong, help: "Force overwrite existing files")
        var forceOverwrite = false

        @Flag(name: .shortAndLong, help: "Append to an existing --output file")
        var append = false

        @Option(name: .shortAndLong, help: "Merge only the specified layer (can be repeated)")
        var layer: [String] = []

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "Additional MVT resources to merge (file or URL)",
            completion: .file(extensions: ["pbf", "mvt"]))
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

            let layerAllowlist = layer.nonempty

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
                throw CLIError("Failed to create the tile at \(output)")
            }

            if options.verbose {
                print("Merging into tile '\(outputUrl.lastPathComponent)' [\(x),\(y)]@\(z)")

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

                guard let otherTile = VectorTile(contentsOf: otherUrl, x: x, y: y, z: z, layerWhitelist: layerAllowlist, logger: options.verbose ? CLI.logger : nil) else {
                    throw CLIError("Failed to parse the tile at '\(path)'")
                }

                if options.verbose {
                    print("- \(otherUrl.lastPathComponent)")
                }

                tile.merge(otherTile)
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
