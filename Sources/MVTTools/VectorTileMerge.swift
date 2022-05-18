#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools

// MARK: Merge

extension VectorTile {

    /// Merge another vector tile into this tile.
    public mutating func merge(_ other: VectorTile) -> Bool {
        guard other.x == x,
              other.y == y,
              other.z == z,
              other.projection == projection
        else { return false }

        for layerName in other.layerNames {
            guard let features = other.features(for: layerName) else { continue }

            appendFeatures(features, to: layerName)
        }

        return true
    }

}
