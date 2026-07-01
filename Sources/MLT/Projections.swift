import Foundation
import GISTools

// MARK: - Forward projections (tile-extent → geographic)

extension MLTDecoder {

    /// Passes tile-local coordinates through without projection (noSRID).
    static func passThroughFromTile(
        x: Int,
        y: Int
    ) -> (Int, Int) -> Coordinate3D {
        { (cx, cy) -> Coordinate3D in
            Coordinate3D(x: Double(cx), y: Double(cy), projection: .noSRID)
        }
    }

    /// Returns a projection function that converts tile-local coordinates to EPSG:4978.
    static func projectToEpsg4978(
        x: Int,
        y: Int,
        z: Int,
        extent: Int
    ) -> (Int, Int) -> Coordinate3D {
        let projectedTo4326 = projectToEpsg4326(x: x, y: y, z: z, extent: extent)
        return { (cx, cy) -> Coordinate3D in
            projectedTo4326(cx, cy).projected(to: .epsg4978)
        }
    }

    /// Returns a projection function that converts tile-local coordinates to EPSG:3857.
    static func projectToEpsg3857(
        x: Int,
        y: Int,
        z: Int,
        extent: Int
    ) -> (Int, Int) -> Coordinate3D {
        let extent = Double(extent)
        let bounds = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)
        let topLeft = Coordinate3D(x: bounds.southWest.x, y: bounds.northEast.y)
        let xSpan: Double = abs(bounds.northEast.x - bounds.southWest.x)
        let ySpan: Double = abs(bounds.northEast.y - bounds.southWest.y)

        return { (cx, cy) -> Coordinate3D in
            let projectedX = topLeft.x + (Double(cx) / extent) * xSpan
            let projectedY = topLeft.y - (Double(cy) / extent) * ySpan
            return Coordinate3D(x: projectedX, y: projectedY)
        }
    }

    /// Returns a projection function that converts tile-local coordinates to EPSG:4326.
    static func projectToEpsg4326(
        x: Int,
        y: Int,
        z: Int,
        extent: Int
    ) -> (Int, Int) -> Coordinate3D {
        let extent = Double(extent)
        let bounds = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)
        let topLeft = Coordinate3D(x: bounds.southWest.x, y: bounds.northEast.y)
        let xSpan: Double = abs(bounds.northEast.x - bounds.southWest.x)
        let ySpan: Double = abs(bounds.northEast.y - bounds.southWest.y)

        return { (cx, cy) -> Coordinate3D in
            let projectedX = topLeft.x + (Double(cx) / extent) * xSpan
            let projectedY = topLeft.y - (Double(cy) / extent) * ySpan
            return Coordinate3D(x: projectedX, y: projectedY).projected(to: .epsg4326)
        }
    }

    /// Picks the forward projection function matching the given projection.
    static func forwardProjection(
        for projection: Projection,
        x: Int,
        y: Int,
        z: Int,
        extent: Int
    ) -> (Int, Int) -> Coordinate3D {
        switch projection {
        case .noSRID:
            passThroughFromTile(x: x, y: y)
        case .epsg3857:
            projectToEpsg3857(x: x, y: y, z: z, extent: extent)
        case .epsg4326:
            projectToEpsg4326(x: x, y: y, z: z, extent: extent)
        case .epsg4978:
            projectToEpsg4978(x: x, y: y, z: z, extent: extent)
        }
    }

}

// MARK: - Inverse projections (geographic → tile-extent)

extension MLTEncoder {

    /// Passes coordinate values through as-is (noSRID).
    static func passThroughToTile() -> (Coordinate3D) -> (Int, Int) {
        { coordinate in
            (x: Int(coordinate.x), y: Int(coordinate.y))
        }
    }

    /// Returns a projection function that converts EPSG:3857 to tile-local integers.
    static func projectFromEpsg3857(
        x: Int,
        y: Int,
        z: Int,
        extent: Int
    ) -> (Coordinate3D) -> (Int, Int) {
        let extent = Double(extent)
        let bounds = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)
        let topLeft = Coordinate3D(x: bounds.southWest.x, y: bounds.northEast.y)
        let xSpan: Double = abs(bounds.northEast.x - bounds.southWest.x)
        let ySpan: Double = abs(bounds.northEast.y - bounds.southWest.y)

        return { coordinate in
            let projectedX = Int(((coordinate.x - topLeft.x) / xSpan) * extent)
            let projectedY = Int(((topLeft.y - coordinate.y) / ySpan) * extent)
            return (projectedX, projectedY)
        }
    }

    /// Returns a projection function that converts EPSG:4978 to tile-local integers.
    static func projectFromEpsg4978(
        x: Int,
        y: Int,
        z: Int,
        extent: Int
    ) -> (Coordinate3D) -> (Int, Int) {
        let projectedFrom4326 = projectFromEpsg4326(x: x, y: y, z: z, extent: extent)
        return { coordinate in
            projectedFrom4326(coordinate.projected(to: .epsg4326))
        }
    }

    /// Returns a projection function that converts EPSG:4326 to tile-local integers.
    static func projectFromEpsg4326(
        x: Int,
        y: Int,
        z: Int,
        extent: Int
    ) -> (Coordinate3D) -> (Int, Int) {
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

    /// Picks the inverse projection function matching the given projection.
    static func inverseProjection(
        for projection: Projection,
        x: Int,
        y: Int,
        z: Int,
        extent: Int
    ) -> (Coordinate3D) -> (Int, Int) {
        switch projection {
        case .noSRID:
            passThroughToTile()
        case .epsg3857:
            projectFromEpsg3857(x: x, y: y, z: z, extent: extent)
        case .epsg4326:
            projectFromEpsg4326(x: x, y: y, z: z, extent: extent)
        case .epsg4978:
            projectFromEpsg4978(x: x, y: y, z: z, extent: extent)
        }
    }

}
