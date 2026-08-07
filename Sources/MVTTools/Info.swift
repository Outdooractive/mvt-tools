#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools

// MARK: Info functions

extension VectorTile {

    /// Summary statistics for a single layer in a vector tile.
    ///
    /// - Parameter name: The layer name.
    /// - Parameter features: Total count of features in the layer.
    /// - Parameter pointFeatures: Number of point or multi-point features.
    /// - Parameter linestringFeatures: Number of line-string or multi-line-string features.
    /// - Parameter polygonFeatures: Number of polygon or multi-polygon features.
    /// - Parameter unknownFeatures: Number of features with an unrecognized geometry type.
    /// - Parameter propertyNames: Dictionary mapping each property key to the number of features that use it.
    /// - Parameter propertyValues: Dictionary mapping each property key to a dictionary of distinct values and their occurrence counts.
    /// - Parameter version: The MVT layer version, if known.
    public struct LayerInfo {
        public let name: String
        public let features: Int
        public let pointFeatures: Int
        public let linestringFeatures: Int
        public let polygonFeatures: Int
        public let unknownFeatures: Int
        public let propertyNames: [String: Int]
        public let propertyValues: [String: [String: Int]]
        public let version: Int?
    }

    /// Decode a raw MVT `Data` value and return the names of every layer it contains.
    ///
    /// - Parameter data: The raw MVT (Mapbox Vector Tile) data to decode.
    /// - Returns: An array of layer name strings, or `nil` if the data could not be decoded.
    public static func layerNames(from data: Data) -> [String]? {
        guard let tile = MVTDecoder.vectorTile(from: data) else { return nil }
        return tile.layers.map { $0.name }
    }

    /// Load a tile from the given file URL and return the names of every layer it contains.
    ///
    /// - Parameter url: A file URL pointing to an MVT file on disk.
    /// - Returns: An array of layer name strings, or `nil` if the data could not be decoded.
    /// - Throws: ``VectorTileError/fileReadFailed`` if the file cannot be read.
    public static func layerNames(at url: URL) throws -> [String]? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        }
        catch {
            throw VectorTileError.fileReadFailed(
                url: url,
                reason: error.localizedDescription)
        }
        return layerNames(from: data)
    }

    /// Gather summary information about the features in each layer of this tile.
    ///
    /// - Returns: An array of ``LayerInfo`` values, one per layer, or `nil` if the tile has no layers.
    public func tileInfo() -> [LayerInfo]? {
        var result: [LayerInfo] = []

        for (layerName, layerContainer) in layers {
            var propertyNames: [String: Int] = [:]
            var propertyValues: [String: [String: Int]] = [:]

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

                for (key, value) in feature.properties {
                    propertyNames[key, default: 0] += 1

                    if let value = value as? CustomStringConvertible {
                        var thisKeyValues = propertyValues[key] ?? [:]
                        thisKeyValues[value.description, default: 0] += 1
                        propertyValues[key] = thisKeyValues
                    }
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
                propertyValues: propertyValues,
                version: nil))
        }

        return result
    }

    /// Decode a raw MVT `Data` value and gather summary information about each of its layers.
    ///
    /// Unlike the instance version of this method, the static variant works directly on raw data
    /// without requiring a fully-initialized ``VectorTile``.
    ///
    /// - Parameter data: The raw MVT data to decode.
    /// - Returns: An array of ``LayerInfo`` values, one per layer, or `nil` if the data could not be decoded.
    public static func tileInfo(from data: Data) -> [LayerInfo]? {
        guard let tile = MVTDecoder.vectorTile(from: data) else { return nil }

        var result: [LayerInfo] = []

        for layer in tile.layers {
            let (keys, values) = MVTDecoder.keysAndValues(forLayer: layer)
            var propertyNames: [String: Int] = [:]
            var propertyValues: [String: [String: Int]] = [:]

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
                    guard let key: String = keys.get(at: Int(tags.first)),
                          let value: Sendable = values.get(at: Int(tags.second))
                    else { continue }

                    propertyNames[key, default: 0] += 1

                    if let value = value as? CustomStringConvertible {
                        var thisKeyValues = propertyValues[key] ?? [:]
                        thisKeyValues[value.description, default: 0] += 1
                        propertyValues[key] = thisKeyValues
                    }
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
                propertyValues: propertyValues,
                version: Int(layer.version)))
        }

        return result
    }

    /// Load a tile from the given file URL and gather summary information about each of its layers.
    ///
    /// - Parameter url: A file URL pointing to an MVT file on disk.
    /// - Returns: An array of ``LayerInfo`` values, one per layer, or `nil` if the data could not be decoded.
    /// - Throws: ``VectorTileError/fileReadFailed`` if the file cannot be read.
    public static func tileInfo(at url: URL) throws -> [LayerInfo]? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        }
        catch {
            throw VectorTileError.fileReadFailed(
                url: url,
                reason: error.localizedDescription)
        }
        return tileInfo(from: data)
    }

}
