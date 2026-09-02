#if EnableGeoPackage
import Foundation
import GISTools
import GISToolsGeoPackage
import Logging

extension VectorTile {

    // MARK: - Import

    /// Create a vector tile from a GeoPackage file.
    ///
    /// The tile's coordinates are automatically derived from the GeoPackage's bounding box.
    /// When features carry a `"gpkg_layer"` property (added by a previous merged export),
    /// they are split into separate layers accordingly and the property is stripped.
    ///
    /// - Parameters:
    ///   - geopackage: The file URL of the GeoPackage database.
    ///   - table: When non-nil, only this feature table is loaded into a single layer.
    ///     When `nil`, all feature tables are loaded, each as a separate layer.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing.
    ///   - logger: An optional logger instance.
    /// - Throws: ``GeoPackageError`` if the file cannot be read.
    public init(
        geopackage url: URL,
        table: String? = nil,
        indexed sortOption: RTreeSortOption? = nil,
        logger: Logger? = nil
    ) async throws {
        let conn = try GeoPackageConnection(url: url)

        let tile: MapTile
        let entries: [(name: String, fc: FeatureCollection)]

        if let table {
            let fc = try await FeatureCollection(geopackage: url, table: table)
            guard let box = fc.calculateBoundingBox() else {
                await conn.close()
                throw GeoPackageError.invalidGeoPackage(detail: "Empty feature collection")
            }
            tile = MapTile(boundingBox: box)
            entries = [(table, fc)]
        }
        else {
            let contents = try await conn.readContents()
            var combinedBox: BoundingBox?
            var result: [(name: String, fc: FeatureCollection)] = []

            for entry in contents where entry.dataType == "features" {
                let features = try await conn.readFeatures(table: entry.tableName)
                let fc = FeatureCollection(features)
                guard fc.features.isNotEmpty else { continue }
                if let box = fc.calculateBoundingBox() {
                    combinedBox = combinedBox.map { $0 + box } ?? box
                }
                result.append((entry.tableName, fc))
            }

            guard result.isNotEmpty else {
                await conn.close()
                throw GeoPackageError.invalidGeoPackage(detail: "No feature tables found in GeoPackage")
            }

            tile = MapTile(boundingBox: combinedBox ?? .world)
            entries = result
        }

        self.x = tile.x
        self.y = tile.y
        self.z = tile.z
        self.projection = .epsg4326
        self.boundingBox = tile.boundingBox(projection: projection)
        self.logger = logger
        self.layers = [:]
        self.layerNames = []
        self.origin = .geopackage

        for (name, fc) in entries {
            distributeFeatures(fc, defaultLayer: name)
        }
        if let sortOption { createIndex(sortOption: sortOption) }

        await conn.close()
    }

    // MARK: - Export

    /// Write the tile's content to a GeoPackage file.
    ///
    /// - Parameters:
    ///   - url: The output file URL (must end in `.gpkg`).
    ///   - table: When non-nil, all features are merged into this single table
    ///     with a `"gpkg_layer"` property to preserve layer information.
    ///     When `nil`, one table per layer is created.
    ///   - createSpatialIndex: Whether to create a spatial (rtree) index.
    ///   - options: Export options controlling simplification.
    /// - Throws: ``GeoPackageError`` or file I/O errors.
    public func writeGeoPackage(
        to url: URL,
        table: String? = nil,
        createSpatialIndex: Bool = false,
        options: VectorTile.ExportOptions? = nil
    ) async throws {
        let conn = try GeoPackageConnection(url: url, skipValidation: true)
        try await conn.createMetadata()

        if let table {
            var allFeatures: [Feature] = []
            for layerName in layerNames {
                let features = processFeatures(self.features(for: layerName), options: options)
                allFeatures.append(contentsOf: features.map { feature in
                    var f = feature
                    f.properties["gpkg_layer"] = layerName
                    return f
                })
            }
            guard allFeatures.isNotEmpty else { return }
            let fc = FeatureCollection(allFeatures)
            try await conn.write(features: fc, to: table, createSpatialIndex: createSpatialIndex)
        }
        else {
            for layerName in layerNames {
                let features = processFeatures(self.features(for: layerName), options: options)
                guard features.isNotEmpty else { continue }
                let tagged = features.map { feature -> Feature in
                    var f = feature
                    f.properties["gpkg_layer"] = layerName
                    return f
                }
                let fc = FeatureCollection(tagged)
                try await conn.write(features: fc, to: layerName, createSpatialIndex: createSpatialIndex)
            }
        }

        await conn.close()
    }

    // MARK: - Private helpers

    /// Distribute features into layers, splitting by `"gpkg_layer"` if present.
    private mutating func distributeFeatures(_ fc: FeatureCollection, defaultLayer: String) {
        let hasGpkgLayer = fc.features.contains { $0.properties["gpkg_layer"] != nil }
        guard hasGpkgLayer else {
            setFeatures(fc.features, for: defaultLayer)
            return
        }
        var groups: [String: [Feature]] = [:]
        for var feature in fc.features {
            let layer = feature.properties.removeValue(forKey: "gpkg_layer") as? String ?? defaultLayer
            groups[layer, default: []].append(feature)
        }
        for (layer, features) in groups {
            setFeatures(features, for: layer)
        }
    }

}
#endif
