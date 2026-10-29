import Foundation
import GISTools
import Logging
import MLTCore

#if EnableMLT

/// Errors thrown by MLT decoding.
enum MLTDecoderError: Error, Equatable {
    case decodeFailed
    case unsupported(String)
}

/// Decodes MapLibre Tile (MLT) binary data into GISTools `Feature` objects
/// grouped by layer name.
///
/// The actual implementation is selected at compile time:
/// - `EnableMLTCXX` uses the C++ `maplibre-tile-spec` bridge.
/// - `EnableMLT` alone uses the pure Swift implementation.
enum MLTDecoder {

    /// Decode MLT data into a dictionary of layer names to `VectorTile.LayerContainer` values.
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
    /// - Returns: A dictionary keyed by layer name, each value a `VectorTile.LayerContainer`.
    /// - Throws: `MLTDecoderError.decodeFailed` if the data is not valid MLT.
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
        #if EnableMLTCXX
        return try MLTDecoderCXX.decode(
            from: mltData,
            x: x,
            y: y,
            z: z,
            projection: projection,
            layerAllowlist: layerAllowlist,
            calculateBoundingBox: calculateBoundingBox,
            logger: logger)
        #else
        do {
            return try MLTDecoderSwift.decode(
                from: mltData,
                x: x,
                y: y,
                z: z,
                projection: projection,
                layerAllowlist: layerAllowlist,
                calculateBoundingBox: calculateBoundingBox,
                logger: logger)
        }
        catch let error as MLTError {
            logger?.warning("\(z)/\(x)/\(y): \(error)")
            throw MLTDecoderError.decodeFailed
        }
        #endif
    }

}

#endif
