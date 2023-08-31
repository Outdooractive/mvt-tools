import ArgumentParser
import Foundation
import GISTools
import MVTTools
import CoreLocation

extension CLI {

    struct Query: AsyncParsableCommand {

        static var configuration = CommandConfiguration(abstract: "Query the features in a vector tile.")

        @Option(name: .shortAndLong, help: "Search only in this layer.")
        var layer: [String] = []

        @OptionGroup
        var options: Options

        @Argument(help: "Search term, can be a string or a coordinate in the form 'latitude,longitude,tolerance(meters)'.")
        var searchTerm: String

        mutating func run() async throws {
            var coordinate: Coordinate3D?
            var tolerance: CLLocationDistance?

            let possibleCoordinateParts = searchTerm.extractingGroupsUsingPattern("^([\\d\\.]+),([\\d\\.]+),([\\d\\.]+)$", caseInsensitive: false)
            if possibleCoordinateParts.count >= 3 {
                if let partLatitude = Double(possibleCoordinateParts[0]),
                   let partLongitude = Double(possibleCoordinateParts[1]),
                   let partTolerance = Double(possibleCoordinateParts[2]),
                   (-90...90).contains(partLatitude),
                   (-180...180).contains(partLongitude),
                   partTolerance > 0.0
                {
                    coordinate = Coordinate3D(latitude: partLatitude, longitude: partLongitude)
                    tolerance = partTolerance
                }
            }

            let url = try options.parseUrl()

            guard let x = options.x,
                  let y = options.y,
                  let z = options.z
            else { throw "Something went wrong during argument parsing" }

            let layerWhitelist = layer.nonempty

            guard let tile = VectorTile(contentsOf: url, x: x, y: y, z: z, layerWhitelist: layerWhitelist, logger: options.verbose ? CLI.logger : nil) else {
                throw "Failed to parse the tile at \(options.path)"
            }

            var result: FeatureCollection?
            if let coordinate = coordinate,
               let tolerance = tolerance
            {
                if options.verbose {
                    print("Searching around \(coordinate), tolerance: \(tolerance)m ...")
                }
                result = search(around: coordinate, tolerance: tolerance, in: tile)
            }
            else {
                if options.verbose {
                    print("Searching for '\(searchTerm)'...")
                }
                result = search(term: searchTerm, in: tile)
            }

            if let result = result,
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
