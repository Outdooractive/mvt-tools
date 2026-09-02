#if EnableFIT
import Foundation
import GISTools
import GISToolsFIT
import Logging

extension VectorTile {

    // MARK: - Import

    /// Create a vector tile from FIT data.
    ///
    /// The tile's coordinates are automatically derived from the FIT bounding box.
    /// Track records are stored as a ``MultiLineString`` feature with per-point
    /// sensor data, lap boundaries, and session/activity metadata.
    ///
    /// - Parameters:
    ///   - data: Binary FIT data.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing.
    ///   - layerProperty: An optional property name used to assign features to layers.
    ///       When `nil`, features are imported as-is from the FIT data.
    ///   - layerAllowlist: An optional set of layer names to load. If `nil`, all layers are loaded.
    ///   - logger: An optional logger instance.
    /// - Throws: ``VectorTileError/parseFailed``,
    ///   ``VectorTileError/invalidCoordinate``, or
    ///   ``VectorTileError/coordinateOutOfBounds``.
    public init(
        fitData data: Data,
        indexed sortOption: RTreeSortOption? = nil,
        layerProperty: String? = nil,
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) throws {
        guard let featureCollection = FeatureCollection(fitData: data) else {
            throw VectorTileError.parseFailed(
                format: "FIT",
                reason: "unable to parse FeatureCollection from data")
        }
        guard let fcBoundingBox = featureCollection.calculateBoundingBox() else {
            throw VectorTileError.parseFailed(
                format: "FIT",
                reason: "unable to calculate bounding box (empty collection)")
        }

        let tile = MapTile(boundingBox: fcBoundingBox)
        self.x = tile.x
        self.y = tile.y
        self.z = tile.z

        guard x >= 0, y >= 0, z >= 0 else {
            (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Invalid tile coordinate")
            throw VectorTileError.invalidCoordinate(x: x, y: y, z: z)
        }

        let maximumTileCoordinate = 1 << z
        if x >= maximumTileCoordinate || y >= maximumTileCoordinate {
            (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Tile coordinate outside bounds")
            throw VectorTileError.coordinateOutOfBounds(
                x: x, y: y, z: z, maxBound: maximumTileCoordinate)
        }

        self.projection = .epsg4326
        self.boundingBox = tile.boundingBox(projection: projection)
        self.logger = logger

        let layerAllowlistSet: Set<String>? = if let layerAllowlist {
            Set(layerAllowlist)
        }
        else {
            nil
        }

        self.layers = [:]
        self.layerNames = []
        self.origin = .fit

        let layerName = "Layer-0"

        if let layerProperty {
            featureCollection.features.divided(
                byKey: { feature in
                    let mapping: String = feature.property(for: layerProperty) ?? layerName
                    return mapping
                },
                onKey: { key, features in
                    if let layerAllowlistSet, !layerAllowlistSet.contains(key) { return }
                    appendFeatures(
                        features.map({ feature in
                            var feature = feature
                            feature.removeProperty(for: layerProperty)
                            return feature
                        }),
                        to: key)
                })
        }
        else {
            if let layerAllowlistSet, !layerAllowlistSet.contains(layerName) { return }
            appendFeatures(featureCollection.features, to: layerName)
        }

        if let sortOption {
            createIndex(sortOption: sortOption)
        }
    }

    /// Create a vector tile by reading it from `url`, which must be a FIT file.
    ///
    /// Track records are stored as a ``MultiLineString`` feature with per-point
    /// sensor data, lap boundaries, and session/activity metadata.
    ///
    /// - Parameters:
    ///   - url: The file URL to read FIT data from.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing.
    ///   - layerProperty: An optional property name used to assign features to layers.
    ///       When `nil`, features are imported as-is from the FIT data.
    ///   - layerAllowlist: An optional set of layer names to load. If `nil`, all layers are loaded.
    ///   - logger: An optional logger instance.
    /// - Throws: ``VectorTileError/fileReadFailed``,
    ///   ``VectorTileError/parseFailed``,
    ///   ``VectorTileError/invalidCoordinate``, or
    ///   ``VectorTileError/coordinateOutOfBounds``.
    public init(
        contentsOfFIT url: URL,
        indexed sortOption: RTreeSortOption? = nil,
        layerProperty: String? = nil,
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        }
        catch {
            (logger ?? VectorTile.logger)?.warning("Failed to load FIT from \(url)")
            throw VectorTileError.fileReadFailed(
                url: url,
                reason: error.localizedDescription)
        }
        try self.init(
            fitData: data,
            indexed: sortOption,
            layerProperty: layerProperty,
            layerAllowlist: layerAllowlist,
            logger: logger)
    }

    // MARK: - Export

    /// Export the tile's content as binary FIT data.
    ///
    /// - Parameter options: Export options controlling simplification.
    /// - Returns: The FIT data, or `nil` if serialization fails.
    public func toFitData(
        options: VectorTile.ExportOptions? = nil
    ) -> Data? {
        let allFeatures = processFeatures(layers.values.flatMap(\.features), options: options)
        let fc = FeatureCollection(allFeatures)
        return try? fc.fitData()
    }

    /// Write the tile's content as FIT to a file URL.
    ///
    /// - Parameter url: The destination file URL.
    /// - Parameter options: Export options controlling simplification.
    /// - Returns: `true` if the write succeeds, `false` otherwise.
    @discardableResult
    public func writeFIT(
        to url: URL,
        options: VectorTile.ExportOptions? = nil
    ) -> Bool {
        guard let data: Data = toFitData(options: options) else { return false }
        do {
            try data.write(to: url)
            return true
        }
        catch {
            return false
        }
    }

}
#endif
