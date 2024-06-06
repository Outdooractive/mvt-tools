#if !os(Linux)
    import CoreLocation
#endif
import Foundation
import GISTools

// MARK: Merge

extension VectorTile {

    /// Merge another vector tile into this tile.
    @discardableResult
    public mutating func merge(
        _ other: VectorTile,
        ignoreTileCoordinateMismatch: Bool = false)
        -> Bool
    {
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
            guard let features = other.features(for: layerName) else { continue }

            appendFeatures(features, to: layerName)
        }

        return true
    }

}
