#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools

// From https://www.maptiler.com/google-maps-coordinates-tile-bounds-projection/
public extension Projection {

    private static let tileSize: Int = 256
    private static let originShift: Double = 2.0 * Double.pi * 6378137.0 / 2.0 // 20037508.342789244
    private static let initialResolution: Double = 2.0 * Double.pi * 6378137.0 / Double(tileSize) // 156543.03392804062 for tileSize 256 pixels

    /// Project EPSG:4326 to EPSG:3857
    internal static func projectToEpsg3857(coordinate: Coordinate3D) -> Coordinate3D {
        let coordinate = coordinate.normalized()

        let x: Double = coordinate.longitude * originShift / 180.0
        var y: Double = log(tan((90.0 + coordinate.latitude) * Double.pi / 360.0)) / (Double.pi / 180.0)
        y *= originShift / 180.0

        return Coordinate3D(latitude: y, longitude: x)
    }

    /// Project EPSG:3857 to EPSG:4326
    internal static func projectToEpsg4326(coordinate: Coordinate3D) -> Coordinate3D {
        let longitude: Double = (coordinate.longitude / originShift) * 180.0
        var latitude: Double = (coordinate.latitude / originShift) * 180.0
        latitude = 180.0 / Double.pi * (2.0 * atan(exp(latitude * Double.pi / 180.0)) - Double.pi / 2.0)

        return Coordinate3D(latitude: latitude, longitude: longitude)
    }

    /// Tile bounds in EPSG:3857
    static func epsg3857TileBounds(
        x: Int,
        y: Int,
        z: Int)
        -> BoundingBox
    {
        // Flip y, but why?
        let y = (1 << z) - 1 - y

        let southWest: Coordinate3D = projectPixelToEpsg3857(px: x * tileSize, py: y * tileSize, z: z)
        let northEast: Coordinate3D = projectPixelToEpsg3857(px: (x + 1) * tileSize, py: (y + 1) * tileSize, z: z)

        return BoundingBox(southWest: southWest, northEast: northEast)
    }

    /// Tile bounds in EPSG:4326
    static func epsg4236TileBounds(
        x: Int,
        y: Int,
        z: Int)
        -> BoundingBox
    {
        let bounds = epsg3857TileBounds(x: x, y: y, z: z)

        let southWest: Coordinate3D = projectToEpsg4326(coordinate: bounds.southWest)
        let northEast: Coordinate3D = projectToEpsg4326(coordinate: bounds.northEast)

        return BoundingBox(southWest: southWest, northEast: northEast)
    }

    static func tile(
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

        let scale: Double = Double(1 << zoom)

        return (
            x: Int(floor(longitude * scale)),
            y: Int(floor(latitude * scale)))
    }

    // MARK: -

    private static func projectPixelToEpsg3857(
        px: Int,
        py: Int,
        z: Int)
        -> Coordinate3D
    {
        let resolution: Double = initialResolution / pow(2.0, Double(z))

        let x: Double = Double(px) * resolution - originShift
        let y: Double = Double(py) * resolution - originShift

        return Coordinate3D(latitude: y, longitude: x)
    }

}
