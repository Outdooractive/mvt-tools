import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    struct Info: AsyncParsableCommand {

        static let configuration = CommandConfiguration(abstract: "Print information about the input file (MVT or GeoJSON)")

        @OptionGroup
        var options: Options

        @Argument(
            help: "The vector tile or GeoJSON (file or URL)",
            completion: .file(extensions: ["pbf", "mvt", "geojson", "json"]))
        var path: String

        mutating func run() async throws {
            let url = try options.parseUrl(fromPath: path)

            guard var layers = VectorTile.tileInfo(at: url)
                    ?? VectorTile(contentsOfGeoJson: url)?.tileInfo()
            else { throw CLIError("Error retreiving the tile info for '\(path)'") }

            layers.sort { first, second in
                guard let firstName = first["name"] as? String,
                      let secondName = second["name"] as? String
                else { return false }

                return firstName.compare(secondName) == .orderedAscending
            }

            let tableHeader = ["Name", "Features", "Points", "LineStrings", "Polygons", "Unknown", "Version"]
            let table: [[String]] = [
                layers.compactMap({ $0["name"] as? String }),
                layers.compactMap({ ($0["features"] as? Int)?.toString }),
                layers.compactMap({ ($0["point_features"] as? Int)?.toString }),
                layers.compactMap({ ($0["linestring_features"] as? Int)?.toString }),
                layers.compactMap({ ($0["polygon_features"] as? Int)?.toString }),
                layers.compactMap({ ($0["unknown_features"] as? Int)?.toString }),
                layers.compactMap({ ($0["version"] as? Int)?.toString }),
            ]

            if options.verbose {
                print("Info for tile '\(url.lastPathComponent)'")
            }

            let result = dumpSideBySide(
                table,
                asTableWithHeaders: tableHeader)

            print(result)

            if options.verbose {
                print("Done.")
            }
        }

        private func dumpSideBySide(
            _ strings: [[String]],
            asTableWithHeaders headers: [String])
            -> String
        {
            var result: [String] = []

            // Setup

            let columns: Int = strings.count
            let rows: Int = strings.reduce(0) { (result, array) in
                (array.count > result ? array.count : result)
            }

            var columnWidths: [Int] = strings.map { $0.reduce(0, { max($0, $1.count) }) }

            guard headers.count == strings.count else {
                print("headers and strings don't match")
                return ""
            }

            for (index, header) in headers.enumerated() {
                columnWidths[index] = max(columnWidths[index], header.count)
            }

            // Assembling the table

            var headerColumns: [String] = []
            var headerSeparators: [String] = []

            for column in 0 ..< columns {
                let string = headers.get(at: column) ?? ""
                let columnWidth = columnWidths[column]

                headerColumns.append((column == 0 ? " " : "") + string.padding(toLength: columnWidth, withPad: " ", startingAt: 0))
                headerSeparators.append((column == 0 ? "-" : "") + String(repeating: "-", count: columnWidths[column]))
            }

            result.append(headerColumns.joined(separator: " | "))
            result.append(headerSeparators.joined(separator: "-+-"))

            for row in 0 ..< rows {
                var currentColumns: [String] = []

                for column in 0 ..< columns {
                    let string = strings[column].get(at: row) ?? ""
                    currentColumns.append((column == 0 ? " " : "") + string.padding(toLength: columnWidths[column], withPad: " ", startingAt: 0))
                }

                result.append(currentColumns.joined(separator: " | "))
            }

            return result.joined(separator: "\n")
        }

    }

}
