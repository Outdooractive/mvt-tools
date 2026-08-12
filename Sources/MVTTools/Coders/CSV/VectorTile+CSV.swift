import Foundation
import GISTools
import GISToolsCSV
import Logging

extension VectorTile {

    // MARK: - Import

    /// Create a vector tile from CSV data.
    ///
    /// The tile's coordinates are automatically derived from the CSV bounding box.
    /// The CSV must have a header row; geometry is never guessed. When features
    /// carry a layer property (see `layerProperty`), they are split into separate
    /// layers accordingly.
    ///
    /// - Parameters:
    ///   - data: CSV data.
    ///   - delimiter: The field delimiter (default `","`).
    ///   - sortOption: An optional R-Tree sort option for spatial indexing.
    ///   - layerProperty: An optional property name used to assign features to layers.
    ///       When `nil`, all features are placed in a single default layer.
    ///   - layerAllowlist: An optional set of layer names to load. If `nil`, all layers are loaded.
    ///   - logger: An optional logger instance.
    /// - Throws: ``VectorTileError/parseFailed``,
    ///   ``VectorTileError/invalidCoordinate``, or
    ///   ``VectorTileError/coordinateOutOfBounds``.
    public init(
        csvData data: Data,
        delimiter: Character = CSVCoder.defaultDelimiter,
        indexed sortOption: RTreeSortOption? = nil,
        layerProperty: String? = VectorTile.defaultLayerPropertyName,
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) throws {
        guard let featureCollection = try? CSVCoder.read(from: data, delimiter: delimiter) else {
            throw VectorTileError.parseFailed(
                format: "CSV",
                reason: "unable to parse FeatureCollection from data")
        }
        guard let fcBoundingBox = featureCollection.calculateBoundingBox() else {
            throw VectorTileError.parseFailed(
                format: "CSV",
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
        self.origin = .csv

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

    /// Create a vector tile by reading it from `url`, which must be a CSV file.
    ///
    /// The tile's coordinates are automatically derived from the CSV bounding box.
    ///
    /// - Parameters:
    ///   - url: The file URL to read CSV data from.
    ///   - delimiter: The field delimiter (default `","`).
    ///   - sortOption: An optional R-Tree sort option for spatial indexing.
    ///   - layerProperty: An optional property name used to assign features to layers.
    ///       When `nil`, all features are placed in a single default layer.
    ///   - layerAllowlist: An optional set of layer names to load. If `nil`, all layers are loaded.
    ///   - logger: An optional logger instance.
    /// - Throws: ``VectorTileError/fileReadFailed``,
    ///   ``VectorTileError/parseFailed``,
    ///   ``VectorTileError/invalidCoordinate``, or
    ///   ``VectorTileError/coordinateOutOfBounds``.
    public init(
        contentsOfCSV url: URL,
        delimiter: Character = CSVCoder.defaultDelimiter,
        indexed sortOption: RTreeSortOption? = nil,
        layerProperty: String? = VectorTile.defaultLayerPropertyName,
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        }
        catch {
            (logger ?? VectorTile.logger)?.warning("Failed to load CSV from \(url)")
            throw VectorTileError.fileReadFailed(
                url: url,
                reason: error.localizedDescription)
        }
        try self.init(
            csvData: data,
            delimiter: delimiter,
            indexed: sortOption,
            layerProperty: layerProperty,
            layerAllowlist: layerAllowlist,
            logger: logger)
    }

    // MARK: - Export

    /// Export the tile's content as CSV data.
    ///
    /// - Parameter delimiter: The field delimiter (default `","`).
    /// - Parameter options: Export options controlling simplification.
    /// - Returns: The CSV data, or `nil` if serialization fails.
    public func toCsvData(
        delimiter: Character = CSVCoder.defaultDelimiter,
        options: VectorTile.ExportOptions? = nil
    ) -> Data? {
        let allFeatures = processFeatures(layers.values.flatMap(\.features), options: options)
        let fc = FeatureCollection(allFeatures)
        return try? CSVCoder.write(fc, delimiter: delimiter)
    }

    /// Write the tile's content as CSV to a file URL.
    ///
    /// - Parameter url: The destination file URL.
    /// - Parameter delimiter: The field delimiter (default `","`).
    /// - Parameter options: Export options controlling simplification.
    /// - Returns: `true` if the write succeeds, `false` otherwise.
    @discardableResult
    public func writeCSV(
        to url: URL,
        delimiter: Character = CSVCoder.defaultDelimiter,
        options: VectorTile.ExportOptions? = nil
    ) -> Bool {
        guard let data: Data = toCsvData(delimiter: delimiter, options: options) else { return false }
        do {
            try data.write(to: url)
            return true
        }
        catch {
            return false
        }
    }

}
