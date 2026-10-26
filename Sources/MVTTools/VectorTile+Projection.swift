import Foundation
import GISTools

// MARK: - Coordinate and geometry reprojection

extension Coordinate3D {

    /// Returns the same numeric values tagged with a different projection.
    func retagged(to projection: Projection) -> Coordinate3D {
        Coordinate3D(
            x: longitude,
            y: latitude,
            z: altitude,
            m: m,
            projection: projection)
    }

}

extension GeoJsonGeometry {

    /// Returns the geometry with its coordinates reinterpreted in another CRS.
    ///
    /// This does not perform a datum transformation. Use
    /// ``Projectable/projected(to:)`` for an actual reprojection.
    func retagged(to projection: Projection) -> GeoJsonGeometry {
        switch self {
        case let point as Point:
            return Point(point.coordinate.retagged(to: projection), calculateBoundingBox: true)

        case let multiPoint as MultiPoint:
            return MultiPoint(
                unchecked: multiPoint.coordinates.map { $0.retagged(to: projection) },
                calculateBoundingBox: true)

        case let lineString as LineString:
            return LineString(
                unchecked: lineString.coordinates.map { $0.retagged(to: projection) },
                calculateBoundingBox: true)

        case let multiLineString as MultiLineString:
            return MultiLineString(
                unchecked: multiLineString.coordinates.map {
                    $0.map { $0.retagged(to: projection) }
                },
                calculateBoundingBox: true)

        case let polygon as Polygon:
            return Polygon(
                unchecked: polygon.rings.map {
                    Ring(unchecked: $0.coordinates.map { $0.retagged(to: projection) })
                },
                calculateBoundingBox: true)

        case let multiPolygon as MultiPolygon:
            return MultiPolygon(
                unchecked: multiPolygon.polygons.map {
                    Polygon(
                        unchecked: $0.rings.map {
                            Ring(unchecked: $0.coordinates.map { $0.retagged(to: projection) })
                        },
                        calculateBoundingBox: true)
                },
                calculateBoundingBox: true)

        case let collection as GeometryCollection:
            return GeometryCollection(
                collection.geometries.map { $0.retagged(to: projection) },
                calculateBoundingBox: true)

        default:
            return self
        }
    }

}

extension Feature {

    /// Returns the feature with its geometry reinterpreted in another CRS.
    func retagged(to projection: Projection) -> Feature {
        if let geometry {
            var result = Feature(
                geometry.retagged(to: projection),
                id: id,
                properties: properties,
                calculateBoundingBox: true)
            result.foreignMembers = foreignMembers
            return result
        }

        return Feature(
            id: id,
            properties: properties,
            foreignMembers: foreignMembers)
    }

}

// MARK: - VectorTile conversions

extension VectorTile {

    /// Returns a copy with every feature reprojected into `projection`.
    ///
    /// This performs a real CRS transformation, unlike ``retagged(to:)``.
    public func projected(to projection: Projection) throws -> VectorTile {
        guard projection != self.projection else { return self }

        var result = try VectorTile(
            x: x,
            y: y,
            z: z,
            projection: projection,
            indexed: indexSortOption,
            logger: logger)
        for layerName in layerNames {
            result.setFeatures(features(for: layerName), for: layerName)
        }
        return result
    }

    /// Returns a copy whose coordinates are reinterpreted as `projection`.
    ///
    /// This does not transform coordinates. It is intended for formats whose
    /// CRS metadata is missing or known to be wrong.
    public func retagged(to projection: Projection) throws -> VectorTile {
        guard projection != self.projection else { return self }

        var result = try VectorTile(
            x: x,
            y: y,
            z: z,
            projection: projection,
            indexed: indexSortOption,
            logger: logger)

        for layerName in layerNames {
            let features = features(for: layerName).map { $0.retagged(to: projection) }
            let boxes = features.compactMap(\.boundingBox)
            let boundingBox = boxes.isEmpty ? nil : boxes.reduce(boxes[0], +)
            result.layers[layerName] = LayerContainer(
                features: features,
                boundingBox: boundingBox)
        }
        result.layerNames = result.layers.keys.sorted()
        if let indexSortOption {
            result.createIndex(sortOption: indexSortOption)
        }
        return result
    }

}
