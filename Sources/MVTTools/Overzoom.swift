#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
import Logging

// MARK: - Rezoom (overzoom / underzoom)

extension VectorTile {

    /// Rezoom this tile into a target tile at a different zoom level.
    ///
    /// Works for both overzooming (target `z` > source `z`) and underzooming
    /// (target `z` < source `z`). The target must be an ancestor or descendant
    /// of this tile; otherwise `nil` is returned.
    ///
    /// Features are copied in geographic coordinates — clipping to the target
    /// tile's bounding box (plus an optional buffer) happens at encode time
    /// when the caller invokes ``mvtData(options:)``, ``writeMVT(to:options:)``,
    /// or ``toGeoJson(options:)``.
    ///
    /// - Parameters:
    ///   - targetX: The target tile's x coordinate.
    ///   - targetY: The target tile's y coordinate.
    ///   - targetZ: The target tile's zoom level.
    /// - Returns: A new `VectorTile` at the target coordinates containing this
    ///   tile's features, or `nil` if the target is not an ancestor or
    ///   descendant of this tile.
    public func rezoom(
        toTargetX targetX: Int,
        targetY: Int,
        targetZ: Int
    ) -> VectorTile? {
        let source = MapTile(x: x, y: y, z: z)
        let target = MapTile(x: targetX, y: targetY, z: targetZ)

        guard source.isRelated(to: target) else {
            (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Target \(targetZ)/\(targetX)/\(targetY) is not an ancestor or descendant")
            return nil
        }

        guard var result = VectorTile(
            x: targetX,
            y: targetY,
            z: targetZ,
            projection: projection,
            logger: logger ?? VectorTile.logger)
        else {
            return nil
        }

        for layerName in layerNames {
            let features = self.features(for: layerName)
            guard features.isNotEmpty else { continue }
            result.appendFeatures(features, to: layerName)
        }

        return result
    }

    /// Rezoom multiple source tiles into a single target tile.
    ///
    /// Each source tile is rezoomed to the target coordinates via
    /// ``rezoom(toTargetX:targetY:targetZ:)`` and the results are merged.
    /// Sources that are not ancestors or descendants of the target are
    /// silently skipped (the result tile may still contain features from
    /// valid sources).
    ///
    /// - Parameters:
    ///   - sources: The source tiles (may be at different zoom levels).
    ///     Each must be an ancestor or descendant of the target.
    ///   - targetX: The target tile's x coordinate.
    ///   - targetY: The target tile's y coordinate.
    ///   - targetZ: The target tile's zoom level.
    /// - Returns: A rezoomed `VectorTile` at the target coordinates. The
    ///   tile may be empty if no sources were valid ancestors/descendants.
    public static func rezoom(
        _ sources: [VectorTile],
        toTargetX targetX: Int,
        targetY: Int,
        targetZ: Int
    ) -> VectorTile {
        let target = MapTile(x: targetX, y: targetY, z: targetZ)

        // Use the projection from the first valid source, or default to
        // EPSG:4326 if no sources are valid.
        var projection: Projection = .epsg4326
        for source in sources {
            if source.mapTile.isRelated(to: target) {
                projection = source.projection
                break
            }
        }

        guard var result = VectorTile(x: targetX, y: targetY, z: targetZ, projection: projection) else {
            // Should never fail for valid coordinates
            return VectorTile(x: 0, y: 0, z: 0, projection: projection)!
        }

        for source in sources {
            guard let rezoomed = source.rezoom(toTargetX: targetX, targetY: targetY, targetZ: targetZ) else {
                continue
            }
            result.merge(rezoomed, ignoreTileCoordinateMismatch: true)
        }

        return result
    }

}