import Foundation
import GISTools

#if EnableMLT

/// Encodes GISTools features into the MapLibre Tile (MLT) binary format.
///
/// The actual implementation is selected at compile time:
/// - `EnableMLTCXX` uses the C++ `maplibre-tile-spec` bridge.
/// - `EnableMLT` alone uses the pure Swift implementation.
enum MLTEncoder {

    /// Encodes layers into MLT binary data, with optional projection, clipping,
    /// simplification, and compression.
    ///
    /// - Parameters:
    ///   - layers: A dictionary of layer names to their `VectorTile.LayerContainer`.
    ///   - x: The tile column index.
    ///   - y: The tile row index.
    ///   - z: The tile zoom level.
    ///   - projection: The source projection of the input coordinates (default: `Projection.epsg4326`).
    ///   - options: Export options controlling buffer size, simplification, and compression.
    /// - Returns: The encoded MLT binary data, or `nil` on failure.
    static func encode(
        layers: [String: VectorTile.LayerContainer],
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        options: VectorTile.ExportOptions = .init()
    ) -> Data? {
        #if EnableMLTCXX
        return MLTEncoderCXX.encode(
            layers: layers,
            x: x,
            y: y,
            z: z,
            projection: projection,
            options: options)
        #else
        return MLTEncoderSwift.encode(
            layers: layers,
            x: x,
            y: y,
            z: z,
            projection: projection,
            options: options)
        #endif
    }

}

#endif
