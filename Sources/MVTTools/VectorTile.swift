#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
import struct GISTools.Polygon
import Logging

/// `VectorTile` holds the contents of one vector tile as GeoJSON.
/// It can read and write data in [MVT format](https://github.com/mapbox/vector-tile-spec/tree/master/2.1).
public struct VectorTile: Sendable {

    /// The default property name for the layer in exported GeoJSON Features.
    public static let defaultLayerPropertyName: String = "vt_layer"

    /// The original file format of the tile's data source.
    public enum Origin: String, Sendable {
        /// The tile was created from a GeoJSON file
        case geoJson
        /// The tile was created from an MVT vector tile
        case mvt
        /// The tile was created from an MLT vector tile
        case mlt
        /// The tile was created from a FIT file
        case fit
        /// The tile was created from a GPX file
        case gpx
        /// The tile was created from a CSV file
        case csv
        /// The tile was created from a Shapefile
        case shapefile
        /// The tile was created from a GeoPackage
        case geopackage
        /// The tile was created empty
        case none
    }

    // MARK: - Properties

    // MARK: Public

    /// A global logger instance for logging errors.
    /// Set this before using `VectorTile`.
    nonisolated(unsafe)
    public static var logger: Logger?

    /// The tile's x coordinate
    public let x: Int
    /// The tile's y coordinate
    public let y: Int
    /// The tile's zoom level
    public let z: Int

    /// The tile coordinates as a `MapTile`.
    public var mapTile: MapTile {
        MapTile(x: x, y: y, z: z)
    }

    /// The layer names in the tile
    public internal(set) var layerNames: [String] = []

    /// Returns a Boolean value indicating whether the tile contains a specific layer.
    ///
    /// - Parameter name: The layer name to check.
    /// - Returns: `true` if the tile contains the layer, otherwise `false`.
    public func hasLayer(_ name: String) -> Bool {
        layerNames.contains(name)
    }

    /// The tile's projection
    public let projection: Projection

    /// A Boolean value indicating whether the tile is empty.
    public var isEmpty: Bool {
        layers.isEmpty
    }

    /// A Boolean value indicating whether the tile is indexed, for faster querying
    public var isIndexed: Bool {
        indexSortOption != nil
    }

    /// The tile's bounding box
    public let boundingBox: BoundingBox

    /// The tile's origin
    public let origin: Origin

    // MARK: Private/Internal

    var indexSortOption: RTreeSortOption?

    struct LayerContainer {
        var features: [Feature]
        var boundingBox: BoundingBox?
        var rTree: RTree<Feature>?

        init(features: [Feature], boundingBox: BoundingBox?) {
            self.features = features
            self.boundingBox = boundingBox
        }
    }

    var layers: [String: LayerContainer] = [:]

    var layersWithContent: [(String, LayerContainer)] {
        layers.filter({ $0.value.features.isNotEmpty })
    }

    /// For logging errors
    var logger: Logger?

    // MARK: - Initializers

    /// Create an empty vector tile at `z`/`x`/`y`.
    ///
    /// - Parameters:
    ///   - x: The tile's x coordinate.
    ///   - y: The tile's y coordinate.
    ///   - z: The tile's zoom level.
    ///   - projection: The spatial projection for the tile. Defaults to `.epsg4326`.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing. Defaults to `nil`.
    ///   - logger: An optional logger instance. Defaults to `nil`.
    /// - Throws: ``VectorTileError/invalidCoordinate`` or
    ///   ``VectorTileError/coordinateOutOfBounds``.
    public init(
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        indexed sortOption: RTreeSortOption? = nil,
        logger: Logger? = nil
    ) throws {
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

        self.x = x
        self.y = y
        self.z = z
        self.projection = projection
        self.origin = .none
        self.logger = logger

        self.layers = [:]
        self.layerNames = []

        switch projection {
        case .noSRID:
            self.boundingBox = BoundingBox(
                southWest: Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
                northEast: Coordinate3D(x: 4096, y: 4096, projection: .noSRID))

        case .epsg3857, .epsg4326, .epsg4978:
            self.boundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: projection)
        }

        if let sortOption {
            createIndex(sortOption: sortOption)
        }
    }

    /// Create an empty vector tile at some map tile coordinate.
    ///
    /// - Parameters:
    ///   - tile: The map tile coordinate.
    ///   - projection: The spatial projection for the tile. Defaults to `.epsg4326`.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing. Defaults to `nil`.
    ///   - logger: An optional logger instance. Defaults to `nil`.
    /// - Throws: ``VectorTileError/invalidCoordinate`` or
    ///   ``VectorTileError/coordinateOutOfBounds``.
    public init(
        tile: MapTile,
        projection: Projection = .epsg4326,
        indexed sortOption: RTreeSortOption? = nil,
        logger: Logger? = nil
    ) throws {
        try self.init(
            x: tile.x,
            y: tile.y,
            z: tile.z,
            projection: projection,
            indexed: sortOption,
            logger: logger)
    }

    /// Removes all content from the tile, clearing all layers.
    public mutating func clear() {
        layers = [:]
        layerNames = []
    }

    /// Creates a new tile by extracting the named layers from this tile.
    ///
    /// - Parameter layerNames: The layer names to extract into the new tile.
    /// - Returns: A new `VectorTile` containing only the specified layers.
    /// - Throws: ``VectorTileError/invalidCoordinate`` or
    ///   ``VectorTileError/coordinateOutOfBounds``.
    public func extract(layerNames: [String]) throws -> VectorTile {
        var newTile = try VectorTile(x: x, y: y, z: z, projection: projection)

        for name in layerNames {
            newTile.layers[name] = layers[name]
        }
        newTile.layerNames = Array(newTile.layers.keys)

        return newTile
    }

}

// MARK: - Accessors

extension VectorTile {

    /// Returns an array of GeoJson Features from the given layer.
    ///
    /// - Parameter layerName: The name of the layer to fetch features from.
    /// - Returns: An array of `Feature` objects. Returns an empty array if the layer does not exist.
    public func features(for layerName: String) -> [Feature] {
        layers[layerName]?.features ?? []
    }

    /// Replace or add a layer with `features`.
    ///
    /// - Parameters:
    ///   - features: The features to set on the layer.
    ///   - layerName: The name of the layer to replace or create.
    /// - Returns: `true` on success.
    @discardableResult
    public mutating func setFeatures(
        _ features: [Feature],
        for layerName: String
    ) -> Bool {
        let features: [Feature] = features.map { (feature) in
            var feature = feature.projected(to: projection)
            feature.updateBoundingBox(onlyIfNecessary: true)

            if feature.id == nil {
                feature.id = .string(UUID().uuidString)
            }

            return feature
        }

        let boundingBoxes: [BoundingBox] = features.compactMap({ $0.boundingBox })
        var layerBoundingBox: BoundingBox?
        if boundingBoxes.isNotEmpty {
            layerBoundingBox = boundingBoxes.reduce(boundingBoxes[0], +)
        }

        var newLayerContainer = LayerContainer(
            features: features,
            boundingBox: layerBoundingBox)

        if let indexSortOption {
            newLayerContainer.rTree = RTree(features, sortOption: indexSortOption)
        }

        layers[layerName] = newLayerContainer
        layerNames = Array(layers.keys)

        return true
    }

    /// Append `features` to a layer, or create a new layer if it doesn't already exist.
    ///
    /// - Parameters:
    ///   - features: The features to append.
    ///   - layerName: The name of the layer to append to.
    /// - Returns: `true` on success.
    @discardableResult
    public mutating func appendFeatures(
        _ features: [Feature],
        to layerName: String
    ) -> Bool {
        var allFeatures: [Feature] = []

        if let layerContainer = layers[layerName] {
            allFeatures = layerContainer.features
        }

        allFeatures.append(contentsOf: features.map({ (feature) in
            var feature = feature.projected(to: projection)
            feature.updateBoundingBox(onlyIfNecessary: true)

            if feature.id == nil {
                feature.id = .string(UUID().uuidString)
            }

            return feature
        }))

        let boundingBoxes: [BoundingBox] = allFeatures.compactMap({ $0.boundingBox })
        var layerBoundingBox: BoundingBox?
        if boundingBoxes.isNotEmpty {
            layerBoundingBox = boundingBoxes.reduce(boundingBoxes[0], +)
        }

        var newLayerContainer = LayerContainer(
            features: allFeatures,
            boundingBox: layerBoundingBox)

        // TODO: Improve this, don't update the complete index
        if let indexSortOption {
            newLayerContainer.rTree = RTree(allFeatures, sortOption: indexSortOption)
        }

        layers[layerName] = newLayerContainer
        layerNames = Array(layers.keys)

        return true
    }

    /// Remove features from a layer.
    ///
    /// - Parameters:
    ///   - layerName: The name of the layer to remove features from.
    ///   - shouldBeRemoved: A closure that takes a `Feature` and returns `true` if it should be removed.
    /// - Returns: `true` if the layer exists and features were removed, otherwise `false`.
    @discardableResult
    public mutating func removeFeatures(
        fromLayer layerName: String,
        where shouldBeRemoved: (Feature) -> Bool
    ) -> Bool {
        guard let layerContainer = layers[layerName] else { return false }

        var allFeatures = layerContainer.features
        allFeatures.removeAll(where: shouldBeRemoved)

        let boundingBoxes: [BoundingBox] = allFeatures.compactMap({ $0.boundingBox })
        var layerBoundingBox: BoundingBox?
        if boundingBoxes.isNotEmpty {
            layerBoundingBox = boundingBoxes.reduce(boundingBoxes[0], +)
        }

        var newLayerContainer = LayerContainer(
            features: allFeatures,
            boundingBox: layerBoundingBox)

        // TODO: Improve this, don't update the complete index
        if let indexSortOption {
            newLayerContainer.rTree = RTree(allFeatures, sortOption: indexSortOption)
        }

        layers[layerName] = newLayerContainer
        layerNames = Array(layers.keys)

        return true
    }

    /// Remove a layer from the tile.
    ///
    /// - Parameter layerName: The name of the layer to remove.
    /// - Returns: The removed layer's previous content, or `nil` if the layer did not exist.
    @discardableResult
    public mutating func removeLayer(_ layerName: String) -> [Feature]? {
        let removedFeatures: LayerContainer? = layers.removeValue(forKey: layerName)
        layerNames = Array(layers.keys)
        return removedFeatures?.features
    }

}

// MARK: - CustomStringConvertible

extension VectorTile: CustomStringConvertible {

    /// A textual description
    public var description: String {
        let layersAndCount = layers.map({ "\($0):\($1.features.count)" })
            .sorted()
            .joined(separator: ", ")
        return "<Tile@x: \(x), y: \(y), z: \(z), projection: \(projection), indexed: \(isIndexed), \(boundingBox), layers: \(layersAndCount)>"
    }

}
