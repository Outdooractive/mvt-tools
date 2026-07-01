import CMLT
import Foundation
import GISTools

/// Errors thrown by MLT operations.
public enum MLTError: Error {
    case decodeFailed
    case encodeFailed
    case unsupportedGeometry
}

/// A decoded MapLibre Tile (MLT), wrapping the C++ decoder via C bridge.
public final class MLTTile {

    let handle: MLTTileHandle

    private init(handle: MLTTileHandle) {
        self.handle = handle
    }

    deinit {
        mlt_tile_destroy(handle)
    }

    /// Decode an MLT tile from raw data.
    public static func decode(from data: Data) throws -> MLTTile {
        let decoder = mlt_decoder_create(true)
        defer { mlt_decoder_destroy(decoder) }

        let handle = try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> MLTTileHandle in
            let ptr = buf.bindMemory(to: UInt8.self).baseAddress
            let h = mlt_tile_decode(decoder, ptr, buf.count)
            guard h != nil else { throw MLTError.decodeFailed }
            return h!
        }

        return MLTTile(handle: handle)
    }

    /// The number of layers in this tile.
    public var layerCount: Int {
        Int(mlt_tile_layer_count(handle))
    }

    /// Returns the layer at the given index.
    public func layer(at index: Int) -> MLTLayer {
        MLTLayer(tile: self, index: index)
    }

    /// All layers in this tile.
    public var layers: [MLTLayer] {
        (0 ..< layerCount).map { MLTLayer(tile: self, index: $0) }
    }

}

/// A layer within an MLT tile.
public struct MLTLayer {

    /// The tile that owns this layer.
    public let tile: MLTTile
    /// The index of this layer within the tile.
    public let index: Int

    /// The layer name.
    public var name: String {
        String(cString: mlt_tile_layer_name(tile.handle, index))
    }

    /// The tile extent (typically 4096).
    public var extent: UInt32 {
        mlt_tile_layer_extent(tile.handle, index)
    }

    /// The number of features in this layer.
    public var featureCount: Int {
        Int(mlt_tile_layer_feature_count(tile.handle, index))
    }

    /// Returns the feature at the given index.
    public func feature(at index: Int) -> MLTFeature {
        MLTFeature(layer: self, index: index)
    }

    /// All features in this layer.
    public var features: [MLTFeature] {
        (0 ..< featureCount).map { MLTFeature(layer: self, index: $0) }
    }

    /// The property keys for this layer.
    public var propertyKeys: [String] {
        let count = mlt_layer_property_key_count(tile.handle, index)
        return (0 ..< Int(count)).compactMap { i in
            mlt_layer_property_key(tile.handle, index, i).map(String.init(cString:))
        }
    }

}

/// A feature within an MLT layer.
public struct MLTFeature {

    /// The layer that owns this feature.
    public let layer: MLTLayer
    /// The index of this feature within the layer.
    public let index: Int

    /// Whether this feature has an ID.
    public var hasID: Bool {
        mlt_feature_has_id(layer.tile.handle, layer.index, index)
    }

    /// The feature ID, or 0 if none.
    public var featureID: UInt64 {
        mlt_feature_id(layer.tile.handle, layer.index, index)
    }

    /// The MLT geometry type.
    public var geometryType: Int32 {
        mlt_feature_geometry_type(layer.tile.handle, layer.index, index)
    }

    /// Returns the feature's GISTools geometry, or nil if conversion fails.
    public func toGISToolsGeometry() -> GeoJsonGeometry? {
        let gt = Int(geometryType)

        // Point / MultiPoint / LineString: use flat coordinate access
        if gt == kMLTGeometryPoint || gt == kMLTGeometryMultiPoint || gt == kMLTGeometryLineString {
            let coordCount = mlt_feature_coordinate_count(layer.tile.handle, layer.index, index)
            guard coordCount > 0 else { return nil }

            var xs = [Float](repeating: 0, count: coordCount)
            var ys = [Float](repeating: 0, count: coordCount)
            let written = mlt_feature_coordinates(layer.tile.handle, layer.index, index, &xs, &ys, coordCount)
            guard written == coordCount else { return nil }

            let coords3D: [Coordinate3D] = zip(xs, ys).map {
                Coordinate3D(x: Double($0), y: Double($1))
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

        // MultiLineString: treat each ring as a line
        if gt == kMLTGeometryMultiLineString {
            let ringCount = mlt_feature_ring_count(layer.tile.handle, layer.index, index)
            if ringCount > 0 {
                var lines: [LineString] = []
                for ri in 0 ..< ringCount {
                    let size = mlt_feature_ring_size(layer.tile.handle, layer.index, index, ri)
                    if size < 2 { continue }
                    var xs = [Float](repeating: 0, count: size)
                    var ys = [Float](repeating: 0, count: size)
                    let written = mlt_feature_ring_coordinates(layer.tile.handle, layer.index, index, ri, &xs, &ys, size)
                    guard written == size else { continue }
                    let coords = zip(xs, ys).map { Coordinate3D(x: Double($0), y: Double($1)) }
                    if let ls = LineString(coords) { lines.append(ls) }
                }
                if lines.count == 1 { return lines[0] }
                return MultiLineString(lines.map { $0.coordinates })
            }
            // Fallback: flat coordinate list
            let coordCount = mlt_feature_coordinate_count(layer.tile.handle, layer.index, index)
            guard coordCount > 0 else { return nil }
            var xs = [Float](repeating: 0, count: coordCount)
            var ys = [Float](repeating: 0, count: coordCount)
            let written = mlt_feature_coordinates(layer.tile.handle, layer.index, index, &xs, &ys, coordCount)
            guard written == coordCount else { return nil }
            let coords = zip(xs, ys).map { Coordinate3D(x: Double($0), y: Double($1)) }
            return LineString(coords)
        }

        // Polygon / MultiPolygon: use ring API
        if gt == kMLTGeometryPolygon || gt == kMLTGeometryMultiPolygon {
            let ringCount = mlt_feature_ring_count(layer.tile.handle, layer.index, index)
            guard ringCount > 0 else { return nil }

            /// Ensures a ring is closed (first == last). MLT rings may omit the closing vertex.
            func closeRing(_ coords: [Coordinate3D]) -> [Coordinate3D] {
                guard coords.count > 1,
                      coords.first != coords.last
                else { return coords }
                return coords + [coords[0]]
            }

            var rings: [[Coordinate3D]] = []
            for ri in 0 ..< ringCount {
                let size = mlt_feature_ring_size(layer.tile.handle, layer.index, index, ri)
                if size < 3 { continue }
                var xs = [Float](repeating: 0, count: size)
                var ys = [Float](repeating: 0, count: size)
                let written = mlt_feature_ring_coordinates(layer.tile.handle, layer.index, index, ri, &xs, &ys, size)
                guard written == size else { continue }
                let coords = zip(xs, ys).map { Coordinate3D(x: Double($0), y: Double($1)) }
                rings.append(closeRing(coords))
            }
            guard rings.isEmpty == false else { return nil }
            return Polygon(rings)
        }

        return nil
    }

    /// Read an integer property value.
    public func intProperty(key: String) -> (value: Int64, found: Bool) {
        var found: Bool = false
        let val = mlt_feature_property_int(layer.tile.handle, layer.index, index, key, &found)
        return (val, found)
    }

    /// Read a double property value.
    public func doubleProperty(key: String) -> (value: Double, found: Bool) {
        var found: Bool = false
        let val = mlt_feature_property_double(layer.tile.handle, layer.index, index, key, &found)
        return (val, found)
    }

    /// Read a string property value. The returned string is copied out.
    public func stringProperty(key: String) -> (value: String?, found: Bool) {
        var found: Bool = false
        let ptr = mlt_feature_property_string(layer.tile.handle, layer.index, index, key, &found)
        let val = ptr.map { String(cString: $0) }
        // Free the malloc'd copy from the C bridge
        if let ptr { free(UnsafeMutablePointer(mutating: ptr)) }
        return (val, found)
    }

    /// Read a boolean property value.
    public func boolProperty(key: String) -> (value: Bool, found: Bool) {
        var found: Bool = false
        let val = mlt_feature_property_bool(layer.tile.handle, layer.index, index, key, &found)
        return (val, found)
    }

    /// All property values as a dictionary.
    public func allProperties() -> [String: Any] {
        var result: [String: Any] = [:]
        for key in layer.propertyKeys {
            let (sv, sf) = stringProperty(key: key)
            if sf { result[key] = sv; continue }
            let (iv, ib) = intProperty(key: key)
            if ib { result[key] = iv; continue }
            let (dv, db) = doubleProperty(key: key)
            if db { result[key] = dv; continue }
            let (bv, bb) = boolProperty(key: key)
            if bb { result[key] = bv; continue }
        }
        return result
    }

    /// Convert this feature to a GISTools Feature.
    public func toGISToolsFeature() -> Feature? {
        guard let geometry = toGISToolsGeometry() else { return nil }
        var props: [String: Sendable] = [:]
        for key in layer.propertyKeys {
            let (sv, sf) = stringProperty(key: key)
            if sf { props[key] = sv; continue }
            let (iv, ib) = intProperty(key: key)
            if ib { props[key] = iv; continue }
            let (dv, db) = doubleProperty(key: key)
            if db { props[key] = dv; continue }
            let (bv, bb) = boolProperty(key: key)
            if bb { props[key] = bv; continue }
        }
        var feature = Feature(geometry, properties: props)
        if hasID {
            feature.id = Feature.Identifier.uint(UInt(featureID))
        }
        return feature
    }

}

// MARK: - Encode

extension MLTTile {

    /// Encodes a set of layers (name → features) into MLT binary data.
    public static func encode(layers: [(name: String, extent: UInt32, features: [Feature])]) throws -> Data {
        let encoder = mlt_encoder_create()
        defer { mlt_encoder_destroy(encoder) }

        for (layerName, extent, features) in layers {
            mlt_encoder_begin_layer(encoder, layerName, extent)

            for feature in features {
                // MLT only supports numeric IDs. String and double IDs are skipped.
                let numericId = feature.id?.uint64Value
                let hasId = numericId != nil
                let featureId = numericId ?? 0

                // Extract coordinates as flat float arrays
                let coords = feature.geometry.allCoordinates
                var xs = coords.map { Float($0.x) }
                var ys = coords.map { Float($0.y) }

                let geomType: Int32
                switch feature.geometry.type {
                case .point:             geomType = Int32(kMLTGeometryPoint)
                case .multiPoint:        geomType = Int32(kMLTGeometryMultiPoint)
                case .lineString:        geomType = Int32(kMLTGeometryLineString)
                case .multiLineString:   geomType = Int32(kMLTGeometryMultiLineString)
                case .polygon:           geomType = Int32(kMLTGeometryPolygon)
                case .multiPolygon:      geomType = Int32(kMLTGeometryMultiPolygon)
                default:                 throw MLTError.unsupportedGeometry
                }

                // Build typed property arrays.
                var mltProps: [MLTProperty] = []
                for (key, value) in feature.properties {
                    let (type, strValue): (Int32, String)
                    if value is String {
                        type = Int32(kMLTPropString)
                        strValue = value as! String
                    }
                    else if let i = value as? Int {
                        type = Int32(kMLTPropInt)
                        strValue = String(i)
                    }
                    else if let i = value as? Int64 {
                        type = Int32(kMLTPropInt)
                        strValue = String(i)
                    }
                    else if let u = value as? UInt {
                        type = Int32(kMLTPropUInt)
                        strValue = String(u)
                    }
                    else if let d = value as? Double {
                        type = Int32(kMLTPropDouble)
                        strValue = String(d)
                    }
                    else if let f = value as? Float {
                        type = Int32(kMLTPropFloat)
                        strValue = String(f)
                    }
                    else if let b = value as? Bool {
                        type = Int32(kMLTPropBool)
                        strValue = b ? "true" : "false"
                    }
                    else {
                        type = Int32(kMLTPropString)
                        strValue = String(describing: value)
                    }
                    guard let k = strdup(key), let v = strdup(strValue) else { continue }
                    var prop = MLTProperty()
                    prop.key = UnsafePointer(k)
                    prop.type = type
                    prop.value = UnsafePointer(v)
                    mltProps.append(prop)
                }
                defer {
                    for prop in mltProps {
                        if let k = prop.key { free(UnsafeMutablePointer(mutating: k)) }
                        if let v = prop.value { free(UnsafeMutablePointer(mutating: v)) }
                    }
                }

                mlt_encoder_add_feature(
                    encoder, featureId, hasId,
                    geomType,
                    &xs, &ys, xs.count,
                    &mltProps, mltProps.count)
            }
        }

        var outLength: Int = 0
        guard let buffer = mlt_encoder_finish(encoder, &outLength) else {
            throw MLTError.encodeFailed
        }
        defer { mlt_buffer_free(buffer) }

        return Data(bytes: buffer, count: outLength)
    }

}
