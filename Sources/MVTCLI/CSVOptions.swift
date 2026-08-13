import ArgumentParser
import GISToolsCSV

// MARK: - CSV read options

/// Command-line options controlling CSV input.
///
/// The delimiter is shared with CSV output. Use `--csv-omit-null` as a
/// shorthand for `--csv-null-handling omit`.
struct CSVReadCLIOptions: ParsableArguments {

    @Option(
        name: [.customLong("cD", withSingleDash: true), .customLong("csv-delimiter")],
        help: "CSV field delimiter used for reading and writing.")
    var delimiter = CSVDelimiterArgument()

    @Option(
        name: [.customLong("cNH", withSingleDash: true), .customLong("csv-null-handling")],
        help: "How CSV NULL and empty values are handled: keep-as-string or omit.")
    var nullHandling: CSVNullHandlingArgument = .keepAsString

    @Flag(
        name: [.customLong("cON", withSingleDash: true), .customLong("csv-omit-null")],
        help: "Omit CSV NULL and empty properties.")
    var omitNull = false

    /// The configured CSV read options.
    var options: CSVReadOptions {
        CSVReadOptions(
            delimiter: delimiter.value,
            nullHandling: omitNull ? .omit : nullHandling.value)
    }

}

// MARK: - CSV write options

/// Command-line options controlling CSV output.
///
/// The delimiter is supplied by ``CSVReadCLIOptions`` so a conversion can
/// use one delimiter for both CSV input and output.
struct CSVWriteCLIOptions: ParsableArguments {

    @Option(
        name: [.customLong("cGF", withSingleDash: true), .customLong("csv-geometry-format")],
        help: "CSV geometry format: auto, wkt, ewkb, or geojson.")
    var geometryFormat: CSVGeometryFormatArgument = .auto

    @Option(
        name: [.customLong("cGC", withSingleDash: true), .customLong("csv-geometry-column")],
        help: "CSV geometry column name.")
    var geometryColumn: String = "geometry"

    @Flag(
        name: [.customLong("cH", withSingleDash: true), .customLong("csv-no-header")],
        help: "Do not write a CSV header row.")
    var noHeader = false

    @Option(
        name: [.customLong("cNV", withSingleDash: true), .customLong("csv-null-value")],
        help: "CSV value used for nil properties.")
    var nullValue = ""

    @Option(
        name: [.customLong("cLE", withSingleDash: true), .customLong("csv-line-ending")],
        help: "CSV line ending: lf or crlf.")
    var lineEnding: CSVLineEndingArgument = .lf

    /// Creates CSV write options using the shared CSV delimiter.
    func options(delimiter: Character) -> CSVWriteOptions {
        CSVWriteOptions(
            delimiter: delimiter,
            geometryFormat: geometryFormat.value,
            geometryColumnName: geometryColumn,
            includeHeader: !noHeader,
            nullValue: nullValue,
            lineEnding: lineEnding.value)
    }

}

/// A command-line CSV delimiter, which must contain exactly one character.
struct CSVDelimiterArgument: CustomStringConvertible, ExpressibleByArgument {

    let value: Character

    init() {
        value = CSVCoder.defaultDelimiter
    }

    init?(argument: String) {
        guard argument.count == 1, let character = argument.first else { return nil }
        value = character
    }

    var description: String { String(value) }

}

// MARK: - Argument values

enum CSVNullHandlingArgument: String, ExpressibleByArgument, CaseIterable {
    case keepAsString = "keep-as-string"
    case omit

    var value: CSVNullHandling {
        switch self {
        case .keepAsString: .keepAsString
        case .omit: .omit
        }
    }
}

enum CSVGeometryFormatArgument: String, ExpressibleByArgument, CaseIterable {
    case auto
    case wkt
    case ewkb
    case geojson

    var value: CSVGeometryFormat {
        switch self {
        case .auto: .auto
        case .wkt: .wkt
        case .ewkb: .ewkb
        case .geojson: .geojson
        }
    }
}

enum CSVLineEndingArgument: String, ExpressibleByArgument, CaseIterable {
    case lf
    case crlf

    var value: CSVLineEnding {
        switch self {
        case .lf: .lf
        case .crlf: .crlf
        }
    }
}
