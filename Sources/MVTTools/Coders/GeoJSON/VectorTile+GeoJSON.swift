#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
import Gzip
import Logging

extension VectorTile {

    // MARK: - Import

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

    // MARK: - Export

    /// Export the tile's content as a GeoJSON `Data` value.
    ///
    /// - Parameter layerNames: When non-empty, only features from the named layers are exported.
    ///   An empty array means all layers.
    /// - Parameter additionalFeatureProperties: A dictionary of extra properties to merge into every exported feature.
    /// - Parameter prettyPrinted: When `true`, the resulting JSON is human-readable with line breaks and indentation.
    /// - Parameter layerProperty: An optional property name used to assign features to layers.
    ///       Defaults to `VectorTile.defaultLayerPropertyName`.
    /// - Parameter options: Export options controlling clipping, simplification, and compression.
    /// - Returns: The GeoJSON data, or `nil` if serialization fails.
    public func toGeoJson(
        layerNames: [String] = [],
        additionalFeatureProperties: [String: Sendable]? = nil,
        prettyPrinted: Bool = false,
        layerProperty: String? = VectorTile.defaultLayerPropertyName,
        options: VectorTile.ExportOptions? = nil
    ) -> Data? {
        var allFeatures: [Feature] = []

        for (layerName, layerContainer) in layers {
            if layerNames.isNotEmpty, !layerNames.contains(layerName) { continue }

            let layerFeatures = processFeatures(layerContainer.features, options: options)

            for feature in layerFeatures {
                var feature = feature
                if let layerProperty {
                    feature.setProperty(layerName, for: layerProperty)
                }
                if let additionalFeatureProperties {
                    feature.properties.merge(additionalFeatureProperties, uniquingKeysWith: { (current, _) in current })
                }
                allFeatures.append(feature)
            }
        }

        let json = FeatureCollection(allFeatures).asJson

        var jsonOptions: JSONSerialization.WritingOptions = []
        if prettyPrinted {
            jsonOptions.insert(.prettyPrinted)
        }

        let serializedData = try? JSONSerialization.data(withJSONObject: json, options: jsonOptions)

        if let options,
           options.compression != .no,
           let serializedData
        {
            var value = 6 // default
            if case let .level(compressionLevel) = options.compression {
                value = max(0, min(9, compressionLevel))
            }
            let level = CompressionLevel(rawValue: Int32(value))
            return (try? serializedData.gzipped(level: level)) ?? serializedData
        }
        else {
            return serializedData
        }
    }

    /// Write the tile's content as GeoJSON to a file URL.
    ///
    /// - Parameter url: The destination file URL.
    /// - Parameter layerNames: When non-empty, only features from the named layers are exported.
    ///   An empty array means all layers.
    /// - Parameter additionalFeatureProperties: A dictionary of extra properties to merge into every exported feature.
    /// - Parameter prettyPrinted: When `true`, the resulting JSON is human-readable with line breaks and indentation.
    /// - Parameter layerProperty: An optional property name used to assign features to layers.
    ///       Defaults to `VectorTile.defaultLayerPropertyName`.
    /// - Parameter options: Export options controlling clipping, simplification, and compression.
    /// - Returns: `true` when the file was written successfully, `false` otherwise.
    @discardableResult
    public func writeGeoJson(
        to url: URL,
        layerNames: [String] = [],
        additionalFeatureProperties: [String: Sendable]? = nil,
        prettyPrinted: Bool = false,
        layerProperty: String? = VectorTile.defaultLayerPropertyName,
        options: VectorTile.ExportOptions? = nil
    ) -> Bool {
        guard let data: Data = toGeoJson(
            layerNames: layerNames,
            additionalFeatureProperties: additionalFeatureProperties,
            prettyPrinted: prettyPrinted,
            layerProperty: layerProperty,
            options: options)
        else { return false }

        do {
            try data.write(to: url)
        }
        catch {
            return false
        }

        return true
    }

}
