import CMLT
import Foundation
import GISTools
import Gzip
import Logging

/// Errors thrown by MLT decoding.
enum MLTDecoderError: Error {
    case decodeFailed
}

/// Decodes MapLibre Tile (MLT) binary data into GISTools ``Feature`` objects
/// grouped by layer name.
enum MLTDecoder {

    /// Decode MLT data into a dictionary of layer names to ``VectorTile.LayerContainer`` values.
    ///
    /// Automatically decompresses gzipped input before decoding. The raw tile-extent
    /// coordinates are projected to the target projection using the given tile
    /// coordinates and tile extent.
    ///
    /// - Parameters:
    ///   - data: Raw MLT binary data, optionally gzip-compressed.
    ///   - x: The tile column index.
    ///   - y: The tile row index.
    ///   - z: The tile zoom level.
    ///   - projection: The target projection for the decoded coordinates.
    ///   - layerAllowlist: An optional set of layer names to include; `nil` includes all layers.
    ///   - calculateBoundingBox: When `true`, calculate a bounding box for each feature.
    ///   - logger: An optional logger for diagnostic messages.
    /// - Returns: A dictionary keyed by layer name, each value a ``VectorTile.LayerContainer``.
    /// - Throws: ``MLTDecoderError/decodeFailed`` if the data is not valid MLT.
    static func decode(
        from mltData: Data,
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        layerAllowlist: Set<String>? = nil,
        calculateBoundingBox: Bool = false,
        logger: Logger? = nil
    ) throws -> [String: VectorTile.LayerContainer] {
        // Auto-decompress gzipped input.
        var mltData = mltData
        if mltData.isGzipped {
            (logger ?? VectorTile.logger)?.info("\(z)/\(x)/\(y): MLT input data is gzipped")
            mltData = (try? mltData.gunzipped()) ?? mltData
        }

        // Create C++ decoder and decode the tile.
        let cxxDecoder = mlt_decoder_create(true)
        defer { mlt_decoder_destroy(cxxDecoder) }

        let handle = try mltData.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> MLTTileHandle in
            let ptr = buf.bindMemory(to: UInt8.self).baseAddress
            let h = mlt_tile_decode(cxxDecoder, ptr, buf.count)
            guard h != nil else {
                logger?.warning("\(z)/\(x)/\(y): Failed to decode MLT tile data")
                throw MLTDecoderError.decodeFailed
            }
            return h!
        }
        defer { mlt_tile_destroy(handle) }

        // Iterate layers and convert every feature.
        let layerCount = Int(mlt_tile_layer_count(handle))
        var result: [String: VectorTile.LayerContainer] = [:]
        result.reserveCapacity(layerCount)

        for li in 0 ..< layerCount {
            let layerName = String(cString: mlt_tile_layer_name(handle, li))
            guard layerAllowlist?.contains(layerName) ?? true else { continue }

            let featureCount = Int(mlt_tile_layer_feature_count(handle, li))
            let propertyKeys = layerPropertyKeys(handle: handle, layerIndex: li)
            let extent = Int(mlt_tile_layer_extent(handle, li))

            let projectionFunction = Projections.forwardProjection(
                for: projection, x: x, y: y, z: z, extent: extent)
            let toCoordinate: (Double, Double) -> Coordinate3D = { fx, fy in
                projectionFunction(Int(fx), Int(fy))
            }

            var features: [Feature] = []
            features.reserveCapacity(featureCount)

            for fi in 0 ..< featureCount {
                if let feature = convertFeature(
                    handle: handle,
                    layerIndex: li,
                    featureIndex: fi,
                    propertyKeys: propertyKeys,
                    toCoordinatesCallback: toCoordinate,
                    calculateBoundingBox: calculateBoundingBox
                ) {
                    features.append(feature)
                }
            }

            if features.isNotEmpty {
                var layerBoundingBox: BoundingBox?
                let boundingBoxes = features.compactMap(\.boundingBox)
                if boundingBoxes.isNotEmpty {
                    layerBoundingBox = boundingBoxes.reduce(boundingBoxes[0], +)
                }
                result[layerName] = VectorTile.LayerContainer(
                    features: features,
                    boundingBox: layerBoundingBox)
            }
        }

        return result
    }

    // MARK: - Private helpers

    /// Returns all property key strings for a given layer.
    private static func layerPropertyKeys(
        handle: MLTTileHandle,
        layerIndex: Int
    ) -> [String] {
        let count = mlt_layer_property_key_count(handle, layerIndex)
        return (0 ..< Int(count)).compactMap { i in
            mlt_layer_property_key(handle, layerIndex, i)
                .map(String.init(cString:))
        }
    }

    /// Converts one MLT feature (indexed within a layer) to a GISTools ``Feature``.
    private static func convertFeature(
        handle: MLTTileHandle,
        layerIndex: Int,
        featureIndex: Int,
        propertyKeys: [String],
        toCoordinatesCallback: (Double, Double) -> Coordinate3D,
        calculateBoundingBox: Bool
    ) -> Feature? {
        guard let geometry = decodeGeometry(
            handle: handle,
            layerIndex: layerIndex,
            featureIndex: featureIndex,
            toCoordinatesCallback: toCoordinatesCallback
        ) else { return nil }

        // Read typed properties.
        var props: [String: Sendable] = [:]
        for key in propertyKeys {
            if let val = readProperty(
                handle: handle,
                layerIndex: layerIndex,
                featureIndex: featureIndex,
                key: key
            ) {
                props[key] = val
            }
        }

        // Build the feature.
        var feature = Feature(
            geometry,
            properties: props,
            calculateBoundingBox: calculateBoundingBox)
        let hasID = mlt_feature_has_id(handle, layerIndex, featureIndex)
        if hasID {
            let fid = mlt_feature_id(handle, layerIndex, featureIndex)
            feature.id = Feature.Identifier.uint(UInt(fid))
        }
        return feature
    }

    /// Attempts to read a property value by key, trying string → int → double → bool.
    private static func readProperty(
        handle: MLTTileHandle,
        layerIndex: Int,
        featureIndex: Int,
        key: String
    ) -> Sendable? {
        var found: Bool = false

        // Try string.
        let strPtr = mlt_feature_property_string(
            handle, layerIndex, featureIndex, key, &found)
        if found {
            let val = String(cString: strPtr!)
            free(UnsafeMutablePointer(mutating: strPtr))
            return val
        }

        // Try int.
        let intVal = mlt_feature_property_int(
            handle, layerIndex, featureIndex, key, &found)
        if found { return intVal }

        // Try double.
        let dblVal = mlt_feature_property_double(
            handle, layerIndex, featureIndex, key, &found)
        if found { return dblVal }

        // Try bool.
        let boolVal = mlt_feature_property_bool(
            handle, layerIndex, featureIndex, key, &found)
        if found { return boolVal }

        return nil
    }

    /// Converts MLT geometry to a GISTools geometry object.
    private static func decodeGeometry(
        handle: MLTTileHandle,
        layerIndex: Int,
        featureIndex: Int,
        toCoordinatesCallback: (Double, Double) -> Coordinate3D
    ) -> GeoJsonGeometry? {
        let gt = Int(mlt_feature_geometry_type(handle, layerIndex, featureIndex))

        // Point / MultiPoint / LineString — flat coordinate list.
        if gt == kMLTGeometryPoint
            || gt == kMLTGeometryMultiPoint
            || gt == kMLTGeometryLineString
        {
            let coordCount = mlt_feature_coordinate_count(
                handle, layerIndex, featureIndex)
            guard coordCount > 0 else { return nil }

            var xs = [Float](repeating: 0, count: coordCount)
            var ys = [Float](repeating: 0, count: coordCount)
            let written = mlt_feature_coordinates(
                handle, layerIndex, featureIndex, &xs, &ys, coordCount)
            guard written == coordCount else { return nil }

            let coordinates3D: [Coordinate3D] = zip(xs, ys).map {
                toCoordinatesCallback(Double($0), Double($1))
            }

            switch gt {
            case kMLTGeometryPoint:
                guard let pt = coordinates3D.first else { return nil }
                return Point(pt)
            case kMLTGeometryMultiPoint:
                return MultiPoint(coordinates3D)
            case kMLTGeometryLineString:
                return LineString(coordinates3D)
            default:
                return nil
            }
        }

        // MultiLineString — decode as individual lines via ring API.
        if gt == kMLTGeometryMultiLineString {
            let ringCount = mlt_feature_ring_count(
                handle, layerIndex, featureIndex)
            if ringCount > 0 {
                var lines: [LineString] = []
                for ri in 0 ..< ringCount {
                    let size = mlt_feature_ring_size(
                        handle, layerIndex, featureIndex, ri)
                    if size < 2 { continue }
                    var xs = [Float](repeating: 0, count: size)
                    var ys = [Float](repeating: 0, count: size)
                    let written = mlt_feature_ring_coordinates(
                        handle, layerIndex, featureIndex, ri, &xs, &ys, size)
                    guard written == size else { continue }
                    let coords = zip(xs, ys).map {
                        toCoordinatesCallback(Double($0), Double($1))
                    }
                    if let ls = LineString(coords) { lines.append(ls) }
                }
                if lines.count == 1 { return lines[0] }
                return MultiLineString(lines.map { $0.coordinates })
            }
            // Fallback: flat coordinate list.
            let coordCount = mlt_feature_coordinate_count(
                handle, layerIndex, featureIndex)
            guard coordCount > 0 else { return nil }
            var xs = [Float](repeating: 0, count: coordCount)
            var ys = [Float](repeating: 0, count: coordCount)
            let written = mlt_feature_coordinates(
                handle, layerIndex, featureIndex, &xs, &ys, coordCount)
            guard written == coordCount else { return nil }
            let coords = zip(xs, ys).map {
                toCoordinatesCallback(Double($0), Double($1))
            }
            return LineString(coords)
        }

        // Polygon / MultiPolygon — ring-based with closure detection.
        if gt == kMLTGeometryPolygon || gt == kMLTGeometryMultiPolygon {
            let ringCount = mlt_feature_ring_count(
                handle, layerIndex, featureIndex)
            guard ringCount > 0 else { return nil }

            // MLT may omit the closing vertex — add it if missing.
            func closeRing(_ coordinates: [Coordinate3D]) -> [Coordinate3D] {
                guard coordinates.count > 1,
                      coordinates.first != coordinates.last
                else { return coordinates }
                return coordinates + [coordinates[0]]
            }

            /// Read ring at global index `ri`, return its coordinates or nil.
            func readRing(_ ri: Int) -> [Coordinate3D]? {
                let size = mlt_feature_ring_size(
                    handle, layerIndex, featureIndex, ri)
                guard size >= 3 else { return nil }
                var xs = [Float](repeating: 0, count: size)
                var ys = [Float](repeating: 0, count: size)
                let written = mlt_feature_ring_coordinates(
                    handle, layerIndex, featureIndex, ri, &xs, &ys, size)
                guard written == size else { return nil }
                return closeRing(zip(xs, ys).map {
                    toCoordinatesCallback(Double($0), Double($1))
                })
            }

            if gt == kMLTGeometryMultiPolygon {
                // Build a MultiPolygon by grouping rings per polygon.
                let polygonCount = Int(mlt_feature_polygon_count(
                    handle, layerIndex, featureIndex))
                var polygons: [[[Coordinate3D]]] = []
                var ringIndex = 0
                for pi in 0 ..< polygonCount {
                    let nRings = Int(mlt_feature_polygon_ring_count(
                        handle, layerIndex, featureIndex, pi))
                    var rings: [[Coordinate3D]] = []
                    for _ in 0 ..< nRings {
                        if ringIndex < ringCount, let coordinates = readRing(ringIndex) {
                            rings.append(coordinates)
                        }
                        ringIndex += 1
                    }
                    if rings.isNotEmpty { polygons.append(rings) }
                }
                guard polygons.isNotEmpty else { return nil }
                return MultiPolygon(polygons)
            }
            else {
                // Polygon: all rings form a single polygon.
                var rings: [[Coordinate3D]] = []
                for ri in 0 ..< ringCount {
                    if let coords = readRing(ri) {
                        rings.append(coords)
                    }
                }
                guard rings.isNotEmpty else { return nil }
                return Polygon(rings)
            }
        }

        return nil
    }

}
