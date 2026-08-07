import Foundation
import GISTools
import GISToolsGPX
import Logging

extension VectorTile {

    // MARK: - Import

    /// Create a vector tile from GPX data.
    ///
    /// The tile's coordinates are automatically derived from the GPX bounding box.
    /// Waypoints, routes, and tracks are automatically split into separate layers
    /// named `"wpt"`, `"rte"`, and `"trk"` respectively.
    ///
    /// - Parameters:
    ///   - data: GPX data.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing.
    ///   - layerProperty: An optional property name used to assign features to layers.
    ///       When `nil`, features are split by their GPX element type
    ///       (`"gpx_type"` → `"wpt"`, `"rte"`, `"trk"`).
    ///   - layerAllowlist: An optional set of layer names to load. If `nil`, all layers are loaded.
    ///   - logger: An optional logger instance.
    /// - Throws: ``VectorTileError/parseFailed``,
    ///   ``VectorTileError/invalidCoordinate``, or
    ///   ``VectorTileError/coordinateOutOfBounds``.
    public init(
        gpxData data: Data,
        indexed sortOption: RTreeSortOption? = nil,
        layerProperty: String? = "gpx_type",
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) throws {
        guard let featureCollection = FeatureCollection(gpxData: data) else {
            throw VectorTileError.parseFailed(
                format: "GPX",
                reason: "unable to parse FeatureCollection from data")
        }
        guard let fcBoundingBox = featureCollection.calculateBoundingBox() else {
            throw VectorTileError.parseFailed(
                format: "GPX",
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
        self.origin = .gpx

        setGeoJson(
            geoJson: featureCollection,
            layerProperty: layerProperty,
            layerAllowlist: layerAllowlistSet)

        if let sortOption {
            createIndex(sortOption: sortOption)
        }
    }

    /// Create a vector tile by reading it from `url`, which must be a GPX file.
    /// Waypoints, routes, and tracks are automatically split into separate layers
    /// named `"wpt"`, `"rte"`, and `"trk"` respectively.
    ///
    /// - Parameters:
    ///   - url: The file URL to read GPX data from.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing.
    ///   - layerProperty: An optional property name used to assign features to layers.
    ///       When `nil`, features are split by their GPX element type (`"gpx_type"`).
    ///   - layerAllowlist: An optional set of layer names to load. If `nil`, all layers are loaded.
    ///   - logger: An optional logger instance.
    /// - Throws: ``VectorTileError/fileReadFailed``,
    ///   ``VectorTileError/parseFailed``,
    ///   ``VectorTileError/invalidCoordinate``, or
    ///   ``VectorTileError/coordinateOutOfBounds``.
    public init(
        contentsOfGPX url: URL,
        indexed sortOption: RTreeSortOption? = nil,
        layerProperty: String? = "gpx_type",
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        }
        catch {
            (logger ?? VectorTile.logger)?.warning("Failed to load GPX from \(url)")
            throw VectorTileError.fileReadFailed(
                url: url,
                reason: error.localizedDescription)
        }
        try self.init(
            gpxData: data,
            indexed: sortOption,
            layerProperty: layerProperty,
            layerAllowlist: layerAllowlist,
            logger: logger)
    }

    // MARK: - Export

    /// Export the tile's content as GPX data.
    ///
    /// - Parameter creator: The value for the `creator` attribute in the GPX output (default `"MVTTools"`).
    /// - Parameter options: Export options controlling simplification.
    /// - Returns: The GPX data, or `nil` if serialization fails.
    public func toGpxData(
        creator: String = "MVTTools",
        options: VectorTile.ExportOptions? = nil
    ) -> Data? {
        let allFeatures = processFeatures(layers.values.flatMap(\.features), options: options)
        let fc = FeatureCollection(allFeatures)
        return try? fc.gpxData(creator: creator)
    }

    /// Write the tile's content as GPX to a file URL.
    ///
    /// - Parameter url: The destination file URL.
    /// - Parameter creator: The value for the `creator` attribute in the GPX output.
    /// - Parameter options: Export options controlling simplification.
    /// - Returns: `true` if the write succeeds, `false` otherwise.
    @discardableResult
    public func writeGPX(
        to url: URL,
        creator: String = "MVTTools",
        options: VectorTile.ExportOptions? = nil
    ) -> Bool {
        guard let data: Data = toGpxData(creator: creator, options: options) else { return false }
        do {
            try data.write(to: url)
            return true
        }
        catch {
            return false
        }
    }

}
