import Foundation
import GISTools
import Logging

extension VectorTile {

    // MARK: - Import

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
        mvtData data: Data,
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

        switch projection {
        case .noSRID:
            self.boundingBox = BoundingBox(
                southWest: Coordinate3D(x: 0.0, y: 0.0, projection: .noSRID),
                northEast: Coordinate3D(x: Double(ExportOptions.extent), y: Double(ExportOptions.extent), projection: .noSRID))
        case .epsg3857, .epsg4326, .epsg4978:
            self.boundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: projection)
        }

        guard let parsedLayers = MVTDecoder.decode(
            from: data, x: x, y: y, z: z,
            projection: projection,
            layerAllowlist: layerAllowlist.map(Set.init),
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
    public init?(
        mvtData data: Data,
        tile: MapTile,
        projection: Projection = .epsg4326,
        indexed sortOption: RTreeSortOption? = nil,
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) {
        self.init(
            mvtData: data,
            x: tile.x,
            y: tile.y,
            z: tile.z,
            projection: projection,
            indexed: sortOption,
            layerAllowlist: layerAllowlist,
            logger: logger)
    }

    /// Create a vector tile by reading it from `url`, which must be in MVT format, at `z`/`x`/`y`.
    public init?(
        contentsOfMVT url: URL,
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
            mvtData: data,
            x: x,
            y: y,
            z: z,
            projection: projection,
            indexed: sortOption,
            layerAllowlist: layerAllowlist,
            logger: logger)
    }

    /// Create a vector tile by reading it from `url`, which must be in MVT format, at some tile coordinate.
    public init?(
        contentsOfMVT url: URL,
        tile: MapTile,
        projection: Projection = .epsg4326,
        indexed sortOption: RTreeSortOption? = nil,
        layerAllowlist: [String]? = nil,
        logger: Logger? = nil
    ) {
        self.init(
            contentsOfMVT: url,
            x: tile.x,
            y: tile.y,
            z: tile.z,
            projection: projection,
            indexed: sortOption,
            layerAllowlist: layerAllowlist,
            logger: logger)
    }

    // MARK: - Export

    /// Returns the tile's content as MVT data.
    public func mvtData(options: ExportOptions? = nil) -> Data? {
        MVTEncoder.encode(
            layers: layers,
            x: x,
            y: y,
            z: z,
            projection: projection,
            options: options ?? ExportOptions())
    }

    /// Writes the tile's content to `url` in MVT format.
    @discardableResult
    public func writeMVT(to url: URL, options: ExportOptions? = nil) -> Bool {
        guard let data: Data = mvtData(options: options) else { return false }

        do {
            try data.write(to: url)
            return true
        }
        catch {
            return false
        }
    }

}
