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
        /// The tile was created from a vector tile
        case mvt
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
    public private(set) var layerNames: [String]

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
    public var boundingBox: BoundingBox

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
    /// - Returns: `nil` when the tile coordinates are invalid or out of bounds.
    public init?(
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        indexed sortOption: RTreeSortOption? = nil,
        logger: Logger? = nil
    ) {
        guard x >= 0, y >= 0, z >= 0 else {
            (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Invalid tile coordinate")
            return nil
        }

        let maximumTileCoordinate = 1 << z
        if x >= maximumTileCoordinate || y >= maximumTileCoordinate {
            (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Tile coordinate outside bounds")
            return nil
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
    /// - Returns: `nil` when the tile coordinates are invalid or out of bounds.
    public init?(
        tile: MapTile,
        projection: Projection = .epsg4326,
        indexed sortOption: RTreeSortOption? = nil,
        logger: Logger? = nil
    ) {
        self.init(
            x: tile.x,
            y: tile.y,
            z: tile.z,
            projection: projection,
            indexed: sortOption,
            logger: logger)
    }

    /// Create a vector tile from `data`, which must be in MVT format, at `z`/`x`/`y`.
    ///
    /// - Parameters:
    ///   - data: The raw MVT protobuf data.
    ///   - x: The tile's x coordinate.
    ///   - y: The tile's y coordinate.
    ///   - z: The tile's zoom level.
    ///   - projection: The spatial projection for the tile. Defaults to `.epsg4326`.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing. Defaults to `nil`.
    ///   - layerAllowlist: An optional set of layer names to load. If `nil`, all layers are loaded.
    ///   - logger: An optional logger instance. Defaults to `nil`.
    /// - Returns: `nil` when the tile coordinates are invalid, out of bounds, or decoding fails.
    public init?(
        data: Data,
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        indexed sortOption: RTreeSortOption? = nil,
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) {
        guard x >= 0, y >= 0, z >= 0 else {
            (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Invalid tile coordinate")
            return nil
        }

        let maximumTileCoordinate = 1 << z
        if x >= maximumTileCoordinate || y >= maximumTileCoordinate {
            (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Tile coordinate outside bounds")
            return nil
        }

        self.x = x
        self.y = y
        self.z = z
        self.projection = projection
        self.logger = logger

        // Note: A plain array might actually be faster for few entries -> check this
        let layerAllowlistSet: Set<String>? = if let layerAllowlist {
            Set(layerAllowlist)
        }
        else {
            nil
        }

        switch projection {
        case .noSRID:
            self.boundingBox = BoundingBox(
                southWest: Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
                northEast: Coordinate3D(x: 4096, y: 4096, projection: .noSRID))

        case .epsg3857, .epsg4326, .epsg4978:
            self.boundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: projection)
        }

        guard let parsedLayers = MVTDecoder.decode(
            from: data,
            x: x,
            y: y,
            z: z,
            projection: projection,
            layerAllowlist: layerAllowlistSet,
            calculateBoundingBox: true,
            logger: logger)
        else { return nil }

        self.layers = parsedLayers
        self.layerNames = Array(layers.keys)
        self.origin = .mvt

        if let sortOption {
            createIndex(sortOption: sortOption)
        }
    }

    /// Create a vector tile from `data`, which must be in MVT format, at some tile coordinate.
    ///
    /// - Parameters:
    ///   - data: The raw MVT protobuf data.
    ///   - tile: The map tile coordinate.
    ///   - projection: The spatial projection for the tile. Defaults to `.epsg4326`.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing. Defaults to `nil`.
    ///   - layerAllowlist: An optional set of layer names to load. If `nil`, all layers are loaded.
    ///   - logger: An optional logger instance. Defaults to `nil`.
    /// - Returns: `nil` when the tile coordinates are invalid, out of bounds, or decoding fails.
    public init?(
        data: Data,
        tile: MapTile,
        projection: Projection = .epsg4326,
        indexed sortOption: RTreeSortOption? = nil,
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) {
        self.init(
            data: data,
            x: tile.x,
            y: tile.y,
            z: tile.z,
            projection: projection,
            indexed: sortOption,
            layerAllowlist: layerAllowlist,
            logger: logger)
    }

    /// Create a vector tile by reading it from `url`, which must be in MVT format, at `z`/`x`/`y`.
    ///
    /// - Parameters:
    ///   - url: The file URL to read MVT data from.
    ///   - x: The tile's x coordinate.
    ///   - y: The tile's y coordinate.
    ///   - z: The tile's zoom level.
    ///   - projection: The spatial projection for the tile. Defaults to `.epsg4326`.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing. Defaults to `nil`.
    ///   - layerAllowlist: An optional set of layer names to load. If `nil`, all layers are loaded.
    ///   - logger: An optional logger instance. Defaults to `nil`.
    /// - Returns: `nil` when the file cannot be read, coordinates are invalid, or decoding fails.
    public init?(
        contentsOf url: URL,
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        indexed sortOption: RTreeSortOption? = nil,
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) {
        guard let data = try? Data(contentsOf: url) else {
            (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Failed to load vector tile from \(url)")
            return nil
        }

        self.init(
            data: data,
            x: x,
            y: y,
            z: z,
            projection: projection,
            indexed: sortOption,
            layerAllowlist: layerAllowlist,
            logger: logger)
    }

    /// Create a vector tile by reading it from `url`, which must be in MVT format, at some tile coordinate.
    ///
    /// - Parameters:
    ///   - url: The file URL to read MVT data from.
    ///   - tile: The map tile coordinate.
    ///   - projection: The spatial projection for the tile. Defaults to `.epsg4326`.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing. Defaults to `nil`.
    ///   - layerAllowlist: An optional set of layer names to load. If `nil`, all layers are loaded.
    ///   - logger: An optional logger instance. Defaults to `nil`.
    /// - Returns: `nil` when the file cannot be read, coordinates are invalid, or decoding fails.
    public init?(
        contentsOf url: URL,
        tile: MapTile,
        projection: Projection = .epsg4326,
        indexed sortOption: RTreeSortOption? = nil,
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) {
        self.init(
            contentsOf: url,
            x: tile.x,
            y: tile.y,
            z: tile.z,
            projection: projection,
            indexed: sortOption,
            layerAllowlist: layerAllowlist,
            logger: logger)
    }

    /// Create a vector tile from `data`, which must be some GeoJSON object.
    ///
    /// The tile's coordinates are automatically derived from the GeoJSON bounding box.
    ///
    /// - Parameters:
    ///   - data: A `Data` object containing a GeoJSON FeatureCollection.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing. Defaults to `nil`.
    ///   - layerProperty: An optional property name used to assign features to layers.
    ///       Defaults to `VectorTile.defaultLayerPropertyName`.
    ///   - layerAllowlist: An optional set of layer names to load. If `nil`, all layers are loaded.
    ///   - logger: An optional logger instance. Defaults to `nil`.
    /// - Returns: `nil` when the GeoJSON data cannot be parsed or the tile coordinates are invalid.
    public init?(
        geoJsonData data: Data,
        indexed sortOption: RTreeSortOption? = nil,
        layerProperty: String? = VectorTile.defaultLayerPropertyName,
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) {
        guard let featureCollection = FeatureCollection(jsonData: data),
              let fcBoundingBox = featureCollection.calculateBoundingBox()
        else { return nil }

        // Find the minimal tile for the GeoJSON
        let tile = MapTile(boundingBox: fcBoundingBox)
        self.x = tile.x
        self.y = tile.y
        self.z = tile.z

        guard x >= 0, y >= 0, z >= 0 else {
            (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Invalid tile coordinate")
            return nil
        }

        let maximumTileCoordinate = 1 << z
        if x >= maximumTileCoordinate || y >= maximumTileCoordinate {
            (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Tile coordinate outside bounds")
            return nil
        }

        self.projection = .epsg4326
        self.boundingBox = tile.boundingBox(projection: projection)
        self.logger = logger

        // Note: A plain array might actually be faster for few entries -> check this
        let layerAllowlistSet: Set<String>? = if let layerAllowlist {
            Set(layerAllowlist)
        }
        else {
            nil
        }

        self.layers = [:]
        self.layerNames = []
        self.origin = .geoJson

        setGeoJson(
            geoJson: featureCollection,
            layerProperty: layerProperty,
            layerAllowlist: layerAllowlistSet)

        if let sortOption {
            createIndex(sortOption: sortOption)
        }
    }

    /// Create a vector tile by reading it from `url`, which must be some GeoJSON object.
    ///
    /// - Parameters:
    ///   - url: The file URL to read GeoJSON data from.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing. Defaults to `nil`.
    ///   - layerProperty: An optional property name used to assign features to layers.
    ///       Defaults to `VectorTile.defaultLayerPropertyName`.
    ///   - layerAllowlist: An optional set of layer names to load. If `nil`, all layers are loaded.
    ///   - logger: An optional logger instance. Defaults to `nil`.
    /// - Returns: `nil` when the file cannot be read or the GeoJSON data cannot be parsed.
    public init?(
        contentsOfGeoJson url: URL,
        indexed sortOption: RTreeSortOption? = nil,
        layerProperty: String? = VectorTile.defaultLayerPropertyName,
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) {
        guard let data = try? Data(contentsOf: url) else {
            (logger ?? VectorTile.logger)?.warning("Failed to import GeoJSON from \(url)")
            return nil
        }

        self.init(
            geoJsonData: data,
            indexed: sortOption,
            layerProperty: layerProperty,
            layerAllowlist: layerAllowlist,
            logger: logger)
    }

}

// MARK: - Functions on the tile

extension VectorTile {

    /// Returns the tile's content as MVT data.
    ///
    /// - Parameter options: Export options for buffer, compression, and simplification. Defaults to standard options.
    /// - Returns: The raw MVT protobuf data, or `nil` if encoding fails.
    public func data(options: ExportOptions? = nil) -> Data? {
        MVTEncoder.encode(
            layers: layers,
            x: x,
            y: y,
            z: z,
            projection: projection,
            options: options ?? ExportOptions())
    }

    /// Writes the tile's content to `url` in MVT format.
    ///
    /// - Parameters:
    ///   - url: The destination file URL.
    ///   - options: Export options for buffer, compression, and simplification. Defaults to standard options.
    /// - Returns: `true` if the write succeeds, otherwise `false`.
    @discardableResult
    public func write(
        to url: URL,
        options: ExportOptions? = nil
    ) -> Bool {
        guard let data: Data = data(options: options) else { return false }

        do {
            try data.write(to: url)
        }
        catch {
            return false
        }

        return true
    }

    /// Removes all content from the tile.
    public mutating func clear() {
        layers = [:]
        layerNames = []
    }

    /// Creates a new tile by extracting the named layers from this tile.
    ///
    /// - Parameter layerNames: The layer names to extract into the new tile.
    /// - Returns: A new `VectorTile` containing only the specified layers, or `nil` if creation fails.
    public func extract(layerNames: [String]) -> VectorTile? {
        guard var newTile = VectorTile(x: x, y: y, z: z, projection: projection) else { return nil }

        for name in layerNames {
            newTile.layers[name] = layers[name]
        }
        newTile.layerNames = Array(newTile.layers.keys)

        return newTile
    }

}

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

extension VectorTile: CustomStringConvertible {

    /// A textual description
    public var description: String {
        let layersAndCount = layers.map({ "\($0):\($1.features.count)" })
            .sorted()
            .joined(separator: ", ")
        return "<Tile@x: \(x), y: \(y), z: \(z), projection: \(projection), indexed: \(isIndexed), \(boundingBox), layers: \(layersAndCount)>"
    }

}
