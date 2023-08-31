import ArgumentParser
import Foundation
import MVTTools

extension CLI {

    struct Info: AsyncParsableCommand {

        static var configuration = CommandConfiguration(abstract: "Print information about the vector tile")

        @OptionGroup
        var options: Options

        mutating func run() async throws {
            let url = try options.parseUrl(extractCoordinate: false)

            guard let tileInfo = VectorTile.tileInfo(at: url),
                  var layers = tileInfo["layers"] as? [[String: Any]]
            else { throw "Error retreiving the tile info for \(options.path)" }

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

            let result = dumpSideBySide(
                table,
                asTableWithHeaders: tableHeader)

            print(result)
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
