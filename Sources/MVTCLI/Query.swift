import ArgumentParser
#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools
import MVTTools

extension CLI {

    struct Query: AsyncParsableCommand {

        static let configuration = CommandConfiguration(abstract: "Query the features in a vector tile")

        @Option(name: .shortAndLong, help: "Search only in this layer (can be repeated)")
        var layer: [String] = []

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "The vector tile (file or URL)",
            completion: .file(extensions: ["pbf", "mvt"]))
        var path: String

        @Argument(help: "Search term, can be a string or a coordinate in the form 'latitude,longitude,tolerance(meters)'")
        var searchTerm: String

        mutating func run() async throws {
            var coordinate: Coordinate3D?
            var tolerance: CLLocationDistance?

            let possibleCoordinateParts = searchTerm.extractingGroupsUsingPattern("^([\\d\\.]+),([\\d\\.]+),([\\d\\.]+)$", caseInsensitive: false)
            if possibleCoordinateParts.count >= 3 {
                if let partLatitude = Double(possibleCoordinateParts[0]),
                   let partLongitude = Double(possibleCoordinateParts[1]),
                   let partTolerance = Double(possibleCoordinateParts[2])?.rounded(),
                   (-90 ... 90).contains(partLatitude),
                   (-180 ... 180).contains(partLongitude),
                   partTolerance > 0.0
                {
                    coordinate = Coordinate3D(latitude: partLatitude, longitude: partLongitude)
                    tolerance = partTolerance
                }
            }

            let (x, y, z) = try xyzOptions.parseXYZ(fromPath: path)
            let url = try options.parseUrl(fromPath: path)

            let layerAllowlist = layer.nonempty

            guard let tile = VectorTile(contentsOf: url, x: x, y: y, z: z, layerWhitelist: layerAllowlist, logger: options.verbose ? CLI.logger : nil) else {
                throw CLIError("Failed to parse the resource at \(path)")
            }

            if options.verbose {
                print("Searching in tile '\(url.lastPathComponent)' [\(x),\(y)]@\(z)")

                if let layerAllowlist {
                    print("Layers: '\(layerAllowlist.joined(separator: ","))'")
                }
            }

            var result: FeatureCollection?
            if let coordinate,
               let tolerance
            {
                if options.verbose {
                    print("Searching around \(coordinate), tolerance: \(tolerance)m ...")
                }
                result = search(around: coordinate, tolerance: tolerance, in: tile)
            }
            else {
                if options.verbose {
                    print("Searching for '\(searchTerm)'…")
                }
                result = search(term: searchTerm, in: tile)
            }

            if let result,
               let output = result.asJsonString(prettyPrinted: true)
            {
                print(output, terminator: "")
                print()

                if options.verbose {
                    let count = result.features.count
                    print("Found \(count) \(count == 1 ? "result" : "results").")
                }
            }
            else {
                print("Nothing found!")
            }
        }

        private func search(
            around coordinate: Coordinate3D,
            tolerance: CLLocationDistance,
            layerName: String? = nil,
            in tile: VectorTile)
            -> FeatureCollection?
        {
            let features: [Feature] = tile.query(at: coordinate, tolerance: tolerance, layerName: layerName)
                .map({ (result) in
                    var feature = result.feature
                    feature.setForeignMember(result.layerName, for: "layer")
                    return feature
                })
            return FeatureCollection(features)
        }

        private func search(
            term: String,
            layerName: String? = nil,
            in tile: VectorTile)
            -> FeatureCollection?
        {
            let features: [Feature] = tile.query(term: term, layerName: layerName)
                .map({ (result) in
                    var feature = result.feature
                    feature.setForeignMember(result.layerName, for: "layer")
                    return feature
                })
            return FeatureCollection(features)
        }

    }

}
