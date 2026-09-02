#if EnableShapefile
import Foundation
import GISTools
import GISToolsShapefile
import Logging

extension VectorTile {

    // MARK: - Import

    /// Create a vector tile from a Shapefile.
    ///
    /// The tile's coordinates are automatically derived from the shapefile's bounding box.
    /// The shapefile's projection is read from its `.prj` file (defaults to `.epsg4326`).
    ///
    /// - Parameters:
    ///   - shapefile: The base URL of the shapefile (may include `.shp` extension).
    ///   - layerName: The target layer name. When `nil`, the shapefile's filename is used.
    ///   - sortOption: An optional R-Tree sort option for spatial indexing.
    ///   - logger: An optional logger instance.
    /// - Throws: ``VectorTileError/parseFailed``,
    ///   ``VectorTileError/invalidCoordinate``, or
    ///   ``VectorTileError/coordinateOutOfBounds``.
    public init(
        shapefile url: URL,
        layerName: String? = nil,
        indexed sortOption: RTreeSortOption? = nil,
        logger: Logger? = nil
    ) throws {
        guard let featureCollection = FeatureCollection(
            shapefile: url,
            calculateBoundingBox: true)
        else {
            throw VectorTileError.parseFailed(
                format: "Shapefile",
                reason: "unable to read or parse shapefile at \(url.path)")
        }

        guard let fcBoundingBox = featureCollection.calculateBoundingBox() else {
            throw VectorTileError.parseFailed(
                format: "Shapefile",
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

        self.projection = featureCollection.projection
        self.boundingBox = tile.boundingBox(projection: projection)
        self.logger = logger

        self.layers = [:]
        self.layerNames = []
        self.origin = .shapefile

        let name = layerName ?? url
            .deletingPathExtension()
            .lastPathComponent
        setFeatures(featureCollection.features, for: name)

        if let sortOption {
            createIndex(sortOption: sortOption)
        }
    }

    // MARK: - Export

    /// Write a single layer as a Shapefile.
    ///
    /// - Parameters:
    ///   - url: The output base URL (extension `.shp`, `.dbf`, `.prj` are added).
    ///   - layerName: When non-nil, only this layer is exported. When `nil`, all layers are merged.
    ///   - encoding: The string encoding for the DBF file (default `.utf8`).
    ///   - options: Export options controlling simplification.
    /// - Throws: ``ShapefileError/mixedGeometry`` if the exported features have mixed geometry types.
    public func writeShapefile(
        to url: URL,
        layerName: String? = nil,
        encoding: String.Encoding = .utf8,
        options: VectorTile.ExportOptions? = nil
    ) throws {
        let features: [Feature]
        if let layerName {
            features = self.features(for: layerName)
        }
        else {
            features = layers.values.flatMap(\.features)
        }

        guard features.isNotEmpty else { return }

        let processed = processFeatures(features, options: options)
        let geometryTypes = Set(processed.map(\.geometry.type))
        guard geometryTypes.count == 1 else {
            throw ShapefileError.mixedGeometry(types: geometryTypes)
        }

        let fc = FeatureCollection(processed)
        try ShapefileCoder.write(fc, to: url, encoding: encoding)
    }

    /// Write each layer as a separate Shapefile into a directory.
    ///
    /// - Parameters:
    ///   - directory: The output directory. One `.shp`/`.dbf`/`.prj` set per layer.
    ///   - encoding: The string encoding for DBF files (default `.utf8`).
    ///   - options: Export options controlling simplification.
    /// - Throws: ``ShapefileError`` or file I/O errors.
    public func writeShapefiles(
        to directory: URL,
        encoding: String.Encoding = .utf8,
        options: VectorTile.ExportOptions? = nil
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for layerName in layerNames {
            let features = self.features(for: layerName)
            guard features.isNotEmpty else { continue }

            let processed = processFeatures(features, options: options)
            let fc = FeatureCollection(processed)
            let fileUrl = directory.appendingPathComponent(layerName)
            try ShapefileCoder.write(fc, to: fileUrl, encoding: encoding)
        }
    }

}

/// Errors thrown by Shapefile export from VectorTile.
public enum ShapefileError: Error, Equatable {

    /// The exported features have mixed geometry types (shapefiles only support one type per file).
    case mixedGeometry(types: Set<GeoJsonType>)

}
#endif
