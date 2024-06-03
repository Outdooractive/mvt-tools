import ArgumentParser
import Foundation
import GISTools
import MVTTools

extension CLI {

    struct Import: AsyncParsableCommand {

        static var configuration = CommandConfiguration(abstract: "Import some GeoJSONs to a vector tile")

        @Option(name: .shortAndLong, help: "Layer name in the vector tile")
        var layer: String?

        @OptionGroup
        var options: Options

        @Argument(
            help: "GeoJSON resources to import (file or URL)",
            completion: .file(extensions: ["json", "geojson"]))
        var other: [String] = []

        mutating func run() async throws {
            let url = try options.parseUrl(checkExistence: false)

            guard let x = options.x,
                  let y = options.y,
                  let z = options.z
            else { throw "Something went wrong during argument parsing" }

            guard var tile = VectorTile(x: x, y: y, z: z, logger: options.verbose ? CLI.logger : nil) else {
                throw "Failed to create the tile at \(options.path)"
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

                guard let otherGeoJSON = FeatureCollection(contentsOf: otherUrl) else {
                    throw "Failed to parse the GeoJSON at \(path)"
                }

                tile.addGeoJson(geoJson: otherGeoJSON, layerName: layer)
            }

            tile.write(
                to: url,
                options: .init(
                    bufferSize: .extent(512),
                    compression: .level(9),
                    simplifyFeatures: .no))
        }

    }

}
