import ArgumentParser
#if !os(Linux)
    import CoreLocation
#endif
import Foundation
import GISTools
import Gzip
import MVTTools

extension CLI {

    struct Query: AsyncParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Query the features in the input file (MVT or GeoJSON)")

        @Option(
            name: [.short, .customLong("output")],
            help: "Output GeoJSON file (optional, default is console).",
            completion: .file(extensions: ["geojson", "json"]))
        var outputFile: String?

        @Option(
            name: [.customLong("oC", withSingleDash: true), .long],
            help: "Output file compression level, between 0=none to 9=best. (default: none)")
        var compressionLevel: Int?

        @Option(
            name: [.customLong("oSm", withSingleDash: true), .long],
            help: "Simplify output features using meters.")
        var simplifyMeters: Int?

        @Flag(
            name: .shortAndLong,
            help: "Overwrite existing files.")
        var forceOverwrite = false

        @Option(
            name: .shortAndLong,
            help: "Search in this layer (can be repeated).")
        var layer: [String] = []

        @Option(
            name: .shortAndLong,
            help: "Do not search in the specified layer (can be repeated).")
        var dropLayer: [String] = []

        @Option(
            name: [.customShort("P"), .long],
            help: "Feature property to use for the layer name in input and output GeoJSONs. Needed for filtering by layer.")
        var propertyName: String = VectorTile.defaultLayerPropertyName

        @Flag(
            name: [.customLong("Di", withSingleDash: true), .long],
            help: "Don't parse the layer name (option 'property-name') from Feature properties in the input GeoJSONs. Might speed up GeoJSON parsing considerably.")
        var disableInputLayerProperty = false

        @Flag(
            name: [.customLong("Do", withSingleDash: true), .long],
            help: "Don't add the layer name (option 'property-name') as a Feature property in the output GeoJSONs.")
        var disableOutputLayerProperty = false

        @Flag(
            name: .shortAndLong,
            help: "Pretty-print the output GeoJSON.")
        var prettyPrint = false

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "The vector tile or GeoJSON (file or URL).",
            completion: .file(extensions: ["pbf", "mvt", "geojson", "json"]))
        var path: String

        @Argument(help: "Search term, can be a string or a coordinate in the form 'latitude,longitude,tolerance(meters)'.")
        var searchTerms: [String]

        mutating func run() async throws {
            if let outputFile {
                let outputUrl = URL(fileURLWithPath: outputFile)
                if (try? outputUrl.checkResourceIsReachable()) ?? false {
                    if forceOverwrite {
                        if options.verbose {
                            print("Existing file '\(outputUrl.lastPathComponent)' will be overwritten")
                        }
                    }
                    else {
                        throw CLIError("Output file must not exist (use --force-overwrite to overwrite existing files)")
                    }
                }
            }

            let searchTerm = searchTerms.joined(separator: " ")

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

            let url = try options.parseUrl(fromPath: path)
            let layerAllowlist = layer.asSet.subtracting(dropLayer).asArray.nonempty
            let layerDenylist = dropLayer.asSet.subtracting(layer).asArray.nonempty

            var tile = VectorTile(
                contentsOfGeoJson: url,
                layerProperty: disableInputLayerProperty ? nil : propertyName,
                layerWhitelist: disableInputLayerProperty ? nil : layerAllowlist,
                logger: options.verbose ? CLI.logger : nil)

            if tile == nil,
               let (x, y, z) = try? xyzOptions.parseXYZ(fromPaths: [path])
            {
                tile = VectorTile(
                    contentsOf: url,
                    x: x,
                    y: y,
                    z: z,
                    layerWhitelist: layerAllowlist,
                    logger: options.verbose ? CLI.logger : nil)
            }

            if tile != nil, let layerDenylist {
                for droppedLayer in layerDenylist {
                    tile?.removeLayer(droppedLayer)
                }
            }

            guard let tile else { throw CLIError("Failed to parse the resource at '\(path)'") }

            if options.verbose {
                print("Searching in tile '\(url.lastPathComponent)' [\(tile.x),\(tile.y)]@\(tile.z)")

                print("Layer property name: \(propertyName)")
                if disableInputLayerProperty {
                    print("  - disable input layer property")
                }
                if disableOutputLayerProperty {
                    print("  - disable output layer property")
                }

                if disableInputLayerProperty,
                   !disableOutputLayerProperty
                {
                    print("  - Warning: Default output layer names will be used with -Di")
                }

                if tile.origin == .mvt
                    || !disableInputLayerProperty
                {
                    if let layerAllowlist {
                        print("Allowed layers: '\(layerAllowlist.sorted().joined(separator: ","))'")
                    }
                    if let layerDenylist {
                        print("Dropped layers: '\(layerDenylist.sorted().joined(separator: ","))'")
                    }
                }
            }

            var result: FeatureCollection?
            if let coordinate,
               let tolerance
            {
                if options.verbose {
                    print("Searching around \(coordinate), tolerance: \(tolerance)m ...")
                }
                result = search(
                    around: coordinate,
                    tolerance: tolerance,
                    layerProperty: disableOutputLayerProperty ? nil : propertyName,
                    in: tile)
            }
            else {
                if options.verbose {
                    print("Searching for '\(searchTerm)'…")
                }
                result = search(
                    term: searchTerm,
                    layerProperty: disableOutputLayerProperty ? nil : propertyName,
                    in: tile)
            }

            if options.verbose {
                print("Output options:")
                print("  - Pretty print: \(prettyPrint)")
            }

            var exportCompressionLevel: VectorTile.ExportOptions.CompressionOptions = .no
            if outputFile != nil { // don't gzip output to the console
                if let compressionLevel, compressionLevel > 0 {
                    exportCompressionLevel = .level(max(0, min(9, compressionLevel)))
                }

                if options.verbose {
                    print("  - Compression: \(exportCompressionLevel)")
                }
            }

            if let simplifyMeters, simplifyMeters > 0 {
                if options.verbose {
                    print("  - Simplification: \(simplifyMeters > 0 ? ".meters(\(simplifyMeters)" : ".no")")
                }
                result = result?.simplified(tolerance: Double(simplifyMeters))
            }

            if let result {
                if let outputFile {
                    let outputUrl = URL(fileURLWithPath: outputFile)
                    var serializedData = result.asJsonData(prettyPrinted: prettyPrint)

                    if exportCompressionLevel != .no {
                        var value = 6 // default
                        if case let .level(compressionLevel) = exportCompressionLevel {
                            value = max(0, min(9, compressionLevel))
                        }
                        let level = CompressionLevel(rawValue: Int32(value))
                        serializedData = (try? serializedData?.gzipped(level: level)) ?? serializedData
                    }

                    try serializedData?.write(to: outputUrl, options: .atomic)
                }
                else if let resultGeoJson = result.asJsonString(prettyPrinted: prettyPrint) {
                    print(resultGeoJson, terminator: "")
                    print()
                }

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
            layerProperty: String?,
            in tile: VectorTile)
            -> FeatureCollection?
        {
            let features: [Feature] = tile.query(at: coordinate, tolerance: tolerance, layerName: layerName)
                .map({ (result) in
                    var feature = result.feature
                    if let layerProperty {
                        feature.setProperty(result.layerName, for: layerProperty)
                    }
                    return feature
                })
            return FeatureCollection(features)
        }

        private func search(
            term: String,
            layerName: String? = nil,
            layerProperty: String?,
            in tile: VectorTile)
            -> FeatureCollection?
        {
            let features: [Feature] = tile.query(term: term, layerName: layerName)
                .map({ (result) in
                    var feature = result.feature
                    if let layerProperty {
                        feature.setProperty(result.layerName, for: layerProperty)
                    }
                    return feature
                })
            return FeatureCollection(features)
        }

    }

}
