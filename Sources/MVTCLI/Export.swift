import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    /// A command that exports any supported input file to a GeoJSON file.
    ///
    /// This is an alias for ``Merge`` with a single input file.
    /// See `merge --help` for full option details.
    struct Export: AsyncParsableCommand {

        static let configuration = CommandConfiguration(
            commandName: "export",
            abstract: "Alias for 'merge'. Export a file as GeoJSON.",
            discussion: "This command behaves identically to 'merge'. See 'merge --help' for details.")

        @OptionGroup
        var mergeOptions: CLI.MergeOptions

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
