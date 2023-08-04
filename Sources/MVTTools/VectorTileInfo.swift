#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools

// MARK: Static functions

extension VectorTile {

    /// Read a tile from `data` and return its layer names
    public static func layerNames(from data: Data) -> [String]? {
        guard let tile = vectorTile(from: data) else { return nil }
        return tile.layers.map { $0.name }
    }

    /// Read a tile from `url` and return its layer names
    public static func layerNames(at url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return layerNames(from: data)
    }

    // { layers:
    //   [ { name: 'world',
    //      features: 1,
    //      point_features: 0,
    //      linestring_features: 0,
    //      polygon_features: 1,
    //      unknown_features: 0,
    //      raster_features: 0,
    //      version: 2 } ],
    //    errors: false }

    /// Read a tile from `data` and return some information about the tile
    public static func tileInfo(from data: Data) -> [String: Any]? {
        guard let tile = vectorTile(from: data) else { return nil }

        var layers: [[String: Any]] = []

        for layer in tile.layers {
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
            }

            let info: [String: Any] = [
                "name": layer.name,
                "version": Int(layer.version),
                "features": pointFeatures + lineStringFeatures + polygonFeatures + unknownFeatures,
                "point_features": pointFeatures,
                "linestring_features": lineStringFeatures,
                "polygon_features": polygonFeatures,
                "unknown_features": unknownFeatures,
            ]
            layers.append(info)
        }

        return [
            "layers": layers,
            "errors": false
        ]
    }

    /// Read a tile from `url` and return some information about the tile
    public static func tileInfo(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return tileInfo(from: data)
    }

}
