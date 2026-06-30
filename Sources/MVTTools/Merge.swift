#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools

// MARK: Merge

extension VectorTile {

    /// Merge all features from another ``VectorTile`` into this tile.
    ///
    /// Features are appended layer-by-layer. Layers that exist in `other` but not in `self`
    /// are created automatically. The tile coordinates (`z`/`x`/`y`) must match unless
    /// `ignoreTileCoordinateMismatch` is `true`.
    ///
    /// - Parameter other: The source tile whose features are to be merged.
    /// - Parameter ignoreTileCoordinateMismatch: When `true`, the tile coordinate check is skipped
    ///   (default: `false`). A warning is still emitted if the projections differ.
    /// - Returns: `true` on success, or `false` when the tile coordinates differ and the check
    ///   is not ignored.
    @discardableResult
    public mutating func merge(
        _ other: VectorTile,
        ignoreTileCoordinateMismatch: Bool = false
    ) -> Bool {
        if !ignoreTileCoordinateMismatch {
            guard other.x == x,
                  other.y == y,
                  other.z == z
            else {
                (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Failed to merge, other has different coordinate \(other.z)/\(other.x)/\(other.y)")
                return false
            }
        }

        if other.projection != projection {
            (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Other has different projection \(projection)")
        }

        for layerName in other.layerNames {
            let features = other.features(for: layerName)
            guard features.isNotEmpty else { continue }

            appendFeatures(features, to: layerName)
        }

        return true
    }

}
