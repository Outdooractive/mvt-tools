import ArgumentParser
import Foundation
import Logging
import MVTTools

@main
struct CLI: AsyncParsableCommand {

    static let logger: Logger = Logger(label: "mvttool")

    static var configuration = CommandConfiguration(
        commandName: "mvt",
        abstract: "A utility for inspecting and working with vector tiles.",
        version: "1.2.3",
        subcommands: [Dump.self, Info.self, Merge.self, Query.self, Export.self, Import.self],
        defaultSubcommand: Dump.self)

}

struct Options: ParsableArguments {

    @Flag(name: .shortAndLong, help: "Print some debug info")
    var verbose: Bool = false

    @Option(name: .short, help: "Tile zoom level - if it can't be extracted from the path")
    var z: Int?

    @Option(name: .short, help: "Tile x coordinate - if it can't be extracted from the path")
    var x: Int?

    @Option(name: .short, help: "Tile y coordinate - if it can't be extracted from the path")
    var y: Int?

    @Argument(
        help: "The MVT resource (file or URL). The tile coordinate can be extracted from the path if it's either in the form '/z/x/y' or 'z_x_y'",
        completion: .file(extensions: ["pbf", "mvt"]))
    var path: String

    // Try to parse x/y/z from the path/URL
    mutating func parseUrl(
        extractCoordinate: Bool = true,
        checkExistence: Bool = true)
        throws -> URL
    {
        let url: URL
        if path.hasPrefix("http") {
            guard let parsedUrl = URL(string: path) else {
                throw "\(path) is not a valid URL"
            }
            url = parsedUrl
        }
        else {
            url = URL(fileURLWithPath: path)
            if checkExistence {
                guard try url.checkResourceIsReachable() else {
                    throw "The file '\(path)' doesn't exist."
                }
            }
        }

        guard extractCoordinate else { return url }

        if x == nil
            || y == nil
            || z == nil
        {
            let urlParts = path.extractingGroupsUsingPattern("\\/(\\d+)\\/(\\d+)\\/(\\d+)(?:\\/|\\.)", caseInsensitive: false)
            if urlParts.count >= 3 {
                if let partX = Int(urlParts[1]),
                   let partY = Int(urlParts[2]),
                   let partZ = Int(urlParts[0])
                {
                    x = partX
                    y = partY
                    z = partZ
                }
            }
            else {
                let pathParts = path.extractingGroupsUsingPattern("(\\d+)_(\\d+)_(\\d+)", caseInsensitive: false)
                if pathParts.count >= 3 {
                    if let partX = Int(pathParts[1]),
                       let partY = Int(pathParts[2]),
                       let partZ = Int(pathParts[0])
                    {
                        x = partX
                        y = partY
                        z = partZ
                    }
                }
            }
        }

        guard let x = x,
              let y = y,
              let z = z
        else { throw "Need z, x and y" }

        guard x >= 0 else { throw "x must be >= 0" }
        guard y >= 0 else { throw "y must be >= 0" }
        guard z >= 0 else { throw "z must be >= 0" }

        let maximumTileCoordinate: Int = 1 << z
        if x >= maximumTileCoordinate { throw "x at zoom \(z) must be smaller than \(maximumTileCoordinate)" }
        if y >= maximumTileCoordinate { throw "y at zoom \(z) must be smaller than \(maximumTileCoordinate)" }

        return url
    }

}
