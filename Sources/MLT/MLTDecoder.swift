import CMLT
import Foundation
import GISTools
import Gzip
import Logging

/// Errors thrown by MLT decoding.
public enum MLTDecoderError: Error {
    case decodeFailed
}

/// Decodes MapLibre Tile (MLT) binary data into GISTools ``Feature`` objects
/// grouped by layer name.
public enum MLTDecoder {

    /// Decode MLT data into a dictionary of layer names to GISTools ``Feature`` arrays.
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
    /// - Returns: A dictionary keyed by layer name, each value an array of ``Feature`` objects.
    /// - Throws: ``MLTDecoderError/decodeFailed`` if the data is not valid MLT.
    public static func decode(
        from data: Data,
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        layerAllowlist: Set<String>? = nil,
        calculateBoundingBox: Bool = false,
        logger: Logger? = nil
    ) throws -> [String: [Feature]] {
        // Auto-decompress gzipped input.
        var mvtData = data
        if mvtData.isGzipped {
            logger?.info("MLTDecoder: Input data is gzipped, decompressing")
            mvtData = (try? mvtData.gunzipped()) ?? mvtData
        }

        // Create C++ decoder and decode the tile.
        let cxxDecoder = mlt_decoder_create(true)
        defer { mlt_decoder_destroy(cxxDecoder) }

        let handle = try mvtData.withUnsafeBytes {
            (buf: UnsafeRawBufferPointer) -> MLTTileHandle in
            let ptr = buf.bindMemory(to: UInt8.self).baseAddress
            let h = mlt_tile_decode(cxxDecoder, ptr, buf.count)
            guard h != nil else {
                logger?.warning("MLTDecoder: Failed to decode tile data")
                throw MLTDecoderError.decodeFailed
            }
            return h!
        }
        defer { mlt_tile_destroy(handle) }

        // Iterate layers and convert every feature.
        let layerCount = Int(mlt_tile_layer_count(handle))
        var result: [String: [Feature]] = [:]
        result.reserveCapacity(layerCount)

        for li in 0 ..< layerCount {
            let layerName = String(cString: mlt_tile_layer_name(handle, li))
            guard layerAllowlist?.contains(layerName) ?? true else { continue }
            let featureCount = Int(mlt_tile_layer_feature_count(handle, li))
            let propertyKeys = layerPropertyKeys(handle: handle, layerIndex: li)
            let extent = Int(mlt_tile_layer_extent(handle, li))

            let projectFn = forwardProjection(
                for: projection,
                x: x, y: y, z: z,
                extent: extent)
            let toCoord: (Double, Double) -> Coordinate3D = { fx, fy in
                projectFn(Int(fx), Int(fy))
            }

            var features: [Feature] = []
            features.reserveCapacity(featureCount)

            for fi in 0 ..< featureCount {
                if let feature = convertFeature(
                    handle: handle,
                    layerIndex: li,
                    featureIndex: fi,
                    propertyKeys: propertyKeys,
                    toCoord: toCoord,
                    calculateBoundingBox: calculateBoundingBox
                ) {
                    features.append(feature)
                }
            }

            if !features.isEmpty {
                result[layerName] = features
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
        toCoord: (Double, Double) -> Coordinate3D,
        calculateBoundingBox: Bool
    ) -> Feature? {
        guard let geometry = decodeGeometry(
            handle: handle,
            layerIndex: layerIndex,
            featureIndex: featureIndex,
            toCoord: toCoord
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
        toCoord: (Double, Double) -> Coordinate3D
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

            let coords3D: [Coordinate3D] = zip(xs, ys).map {
                toCoord(Double($0), Double($1))
            }

            switch gt {
            case kMLTGeometryPoint:
                guard let pt = coords3D.first else { return nil }
                return Point(pt)
            case kMLTGeometryMultiPoint:
                return MultiPoint(coords3D)
            case kMLTGeometryLineString:
                return LineString(coords3D)
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
                        toCoord(Double($0), Double($1))
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
                toCoord(Double($0), Double($1))
            }
            return LineString(coords)
        }

        // Polygon / MultiPolygon — ring-based with closure detection.
        if gt == kMLTGeometryPolygon || gt == kMLTGeometryMultiPolygon {
            let ringCount = mlt_feature_ring_count(
                handle, layerIndex, featureIndex)
            guard ringCount > 0 else { return nil }

            // MLT may omit the closing vertex — add it if missing.
            func closeRing(_ coords: [Coordinate3D]) -> [Coordinate3D] {
                guard coords.count > 1,
                      coords.first != coords.last
                else { return coords }
                return coords + [coords[0]]
            }

            var rings: [[Coordinate3D]] = []
            for ri in 0 ..< ringCount {
                let size = mlt_feature_ring_size(
                    handle, layerIndex, featureIndex, ri)
                if size < 3 { continue }
                var xs = [Float](repeating: 0, count: size)
                var ys = [Float](repeating: 0, count: size)
                let written = mlt_feature_ring_coordinates(
                    handle, layerIndex, featureIndex, ri, &xs, &ys, size)
                guard written == size else { continue }
                let coords = zip(xs, ys).map {
                    toCoord(Double($0), Double($1))
                }
                rings.append(closeRing(coords))
            }
            guard rings.isEmpty == false else { return nil }
            return Polygon(rings)
        }

        return nil
    }

}
