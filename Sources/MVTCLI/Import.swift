import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    /// A command that imports data from various formats into a single
    /// output file in any supported format.
    ///
    /// This is an alias for ``Merge`` with the same options and behavior.
    struct Import: AsyncParsableCommand {

        static let configuration = CommandConfiguration(
            commandName: "import",
            abstract: "Alias for 'merge'. Import data into a file of any supported format.",
            discussion: "This command behaves identically to 'merge'. See 'merge --help' for details.")

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
