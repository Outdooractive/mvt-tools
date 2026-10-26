import ArgumentParser
import Foundation
import GISTools

/// A CLI projection argument: `auto`, a registered SRID, or a recognized WKT.
struct ProjectionArgument: ExpressibleByArgument, Equatable, Sendable {

    enum Value: Equatable, Sendable {
        case auto
        case projection(Projection)
    }

    let value: Value

    static var defaultValueDescription: String {
        "auto"
    }

    init(value: Value) {
        self.value = value
    }

    init?(argument: String) {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower == "auto" {
            self.value = .auto
            return
        }
        if lower == "nosrid" || lower == "none" {
            self.value = .projection(.noSRID)
            return
        }
        if lower.hasPrefix("srid=") {
            let value = trimmed.dropFirst("srid=".count).prefix { $0 != ";" }
            guard let srid = Int(value), let projection = Projection(srid: srid) else {
                return nil
            }
            self.value = .projection(projection)
            return
        }
        if lower.hasPrefix("epsg:") {
            guard let srid = Int(trimmed.dropFirst("epsg:".count)),
                  let projection = Projection(srid: srid)
            else {
                return nil
            }
            self.value = .projection(projection)
            return
        }
        if lower.hasPrefix("epsg"), let srid = Int(trimmed.dropFirst("epsg".count)) {
            guard let projection = Projection(srid: srid) else { return nil }
            self.value = .projection(projection)
            return
        }
        if lower.hasPrefix("urn:") {
            let value = trimmed.split(separator: ":").last.map(String.init) ?? ""
            guard let srid = Int(value), let projection = Projection(srid: srid) else {
                return nil
            }
            self.value = .projection(projection)
            return
        }
        if let srid = Int(trimmed), let projection = Projection(srid: srid) {
            self.value = .projection(projection)
            return
        }
        if let projection = Projection(wkt: trimmed) {
            self.value = .projection(projection)
            return
        }
        return nil
    }

    var projection: Projection? {
        switch value {
        case .auto: nil
        case let .projection(projection): projection
        }
    }

}

extension ProjectionArgument: CustomStringConvertible {

    var description: String {
        switch value {
        case .auto: "auto"
        case let .projection(projection):
            projection.hasSRID ? "EPSG:\(projection.srid)" : "noSRID"
        }
    }

}

/// Shared input/output projection options.
struct ProjectionOptions: ParsableArguments {

    @Option(
        name: [.customLong("ip", withSingleDash: true), .customLong("input-projection")],
        help: "Input CRS: auto, an SRID, EPSG:n, noSRID, or a registered WKT.")
    var inputProjection: ProjectionArgument = ProjectionArgument(value: .auto)

    @Option(
        name: [.customLong("op", withSingleDash: true), .customLong("output-projection")],
        help: "Output CRS: auto, an SRID, EPSG:n, noSRID, or a registered WKT.")
    var outputProjection: ProjectionArgument = ProjectionArgument(value: .auto)

    var input: Projection? {
        inputProjection.projection
    }

    var output: Projection? {
        outputProjection.projection
    }

}
