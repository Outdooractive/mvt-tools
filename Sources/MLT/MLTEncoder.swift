import CMLT
import Foundation
import GISTools

/// Errors thrown by MLT encoding.
public enum MLTEncoderError: Error {
    case encodeFailed
    case unsupportedGeometry
}

/// Encodes GISTools features into the MapLibre Tile (MLT) binary format.
public enum MLTEncoder {

    /// Encodes a set of layers (name → features) into MLT binary data.
    /// - Parameters:
    ///   - layers: Each element is a layer name, tile extent (typically 4096),
    ///     and an array of GISTools ``Feature`` objects.
    ///   - x: The tile column index.
    ///   - y: The tile row index.
    ///   - z: The tile zoom level.
    ///   - projection: The source projection of the input coordinates (default: ``Projection/epsg4326``).
    /// - Returns: The encoded MLT binary data.
    /// - Throws: ``MLTEncoderError/encodeFailed`` if encoding fails,
    ///   ``MLTEncoderError/unsupportedGeometry`` if a feature has an unsupported geometry type.
    public static func encode(
        layers: [(name: String, extent: UInt32, features: [Feature])],
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326
    ) throws -> Data {
        let encoder = mlt_encoder_create()
        defer { mlt_encoder_destroy(encoder) }

        for (layerName, extent, features) in layers {
            mlt_encoder_begin_layer(encoder, layerName, extent)

            // Build the inverse projection for this layer's extent.
            let projectFn = inverseProjection(
                for: projection,
                x: x, y: y, z: z,
                extent: Int(extent))

            for feature in features {
                // MLT only supports numeric IDs; skip non-integer IDs.
                let numericId = feature.id?.uint64Value
                let hasId = numericId != nil
                let featureId = numericId ?? 0

                // Project coordinates from geographic space to tile-extent space,
                // then flatten to float arrays.
                let coords = feature.geometry.allCoordinates.map(projectFn)
                var xs = coords.map { Float($0.0) }
                var ys = coords.map { Float($0.1) }

                // Map GISTools geometry type → MLT constant.
                let geomType: Int32
                switch feature.geometry.type {
                case .point:             geomType = Int32(kMLTGeometryPoint)
                case .multiPoint:        geomType = Int32(kMLTGeometryMultiPoint)
                case .lineString:        geomType = Int32(kMLTGeometryLineString)
                case .multiLineString:   geomType = Int32(kMLTGeometryMultiLineString)
                case .polygon:           geomType = Int32(kMLTGeometryPolygon)
                case .multiPolygon:      geomType = Int32(kMLTGeometryMultiPolygon)
                default:                 throw MLTEncoderError.unsupportedGeometry
                }

                // Build typed property list.
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
                        // Fallback: stringify unknown types.
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
                        if let k = prop.key {
                            free(UnsafeMutablePointer(mutating: k))
                        }
                        if let v = prop.value {
                            free(UnsafeMutablePointer(mutating: v))
                        }
                    }
                }

                mlt_encoder_add_feature(
                    encoder, featureId, hasId,
                    geomType,
                    &xs, &ys, xs.count,
                    &mltProps, mltProps.count)
            }
        }

        // Finalize and return the encoded data.
        var outLength: Int = 0
        guard let buffer = mlt_encoder_finish(encoder, &outLength) else {
            throw MLTEncoderError.encodeFailed
        }
        defer { mlt_buffer_free(buffer) }

        return Data(bytes: buffer, count: outLength)
    }

}
