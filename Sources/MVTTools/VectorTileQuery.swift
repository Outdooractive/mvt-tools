#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools

extension VectorTile {

    public typealias QueryResult = (
        layerName: String,
        feature: Feature
    )

    public typealias QueryManyResult = (
        coordinate: Coordinate3D,
        results: [QueryManyLayerAndId]
    )

    public typealias QueryManyLayerAndId = (
        layerName: String,
        featureId: String
    )

    // MARK: - Indexing

    public mutating func createIndex() {
        for layerName in layerNames {
            guard var layerContainer = layers[layerName],
                  !layerContainer.features.isEmpty
            else { continue }

            layerContainer.rTree = RTree(layerContainer.features)

            layers[layerName] = layerContainer
        }

        isIndexed = true
    }

    // MARK: - Searching

    /// Note: The meaning of *tolerance* depends on the projection.
    /// For *epsg3857* and *epsg4326*, it will be meters. For *tile*, it's a value in the tile's coordinate space.
    public func query(
        at coordinate: Coordinate3D,
        tolerance: CLLocationDistance,
        layerName: String? = nil,
        featureFilter: ((Feature) -> Bool)? = nil,
        projection: TileProjection = .epsg4326)
        -> [QueryResult]
    {
        if projection != self.projection {
            assertionFailure("Reprojection is currently not supported")
            return []
        }

        let queryBoundingBox = VectorTile.queryBoundingBox(
            at: coordinate,
            tolerance: tolerance,
            projection: projection)

        return query(
            in: queryBoundingBox,
            layerName: layerName,
            featureFilter: featureFilter,
            projection: projection)
    }

    public func query(
        in queryBoundingBox: BoundingBox,
        layerName: String? = nil,
        featureFilter: ((Feature) -> Bool)? = nil,
        projection: TileProjection = .epsg4326)
        -> [QueryResult]
    {
        if projection != self.projection {
            assertionFailure("Reprojection is currently not supported")
            return []
        }

        let queryLayerNames: [String]
        if let layerName = layerName {
            queryLayerNames = [layerName]
        }
        else {
            queryLayerNames = layerNames
        }

        var result: [QueryResult] = []

        for layerName in queryLayerNames {
            guard let layerFeatureContainer = layers[layerName],
                let boundingBox = layerFeatureContainer.boundingBox,
                boundingBox.intersects(queryBoundingBox)
                else { continue }

            let resultFeatures: [Feature]

            if let rTree = layerFeatureContainer.rTree {
                // The search will only return features that intersect with the bounding box
                resultFeatures = rTree.search(inBoundingBox: queryBoundingBox)
            }
            else {
                resultFeatures = layerFeatureContainer.features.filter({ (feature) in
                    // First check the feature's bounding box
                    guard feature.boundingBox?.intersects(queryBoundingBox) ?? false else { return false }

                    // Check the feature itself
                    guard feature.intersects(queryBoundingBox) else { return false }

                    return true
                })
            }

            for feature in resultFeatures {
                guard featureFilter?(feature) ?? true else { continue }

                result.append((
                    layerName: layerName,
                    feature: feature
                ))
            }
        }

        return result
    }

    /// Note: The meaning of *tolerance* depends on the projection.
    /// For *epsg3857* and *epsg4326*, it will be meters. For *tile*, it's a value in the tile's coordinate space.
    public func queryMany(
        at coordinates: [Coordinate3D],
        tolerance: CLLocationDistance,
        layerName: String? = nil,
        featureFilter: ((Feature) -> Bool)? = nil,
        includeDuplicates: Bool = true,
        projection: TileProjection = .epsg4326)
        -> (features: [String: Feature], results: [QueryManyResult])
    {
        if projection != self.projection {
            assertionFailure("Reprojection is currently not supported")
            return (features: [:], results: [])
        }

        let queryBoundingBoxes: [BoundingBox] = coordinates.map { (coordinate) in
            return VectorTile.queryBoundingBox(
                at: coordinate,
                tolerance: tolerance,
                projection: projection)
        }

        let queryLayerNames: [String]
        if let layerName = layerName {
            queryLayerNames = [layerName]
        }
        else {
            queryLayerNames = layerNames
        }

        var results: [QueryManyResult] = []
        var features: [String: Feature] = [:]

        for (index, queryBoundingBox) in queryBoundingBoxes.enumerated() {
            var currentResult: [QueryManyLayerAndId] = []

            for layerName in queryLayerNames {
                guard let layerFeatureContainer = layers[layerName],
                    let boundingBox = layerFeatureContainer.boundingBox,
                    boundingBox.intersects(queryBoundingBox)
                    else { break }

                let resultFeatures: [Feature]

                if let rTree = layerFeatureContainer.rTree {
                    // The search will only return features that intersect with the bounding box
                    resultFeatures = rTree.search(inBoundingBox: queryBoundingBox)
                }
                else {
                    resultFeatures = layerFeatureContainer.features.filter({ (feature) in
                        // First check the feature's bounding box
                        guard feature.boundingBox?.intersects(queryBoundingBox) ?? false else { return false }

                        // Check the feature itself
                        guard feature.intersects(queryBoundingBox) else { return false }

                        return true
                    })
                }

                for feature in resultFeatures {
                    // All parsed features get automatically an id
                    guard let featureId = feature.id else { continue }

                    if !features.hasKey(featureId) {
                        features[featureId] = feature
                    }
                    else if !includeDuplicates {
                        continue
                    }

                    guard featureFilter?(feature) ?? true else { continue }

                    currentResult.append((
                        layerName: layerName,
                        featureId: featureId
                    ))
                }
            }

            if !currentResult.isEmpty {
                results.append(
                    QueryManyResult(
                        coordinate: coordinates[index],
                        results: currentResult))
            }
        }

        return (features: features, results: results)
    }

    private static func queryBoundingBox(
        at coordinate: Coordinate3D,
        tolerance: CLLocationDistance,
        projection: TileProjection)
        -> BoundingBox
    {
        switch projection {
        case .tile, .epsg3857:
            return BoundingBox(
                southWest: Coordinate3D(
                    latitude: coordinate.latitude - tolerance,
                    longitude: coordinate.longitude - tolerance),
                northEast: Coordinate3D(
                    latitude: coordinate.latitude + tolerance,
                    longitude: coordinate.longitude + tolerance))

        case .epsg4326:
            // Length of one minute at this latitude
            let oneDegreeLongitudeDistanceInMeters: Double = cos(coordinate.longitude * Double.pi / 180.0) * 111000.0
            let oneDegreeLatitudeDistanceInMeters: Double = 111000.0

            let longitudeDistance: Double = (tolerance / oneDegreeLongitudeDistanceInMeters)
            let latitudeDistance: Double = (tolerance / oneDegreeLatitudeDistanceInMeters)

            return BoundingBox(
                southWest: Coordinate3D(
                    latitude: coordinate.latitude - latitudeDistance,
                    longitude: coordinate.longitude - longitudeDistance),
                northEast: Coordinate3D(
                    latitude: coordinate.latitude + latitudeDistance,
                    longitude: coordinate.longitude + longitudeDistance))
        }
    }

}
