#if !os(Linux)
    import CoreLocation
#endif
import Foundation
import GISTools

// MARK: Info functions

extension VectorTile {

    public struct LayerInfo {
        public let name: String
        public let features: Int
        public let pointFeatures: Int
        public let linestringFeatures: Int
        public let polygonFeatures: Int
        public let unknownFeatures: Int
        public let propertyNames: [String: Int]
        public let version: Int?
    }

    /// Read a tile from `data` and return its layer names
    public static func layerNames(from data: Data) -> [String]? {
        guard let tile = MVTDecoder.vectorTile(from: data) else { return nil }
        return tile.layers.map { $0.name }
    }

    /// Read a tile from `url` and return its layer names
    public static func layerNames(at url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return layerNames(from: data)
    }

    // [{
    //   name: 'world',
    //   features: 1,
    //   point_features: 0,
    //   linestring_features: 0,
    //   polygon_features: 1,
    //   unknown_features: 0,
    //   property_names: [:],
    //   version: 2
    // }]

    /// Information about the features in a tile, per layer.
    public func tileInfo() -> [LayerInfo]? {
        var result: [LayerInfo] = []

        for (layerName, layerContainer) in layers {
            var propertyNames: [String: Int] = [:]

            var pointFeatures = 0
            var lineStringFeatures = 0
            var polygonFeatures = 0
            var unknownFeatures = 0

            for feature in layerContainer.features {
                switch feature.geometry.type {
                case .point, .multiPoint: pointFeatures += 1
                case .lineString, .multiLineString: lineStringFeatures += 1
                case .polygon, .multiPolygon: polygonFeatures += 1
                default: unknownFeatures += 1
                }

                for key in feature.properties.keys {
                    propertyNames[key, default: 0] += 1
                }
            }

            result.append(LayerInfo(
                name: layerName,
                features: pointFeatures + lineStringFeatures + polygonFeatures + unknownFeatures,
                pointFeatures: pointFeatures,
                linestringFeatures: lineStringFeatures,
                polygonFeatures: polygonFeatures,
                unknownFeatures: unknownFeatures,
                propertyNames: propertyNames,
                version: nil))
        }

        return result
    }

    /// Read a tile from `data` and return some information about the tile per layer.
    public static func tileInfo(from data: Data) -> [LayerInfo]? {
        guard let tile = MVTDecoder.vectorTile(from: data) else { return nil }

        var result: [LayerInfo] = []

        for layer in tile.layers {
            let keys: [String] = layer.keys
            var propertyNames: [String: Int] = [:]

            var pointFeatures = 0
            var lineStringFeatures = 0
            var polygonFeatures = 0
            var unknownFeatures = 0

            for feature in layer.features {
                switch feature.type {
                case .point: pointFeatures += 1
                case .linestring: lineStringFeatures += 1
                case .polygon: polygonFeatures += 1
                case .unknown: unknownFeatures += 1
                }

                for tags in feature.tags.pairs() {
                    guard let key: String = keys.get(at: Int(tags.first)) else { continue }

                    propertyNames[key, default: 0] += 1
                }
            }

            result.append(LayerInfo(
                name: layer.name,
                features: pointFeatures + lineStringFeatures + polygonFeatures + unknownFeatures,
                pointFeatures: pointFeatures,
                linestringFeatures: lineStringFeatures,
                polygonFeatures: polygonFeatures,
                unknownFeatures: unknownFeatures,
                propertyNames: propertyNames,
                version: Int(layer.version)))
        }

        return result
    }

    /// Read a tile from `url` and return some information about the tile per layer.
    public static func tileInfo(at url: URL) -> [LayerInfo]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return tileInfo(from: data)
    }

}
