#if EnableMLT
import Foundation
import GISTools
import Gzip
import Logging
import MLTCore

/// Pure Swift MLT decoder.
enum MLTDecoderSwift {

    static func decode(
        from mltData: Data,
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        layerAllowlist: Set<String>? = nil,
        calculateBoundingBox: Bool = false,
        logger: Logger? = nil
    ) throws -> [String: VectorTile.LayerContainer] {
        var data = mltData
        if data.isGzipped {
            (logger ?? VectorTile.logger)?.info("\(z)/\(x)/\(y): MLT input data is gzipped")
            guard let decompressed = try? data.gunzipped() else {
                throw MLTDecoderError.decodeFailed
            }
            data = decompressed
        }

        let layers = try MLTDecoderCore.decode(data)
        var result: [String: VectorTile.LayerContainer] = [:]

        for layer in layers {
            guard layerAllowlist?.contains(layer.name) ?? true else {
                continue
            }

            let projectionFunction = Projections.forwardProjection(
                for: projection,
                x: x,
                y: y,
                z: z,
                extent: layer.extent)

            var features: [Feature] = []
            features.reserveCapacity(layer.featureCount)

            for index in 0 ..< layer.featureCount {
                let geometry = convertGeometry(
                    layer.geometries[index],
                    project: { projectionFunction(Int($0), Int($1)) })
                guard let geometry else { continue }

                var properties: [String: Sendable] = [:]
                properties.reserveCapacity(layer.properties.count)
                for (name, values) in layer.properties {
                    if index < values.count, let value = values[index] {
                        properties[name] = value.sendableValue
                    }
                }

                var feature = Feature(
                    geometry,
                    properties: properties,
                    calculateBoundingBox: calculateBoundingBox)

                if index < layer.ids.count, let id = layer.ids[index] {
                    if let value = Feature.Identifier.UIntId(exactly: id) {
                        feature.id = .uint(value)
                    }
                    else {
                        feature.id = .string(String(id))
                    }
                }

                features.append(feature)
            }

            if features.isNotEmpty {
                var layerBoundingBox: BoundingBox?
                let boundingBoxes = features.compactMap(\.boundingBox)
                if let first = boundingBoxes.first {
                    layerBoundingBox = boundingBoxes.dropFirst().reduce(first, +)
                }
                result[layer.name] = VectorTile.LayerContainer(
                    features: features,
                    boundingBox: layerBoundingBox)
            }
        }

        return result
    }

    private static func convertGeometry(
        _ geometry: MLTGeometry,
        project: (Int32, Int32) -> Coordinate3D
    ) -> GeoJsonGeometry? {
        switch geometry {
        case let .point(coordinate):
            return Point(project(coordinate.x, coordinate.y))

        case let .multiPoint(coordinates):
            return MultiPoint(coordinates.map { project($0.x, $0.y) })

        case let .lineString(coordinates):
            guard coordinates.count >= 2 else { return nil }
            return LineString(coordinates.map { project($0.x, $0.y) })

        case let .multiLineString(lines):
            let converted = lines.compactMap { line -> [Coordinate3D]? in
                guard line.count >= 2 else { return nil }
                return line.map { project($0.x, $0.y) }
            }
            guard converted.isNotEmpty else { return nil }
            return MultiLineString(converted)

        case let .polygon(rings):
            let converted = rings.compactMap { ring -> [Coordinate3D]? in
                guard ring.count >= 3 else { return nil }
                return ring.map { project($0.x, $0.y) }
            }
            guard converted.isNotEmpty else { return nil }
            return Polygon(converted)

        case let .multiPolygon(polygons):
            let converted = polygons.compactMap { polygon -> [[Coordinate3D]]? in
                let rings = polygon.compactMap { ring -> [Coordinate3D]? in
                    guard ring.count >= 3 else { return nil }
                    return ring.map { project($0.x, $0.y) }
                }
                guard rings.isNotEmpty else { return nil }
                return rings
            }
            guard converted.isNotEmpty else { return nil }
            return MultiPolygon(converted)
        }
    }

}

#endif
