import Foundation
import GISTools

// MARK: - Forward projections (tile-extent → geographic)

enum Projections {

    /// Passes tile-local coordinates through without projection (noSRID).
    static func passThroughFromTile(
        x: Int,
        y: Int
    ) -> (Int, Int) -> Coordinate3D {
        { (cx, cy) -> Coordinate3D in
            Coordinate3D(x: Double(cx), y: Double(cy), projection: .noSRID)
        }
    }

    /// Returns a projection function that converts tile-local coordinates
    /// into `projection` for *any* registered projection.
    ///
    /// The MVT/MLT tile grid is a Web Mercator pyramid: tile-local
    /// coordinates are linear in Web Mercator meters. The function therefore
    /// interpolates linearly in EPSG:3857 within the tile bounds and projects
    /// the result through gis-tools' EPSG:4326 pivot into the target
    /// projection. For EPSG:3857, EPSG:4326 and EPSG:4978 this is identical
    /// to the previous per-projection special cases, but projections
    /// registered at runtime (e.g. via ``CustomProjection``) are now supported
    /// as well.
    ///
    /// - Parameters:
    ///   - projection: The target projection.
    ///   - x: The tile's x coordinate.
    ///   - y: The tile's y coordinate.
    ///   - z: The tile's zoom level.
    ///   - extent: The layer extent (tile grid size).
    /// - Returns: A function mapping tile-local (x, y) integers to
    ///   `Coordinate3D` in `projection`.
    static func forwardProjection(
        for projection: Projection,
        x: Int,
        y: Int,
        z: Int,
        extent: Int
    ) -> (Int, Int) -> Coordinate3D {
        if !projection.hasSRID {
            return passThroughFromTile(x: x, y: y)
        }

        let extent = Double(extent)
        let bounds = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)
        let topLeft = Coordinate3D(x: bounds.southWest.x, y: bounds.northEast.y)
        let xSpan: Double = abs(bounds.northEast.x - bounds.southWest.x)
        let ySpan: Double = abs(bounds.northEast.y - bounds.southWest.y)

        return { (cx, cy) -> Coordinate3D in
            let projectedX = topLeft.x + (Double(cx) / extent) * xSpan
            let projectedY = topLeft.y - (Double(cy) / extent) * ySpan
            let mercatorCoordinate = Coordinate3D(x: projectedX, y: projectedY, projection: .epsg3857)
            return mercatorCoordinate.projected(to: projection)
        }
    }

}

// MARK: - Inverse projections (geographic → tile-extent)

extension Projections {

    /// Passes coordinate values through as-is (noSRID).
    static func passThroughToTile() -> (Coordinate3D) -> (Int, Int) {
        { coordinate in
            (x: Int(coordinate.x), y: Int(coordinate.y))
        }
    }

    /// Returns a projection function that converts coordinates in `projection`
    /// to tile-local integers for *any* registered projection.
    ///
    /// Coordinates are projected into EPSG:3857 (the native space of the MVT
    /// tile grid), then mapped linearly into the tile extent. For EPSG:3857,
    /// EPSG:4326 and EPSG:4978 this is identical to the previous
    /// per-projection special cases, but projections registered at runtime
    /// (e.g. via ``CustomProjection``) are now supported as well.
    ///
    /// - Parameters:
    ///   - projection: The source projection of the input coordinates.
    ///   - x: The tile's x coordinate.
    ///   - y: The tile's y coordinate.
    ///   - z: The tile's zoom level.
    ///   - extent: The layer extent (tile grid size).
    /// - Returns: A function mapping `Coordinate3D` in `projection` to
    ///   tile-local (x, y) integers.
    static func inverseProjection(
        for projection: Projection,
        x: Int,
        y: Int,
        z: Int,
        extent: Int
    ) -> (Coordinate3D) -> (Int, Int) {
        if !projection.hasSRID {
            return passThroughToTile()
        }

        let extent = Double(extent)
        let bounds = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)
        let topLeft = Coordinate3D(x: bounds.southWest.x, y: bounds.northEast.y)
        let xSpan: Double = abs(bounds.northEast.x - bounds.southWest.x)
        let ySpan: Double = abs(bounds.northEast.y - bounds.southWest.y)

        return { coordinate in
            let projectedCoordinate = coordinate.projected(to: .epsg3857)
            let projectedX = Int(((projectedCoordinate.x - topLeft.x) / xSpan) * extent)
            let projectedY = Int(((topLeft.y - projectedCoordinate.y) / ySpan) * extent)
            return (projectedX, projectedY)
        }
    }

}
