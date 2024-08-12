import ArgumentParser
#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools
import MVTTools

extension CLI {

    struct Query: AsyncParsableCommand {

        static let configuration = CommandConfiguration(abstract: "Query the features in the input file (mvt or GeoJSON)")

        @Option(name: .shortAndLong, help: "Output GeoJSON file (optional, default is console).")
        var output: String?

        @Flag(name: .shortAndLong, help: "Force overwrite existing files.")
        var forceOverwrite = false

        @Option(name: .shortAndLong, help: "Search only in this layer (can be repeated).")
        var layer: [String] = []

        @Flag(name: .shortAndLong, help: "Pretty-print the output GeoJSON.")
        var prettyPrint = false

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "The vector tile or GeoJSON (file or URL)",
            completion: .file(extensions: ["pbf", "mvt", "geojson", "json"]))
        var path: String

        @Argument(help: "Search term, can be a string or a coordinate in the form 'latitude,longitude,tolerance(meters)'")
        var searchTerm: String

        mutating func run() async throws {
            if let output {
                let outputUrl = URL(fileURLWithPath: output)
                if (try? outputUrl.checkResourceIsReachable()) ?? false {
                    if forceOverwrite {
                        print("Existing file '\(outputUrl.lastPathComponent)' will be overwritten")
                    }
                    else {
                        throw CLIError("Output file must not exist (use --force-overwrite to overwrite existing files)")
                    }
                }
            }

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
                print("Searching in tile '\(url.lastPathComponent)' [\(tile.x),\(tile.y)]@\(tile.z)")

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

            if let result {
                if let output {
                    let outputUrl = URL(fileURLWithPath: output)
                    try result.asJsonData(prettyPrinted: prettyPrint)?.write(to: outputUrl, options: .atomic)
                }
                else if let resultGeoJson = result.asJsonString(prettyPrinted: prettyPrint) {
                    print(resultGeoJson, terminator: "")
                    print()

                    if options.verbose {
                        let count = result.features.count
                        print("Found \(count) \(count == 1 ? "result" : "results").")
                    }
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
