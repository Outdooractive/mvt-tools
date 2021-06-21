#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools
import struct GISTools.Polygon

public struct VectorTile {

    // MARK: -

    public enum TileProjection: CustomStringConvertible {
        /// The unmodifed vector tile coordinates
        case tile
        /// EPSG:3857 - web mercator
        case epsg3857
        /// EPSG:4326 - geodetic
        case epsg4326

        public var description: String {
            switch self {
            case .tile: return "None"
            case .epsg3857: return "EPSG:3857"
            case .epsg4326: return "EPSG:4326"
            }
        }
    }

    // MARK: - Properties
    // MARK: Public

    public let x: Int
    public let y: Int
    public let z: Int

    public private(set) var layerNames: [String]
    public func hasLayer(_ name: String) -> Bool {
        layerNames.contains(name)
    }

    public let projection: TileProjection

    public var isEmpty: Bool {
        return layers.isEmpty
    }

    public internal(set) var isIndexed: Bool = false

    public var boundingBox: BoundingBox

    // MARK: Private/Internal

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

    public var printParseFailures: Bool = {
        var isDebugBuild: Bool = false
        assert({
            isDebugBuild = true
            return true
        }())
        return isDebugBuild
    }()

    // MARK: - Initializers

    public init?(
        x: Int,
        y: Int,
        z: Int,
        projection: TileProjection = .epsg4326)
    {
        guard x >= 0, y >= 0, z >= 0 else { return nil }

        let maximumTileCoordinate: Int = 1 << z
        if x >= maximumTileCoordinate || y >= maximumTileCoordinate { return nil }

        self.x = x
        self.y = y
        self.z = z
        self.projection = projection

        self.layers = [:]
        self.layerNames = []

        switch projection {
        case .tile:
            self.boundingBox = BoundingBox(
                southWest: Coordinate3D(latitude: 0.0, longitude: 0.0),
                northEast: Coordinate3D(latitude: 4096, longitude: 4096))

        case .epsg3857:
            self.boundingBox = Projection.epsg3857TileBounds(x: x, y: y, z: z)

        case .epsg4326:
            self.boundingBox = Projection.epsg4236TileBounds(x: x, y: y, z: z)
        }
    }

    public init?(
        data: Data,
        x: Int,
        y: Int,
        z: Int,
        projection: TileProjection = .epsg4326,
        layerWhitelist: [String]? = nil)
    {
        guard x >= 0, y >= 0, z >= 0 else { return nil }

        let maximumTileCoordinate: Int = 1 << z
        if x >= maximumTileCoordinate || y >= maximumTileCoordinate { return nil }

        self.x = x
        self.y = y
        self.z = z
        self.projection = projection

        // Note: A plain array might actually be faster for few entries -> check this
        let layerWhitelistSet: Set<String>?
        if let layerWhitelist = layerWhitelist {
            layerWhitelistSet = Set(layerWhitelist)
        }
        else {
            layerWhitelistSet = nil
        }

        guard let parsedLayers = VectorTile.loadTileFrom(data: data, x: x, y: y, z: z, projection: projection, layerWhitelist: layerWhitelistSet) else { return nil }

        self.layers = parsedLayers
        self.layerNames = Array(layers.keys)

        switch projection {
        case .tile:
            self.boundingBox = BoundingBox(
                southWest: Coordinate3D(latitude: 0.0, longitude: 0.0),
                northEast: Coordinate3D(latitude: 4096, longitude: 4096))

        case .epsg3857:
            self.boundingBox = Projection.epsg3857TileBounds(x: x, y: y, z: z)

        case .epsg4326:
            self.boundingBox = Projection.epsg4236TileBounds(x: x, y: y, z: z)
        }
    }

    public init?(
        contentsOf url: URL,
        x: Int,
        y: Int,
        z: Int,
        projection: TileProjection = .epsg4326,
        layerWhitelist: [String]? = nil)
    {
        guard x >= 0, y >= 0, z >= 0 else { return nil }

        let maximumTileCoordinate: Int = 1 << z
        if x >= maximumTileCoordinate || y >= maximumTileCoordinate { return nil }

        self.x = x
        self.y = y
        self.z = z
        self.projection = projection

        // Note: A plain array might actually be faster for few entries -> check this
        let layerWhitelistSet: Set<String>?
        if let layerWhitelist = layerWhitelist {
            layerWhitelistSet = Set(layerWhitelist)
        }
        else {
            layerWhitelistSet = nil
        }

        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let parsedLayers = VectorTile.loadTileFrom(data: data, x: x, y: y, z: z, projection: projection, layerWhitelist: layerWhitelistSet) else { return nil}

        self.layers = parsedLayers
        self.layerNames = Array(layers.keys)

        switch projection {
        case .tile:
            self.boundingBox = BoundingBox(
                southWest: Coordinate3D(latitude: 0.0, longitude: 0.0),
                northEast: Coordinate3D(latitude: 4096, longitude: 4096))

        case .epsg3857:
            self.boundingBox = Projection.epsg3857TileBounds(x: x, y: y, z: z)

        case .epsg4326:
            self.boundingBox = Projection.epsg4236TileBounds(x: x, y: y, z: z)
        }
    }

}

// MARK: - Functions on the tile

extension VectorTile {

    // TODO: Compression
    public func data() -> Data? {
        return VectorTile.tileDataFor(layers: layers, x: x, y: y, z: z, projection: projection)
    }

    // TODO: Compression
    @discardableResult
    public func write(to url: URL) -> Bool {
        guard let data: Data = self.data() else { return false }

        do {
            try data.write(to: url)
        }
        catch {
            return false
        }

        return true
    }

    public mutating func clear() {
        layers = [:]
        layerNames = []
    }

    public func extract(layerNames: [String]) -> VectorTile? {
        guard var newTile = VectorTile(x: x, y: y, z: z, projection: projection) else { return nil }

        for name in layerNames {
            newTile.layers[name] = layers[name]
        }

        return newTile
    }

}

extension VectorTile {

    /// Returns an array of GeoJson Features
    public func features(for layerName: String) -> [Feature]? {
        return layers[layerName]?.features
    }

    @discardableResult
    public mutating func setFeatures(_ features: [Feature], for layerName: String) -> Bool {
        let features: [Feature] = features.map { (feature) in
            var feature = feature
            feature.updateBoundingBox(onlyIfNecessary: true)

            if feature.id == nil {
                feature.id = UUID().uuidString
            }

            return feature
        }

        let boundingBoxes: [BoundingBox] = features.compactMap({ $0.boundingBox })
        var layerBoundingBox: BoundingBox?
        if !boundingBoxes.isEmpty {
            layerBoundingBox = boundingBoxes.reduce(boundingBoxes[0], +)
        }

        var newLayerContainer = LayerContainer(
            features: features,
            boundingBox: layerBoundingBox)

        if isIndexed {
            newLayerContainer.rTree = RTree(features)
        }

        layers[layerName] = newLayerContainer
        layerNames = Array(layers.keys)

        return true
    }

    @discardableResult
    public mutating func appendFeatures(_ features: [Feature], to layerName: String) -> Bool {
        var allFeatures: [Feature] = []

        if let layerContainer = layers[layerName] {
            allFeatures = layerContainer.features
        }

        allFeatures.append(contentsOf: features.map({ (feature) in
            var feature = feature
            feature.updateBoundingBox(onlyIfNecessary: true)

            if feature.id == nil {
                feature.id = UUID().uuidString
            }

            return feature
        }))

        let boundingBoxes: [BoundingBox] = allFeatures.compactMap({ $0.boundingBox })
        var layerBoundingBox: BoundingBox?
        if !boundingBoxes.isEmpty {
            layerBoundingBox = boundingBoxes.reduce(boundingBoxes[0], +)
        }

        var newLayerContainer = LayerContainer(
            features: allFeatures,
            boundingBox: layerBoundingBox)

        // TODO: Improve this, don't update the complete index
        if isIndexed {
            newLayerContainer.rTree = RTree(features)
        }

        layers[layerName] = newLayerContainer
        layerNames = Array(layers.keys)

        return true
    }

    // TODO: removeFeatures()

    @discardableResult
    public mutating func removeLayer(_ layerName: String) -> [Feature]? {
        let removedFeatures: LayerContainer? = layers.removeValue(forKey: layerName)
        layerNames = Array(layers.keys)
        return removedFeatures?.features
    }

}

extension VectorTile: CustomStringConvertible {

    public var description: String {
        return "<Tile @ x: \(x), y: \(y), z: \(z), projection: \(projection), indexed: \(isIndexed), layers: \(layerNames.joined(separator: ",")), boundingBox: \(boundingBox)>"
    }

}
