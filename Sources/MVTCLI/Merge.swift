import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    /// A command that merges multiple input files into a single tile.
    ///
    /// Supports MVT, MLT, GeoJSON, GPX, Shapefile, and GeoPackage input,
    /// with layer filtering, output compression, feature simplification,
    /// and customizable buffer sizes.
    struct Merge: AsyncParsableCommand {

        static let configuration = CommandConfiguration(
            abstract: "Merge any number of input files into a single file of any supported format",
            discussion: "Note: Vector tiles should all have the same tile coordinate or strange things will happen.")

        @OptionGroup
        var mergeOptions: MergeOptions

        @OptionGroup
        var xyzOptions: XYZOptions

        @OptionGroup
        var options: Options

        mutating func run() async throws {
            try await CLI.MergeOptions.run(
                mergeOptions,
                xyzOptions: &xyzOptions,
                cliOptions: options)
        }

    }

}
