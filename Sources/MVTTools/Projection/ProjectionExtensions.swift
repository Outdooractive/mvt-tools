#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools

// From https://www.maptiler.com/google-maps-coordinates-tile-bounds-projection/
extension Projection {

    private static let tileSize = 256
    private static let initialResolution = 2.0 * Double.pi * 6_378_137.0 / Double(tileSize) // 156543.03392804062 for tileSize 256 pixels

    /// Tile bounds in EPSG:3857
    public static func epsg3857TileBounds(
        x: Int,
        y: Int,
        z: Int)
        -> ProjectedBoundingBox
    {
        // Flip y, but why?
        let y = (1 << z) - 1 - y

        let southWest = projectPixelToEpsg3857(px: x * tileSize, py: y * tileSize, z: z)
        let northEast = projectPixelToEpsg3857(px: (x + 1) * tileSize, py: (y + 1) * tileSize, z: z)

        return ProjectedBoundingBox(southWest: southWest, northEast: northEast)
    }

    /// Tile bounds in EPSG:4326
    public static func epsg4236TileBounds(
        x: Int,
        y: Int,
        z: Int)
        -> ProjectedBoundingBox
    {
        let bounds = epsg3857TileBounds(x: x, y: y, z: z)

        let southWest = bounds.southWest.projectedToEpsg4326
        let northEast = bounds.northEast.projectedToEpsg4326

        return ProjectedBoundingBox(southWest: southWest, northEast: northEast)
    }

    /// *x* and *y* for a tile at a coordinate and zoom.
    public static func tile(
        for coordinate: Coordinate3D,
        atZoom zoom: Int)
        -> (x: Int, y: Int)
    {
        var longitude: CLLocationDegrees = coordinate.longitude
        var latitude: CLLocationDegrees = coordinate.latitude

        if longitude > 180.0 {
            longitude -= 360.0
        }

        longitude = (longitude / 360.0) + 0.5
        latitude = 0.5 - ((log(tan((Double.pi / 4.0) + ((0.5 * Double.pi * latitude) / 180.0))) / Double.pi) / 2.0)

        let scale = Double(1 << zoom)

        return (
            x: Int(floor(longitude * scale)),
            y: Int(floor(latitude * scale)))
    }

    // MARK: -

    private static func projectPixelToEpsg3857(
        px: Int,
        py: Int,
        z: Int)
        -> ProjectedCoordinate
    {
        let resolution: Double = initialResolution / pow(2.0, Double(z))

        let x = Double(px) * resolution - originShift
        let y = Double(py) * resolution - originShift

        return ProjectedCoordinate(latitude: y, longitude: x, projection: .epsg3857)
    }

}
