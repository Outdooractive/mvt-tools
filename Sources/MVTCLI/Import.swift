import ArgumentParser
import Foundation
import GISTools
import MVTTools

extension CLI {

    struct Import: AsyncParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Import some GeoJSONs into a vector tile")

        @Option(
            name: [.short, .customLong("output")],
            help: "Output MVT file.",
            completion: .file(extensions: ["pbf", "mvt"]))
        var outputFile: String

        @Option(
            name: [.customLong("oC", withSingleDash: true), .long],
            help: "Output file compression level, between 0=none to 9=best.")
        var compressionLevel: Int = 9

        @Option(
            name: [.customLong("oBe", withSingleDash: true), .long],
            help: "Output buffer extents for tiles of size \(VectorTile.ExportOptions.extent). (default: 512)")
        var bufferExtents: Int?

        @Option(
            name: [.customLong("oBp", withSingleDash: true), .long],
            help: "Output buffer pixels for tiles of size \(VectorTile.ExportOptions.tileSize). Overrides 'buffer-extents'.")
        var bufferPixels: Int?

        @Option(
            name: [.customLong("oSe", withSingleDash: true), .long],
            help: "Simplify output features using tile extents. (default: no simplification)")
        var simplifyExtents: Int?

        @Option(
            name: [.customLong("oSm", withSingleDash: true), .long],
            help: "Simplify output features using meters. Overrides 'simplify-extents'.")
        var simplifyMeters: Int?

        @Flag(
            name: .shortAndLong,
            help: "Overwrite an existing 'output' file.")
        var forceOverwrite = false

        @Flag(
            name: .shortAndLong,
            help: "Append to an existing 'output' file.")
        var append = false

        @Option(
            name: .shortAndLong,
            help: "Import only the specified layer (can be repeated). ")
        var layer: [String] = []

        @Option(
            name: [.customShort("L"), .long],
            help: "Layer name in the vector tile for the imported GeoJSON. Can be used with 'property-name' as a fallback name.")
        var layerName: String?

        @Option(
            name: [.customShort("P"), .long],
            help: "Feature property to use for the layer name in input GeoJSONs. Fallback to 'layer-name' or a default if the property is not present. Needed for filtering by layer.")
        var propertyName: String = VectorTile.defaultLayerPropertyName

        @Flag(
            name: [.customLong("Di", withSingleDash: true), .long],
            help: "Don't parse the layer name (option 'property-name') from Feature properties in the input GeoJSONs, just use 'layer-name' or a default. Might speed up GeoJSON parsing considerably.")
        var disableInputLayerProperty: Bool = false

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "GeoJSON resources to import (file or URL).",
            completion: .file(extensions: ["json", "geojson"]))
        var other: [String] = []

        mutating func run() async throws {
            let (x, y, z) = try xyzOptions.parseXYZ(fromPaths: [outputFile] + other)
            let layerAllowlist = layer.nonempty

            let outputUrl = URL(fileURLWithPath: outputFile)
            if (try? outputUrl.checkResourceIsReachable()) ?? false {
                if forceOverwrite {
                    if options.verbose {
                        print("Existing file '\(outputUrl.lastPathComponent)' will be overwritten")
                    }
                }
                else if append {
                    if options.verbose {
                        print("Existing file '\(outputUrl.lastPathComponent)' will be appended")
                    }
                }
                else {
                    throw CLIError("Output file must not exist (use --force-overwrite or --append to overwrite existing files)")
                }
            }

            var tile: VectorTile?
            if append,
               (try? outputUrl.checkResourceIsReachable()) ?? false
            {
                tile = VectorTile(
                    contentsOf: outputUrl,
                    x: x,
                    y: y,
                    z: z,
                    logger: options.verbose ? CLI.logger : nil)
            }

            if tile == nil {
                tile = VectorTile(
                    x: x,
                    y: y,
                    z: z,
                    logger: options.verbose ? CLI.logger : nil)
            }

            guard var tile else { throw CLIError("Failed to create a tile [\(x),\(y)]@\(z)") }

            if options.verbose {
                print("Import into \(tile.origin) tile '\(outputUrl.lastPathComponent)' [\(x),\(y)]@\(z)")
                print("Property name: \(propertyName)")

                if disableInputLayerProperty {
                    print("  - disable input layer property")
                }

                if let layerName {
                    print("Fallback layer name: \(layerName)")
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

                guard var otherGeoJSON = FeatureCollection(contentsOf: otherUrl) else {
                    throw CLIError("Failed to parse the GeoJSON at '\(path)'")
                }

                print("- \(otherUrl.lastPathComponent)")

                if !disableInputLayerProperty,
                   let layerAllowlist
                {
                    otherGeoJSON.filterFeatures { feature in
                        guard let layerName: String = feature.property(for: propertyName) else { return false }
                        return layerAllowlist.contains(layerName)
                    }
                }

                tile.addGeoJson(
                    geoJson: otherGeoJSON,
                    layerName: layerName,
                    layerProperty: disableInputLayerProperty ? nil : propertyName)
            }

            // Export

            let bufferSize: VectorTile.ExportOptions.BufferSizeOptions = if let bufferPixels, bufferPixels > 0 {
                .pixel(bufferPixels)
            }
            else if let bufferExtents, bufferExtents > 0 {
                .extent(bufferExtents)
            }
            else {
                .extent(512)
            }

            var compression: VectorTile.ExportOptions.CompressionOptions = .no
            if compressionLevel > 0 {
                compression = .level(max(0, min(9, compressionLevel)))
            }

            let simplifyFeatures: VectorTile.ExportOptions.SimplifyFeaturesOptions = if let simplifyMeters, simplifyMeters > 0 {
                .meters(Double(simplifyMeters))
            }
            else if let simplifyExtents, simplifyExtents > 0 {
                .extent(simplifyExtents)
            }
            else {
                .no
            }

            if options.verbose {
                print("Output options:")
                print("  - Buffer size: \(bufferSize)")
                print("  - Compression: \(compression)")
                print("  - Simplification: \(simplifyFeatures)")
            }

            let exportOptions: VectorTile.ExportOptions = .init(
                bufferSize: bufferSize,
                compression: compression,
                simplifyFeatures: simplifyFeatures)

            tile.write(
                to: outputUrl,
                options: exportOptions)

            if options.verbose {
                print("Done.")
            }
        }

    }

}
