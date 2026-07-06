import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    /// A command that prints the contents of any supported input file
    /// as pretty-printed GeoJSON to the console.
    ///
    /// Supports MVT, MLT, GeoJSON, GPX, Shapefile, and GeoPackage input,
    /// with layer filtering, output simplification, and control over the
    /// GeoJSON layer property name.
    struct Dump: AsyncParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Print the input file (MVT, MLT, GeoJSON, GPX, Shapefile, or GeoPackage) as pretty-printed GeoJSON to the console")

        @Option(
            name: .shortAndLong,
            help: "Dump the specified layer (can be repeated).")
        var layer: [String] = []

        @Option(
            name: .shortAndLong,
            help: "Drop the specified layer (can be repeated).")
        var dropLayer: [String] = []

        @Option(
            name: [.customShort("P"), .long],
            help: """
            Feature property to use for the layer name in input and output GeoJSONs. \
            Needed for filtering by layer. For GPX input, defaults to "gpx_type" \
            (splits waypoints/routes/tracks).
            """)
        var propertyName: String = VectorTile.defaultLayerPropertyName

        @Flag(
            name: [.customLong("Di", withSingleDash: true), .long],
            help: "Don't parse the layer name (option 'property-name') from Feature properties in the input GeoJSONs. Might speed up GeoJSON parsing considerably.")
        var disableInputLayerProperty = false

        @Flag(
            name: [.customLong("Do", withSingleDash: true), .long],
            help: "Don't add the layer name (option 'property-name') as a Feature property in the output GeoJSONs.")
        var disableOutputLayerProperty = false

        @Option(
            name: [.customLong("oSm", withSingleDash: true), .long],
            help: "Simplify output features using meters.")
        var simplifyMeters: Int?

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        @Argument(
            help: "The input file (MLT, MVT, GeoJSON, GPX, Shapefile, or GeoPackage).",
            completion: .file(extensions: ["pbf", "mvt", "mlt", "geojson", "json", "gpx", "shp", "gpkg"]))
        var path: String

        mutating func run() async throws {
            let url = try options.parseUrl(fromPath: path)
            let format = try TileFormat.resolve(
                url: url,
                xyzOptions: &xyzOptions,
                verbose: options.verbose)
            let layerAllowlist = layer.asSet.subtracting(dropLayer).asArray.nonempty
            let layerDenylist = dropLayer.asSet.subtracting(layer).asArray.nonempty

            // layer allowlist only makes sense for formats that have named layers
            let effectiveAllowlist: [String]? = format.supportsInputLayerProperty && disableInputLayerProperty
                ? nil
                : layerAllowlist

            let tile = try await format.loadTile(
                from: url,
                layerAllowlist: effectiveAllowlist,
                layerProperty: disableInputLayerProperty ? nil : propertyName,
                logger: options.verbose ? CLI.logger : nil)

            guard let tile else { throw CLIError("Failed to parse the resource at '\(path)'") }

            if options.verbose {
                print("Dumping \(format) tile '\(url.lastPathComponent)' [\(tile.x),\(tile.y)]@\(tile.z)")

                if format.supportsInputLayerProperty {
                    print("Layer property name: \(propertyName)")
                    if disableInputLayerProperty {
                        print("  - disable input layer property")
                    }
                }
                if disableOutputLayerProperty {
                    print("  - disable output layer property")
                }

                if let layerAllowlist {
                    print("Allowed layers: '\(layerAllowlist.sorted().joined(separator: ","))'")
                }
                if let layerDenylist {
                    print("Dropped layers: '\(layerDenylist.sorted().joined(separator: ","))'")
                }

                var exportOptions = VectorTile.ExportOptions()
                if let simplifyMeters, simplifyMeters > 0 {
                    exportOptions.simplifyFeatures = .meters(Double(simplifyMeters))
                }
                print("Output options:")
                print("  - Pretty print: true")
                print("  - Simplification: \(exportOptions.simplifyFeatures)")

                print("GeoJSON:")
            }

            var exportOptions = VectorTile.ExportOptions()
            if let simplifyMeters, simplifyMeters > 0 {
                exportOptions.simplifyFeatures = .meters(Double(simplifyMeters))
            }

            var layerNames: [String] = []
            if let layerDenylist {
                layerNames = tile.layerNames.asSet.subtracting(layerDenylist).asArray
            }

            guard let data = tile.toGeoJson(
                layerNames: layerNames,
                prettyPrinted: true,
                layerProperty: disableOutputLayerProperty ? nil : propertyName,
                options: exportOptions)
            else { throw CLIError("Failed to extract the tile data as GeoJSON") }

            print(String(data: data, encoding: .utf8) ?? "", terminator: "")
            print()

            if options.verbose {
                print("Done.")
            }
        }

    }

}
