#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools

extension VectorTile {

    public typealias QueryResult = (
        layerName: String,
        feature: Feature)

    public typealias QueryManyResult = (
        coordinate: Coordinate3D,
        results: [QueryManyLayerAndId])

    public typealias QueryManyLayerAndId = (
        layerName: String,
        featureId: Feature.Identifier)

    // MARK: - Indexing

    /// Create an R-Tree index on this tile for faster querying
    public mutating func createIndex(sortOption: RTreeSortOption = .hilbert) {
        for layerName in layerNames {
            guard var layerContainer = layers[layerName],
                  !layerContainer.features.isEmpty
            else { continue }

            layerContainer.rTree = RTree(layerContainer.features, sortOption: sortOption)

            layers[layerName] = layerContainer
        }

        indexSortOption = sortOption
    }

    // MARK: - Searching

    /// Search for `term` in feature properties
    public func query(
        term: String,
        layerName: String? = nil,
        featureFilter: ((Feature) -> Bool)? = nil)
        -> [QueryResult]
    {
        let queryLayerNames: [String]
        if let layerName {
            queryLayerNames = [layerName]
        }
        else {
            queryLayerNames = layerNames
        }

        var result: [QueryResult] = []

        for layerName in queryLayerNames {
            guard let layerFeatureContainer = layers[layerName] else { continue }

            let resultFeatures: [Feature] = layerFeatureContainer.features.filter({ feature in
                for value in feature.properties.values.compactMap({ $0 as? String }) {
                    if value.contains(term) {
                        return true
                    }
                }

                return false
            })

            for feature in resultFeatures {
                guard featureFilter?(feature) ?? true else { continue }

                result.append((
                    layerName: layerName,
                    feature: feature))
            }
        }

        return result
    }

    /// Search for content in this tile around `coordinate`
    ///
    /// Note: The meaning of *tolerance* depends on the projection.
    /// For *epsg3857* and *epsg4326*, it will be meters. For *tile*, it's a value in the tile's coordinate space.
    public func query(
        at coordinate: Coordinate3D,
        tolerance: CLLocationDistance,
        layerName: String? = nil,
        featureFilter: ((Feature) -> Bool)? = nil)
        -> [QueryResult]
    {
        let queryBoundingBox = VectorTile.queryBoundingBox(
            at: coordinate,
            tolerance: tolerance,
            projection: projection)

        return query(
            in: queryBoundingBox,
            layerName: layerName,
            featureFilter: featureFilter)
    }

    /// Search for content in this tile inside of `queryBoundingBox`
    public func query(
        in queryBoundingBox: BoundingBox,
        layerName: String? = nil,
        featureFilter: ((Feature) -> Bool)? = nil)
        -> [QueryResult]
    {
        let queryLayerNames: [String]
        if let layerName {
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
                resultFeatures = layerFeatureContainer.features.filter({ feature in
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
                    feature: feature))
            }
        }

        return result
    }

    /// Search for content in this tile at `coordinates`
    ///
    /// Note: The meaning of *tolerance* depends on the projection.
    /// For *epsg3857* and *epsg4326*, it will be meters. For *tile*, it's a value in the tile's coordinate space.
    public func queryMany(
        at coordinates: [Coordinate3D],
        tolerance: CLLocationDistance,
        layerName: String? = nil,
        featureFilter: ((Feature) -> Bool)? = nil,
        includeDuplicates: Bool = true)
        -> (features: [Feature.Identifier: Feature], results: [QueryManyResult])
    {
        let queryBoundingBoxes: [BoundingBox] = coordinates.map { coordinate in
            VectorTile.queryBoundingBox(
                at: coordinate,
                tolerance: tolerance,
                projection: projection)
        }

        let queryLayerNames: [String]
        if let layerName {
            queryLayerNames = [layerName]
        }
        else {
            queryLayerNames = layerNames
        }

        var results: [QueryManyResult] = []
        var features: [Feature.Identifier: Feature] = [:]

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
                    resultFeatures = layerFeatureContainer.features.filter({ feature in
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
                        featureId: featureId))
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

    static func queryBoundingBox(
        at coordinate: Coordinate3D,
        tolerance: CLLocationDistance,
        projection: Projection)
        -> BoundingBox
    {
        let tolerance = fabs(tolerance)

        switch projection {
        case .epsg3857, .noSRID:
            return BoundingBox(
                southWest: Coordinate3D(
                    x: coordinate.longitude - tolerance,
                    y: coordinate.latitude - tolerance,
                    projection: projection),
                northEast: Coordinate3D(
                    x: coordinate.longitude + tolerance,
                    y: coordinate.latitude + tolerance,
                    projection: projection))
            .clamped()

        case .epsg4326:
            // Length of one minute at this latitude
            let oneDegreeLatitudeDistanceInMeters = 111_000.0
            let oneDegreeLongitudeDistanceInMeters = fabs(cos(coordinate.longitude * Double.pi / 180.0) * oneDegreeLatitudeDistanceInMeters)

            let longitudeDistance = (tolerance / oneDegreeLongitudeDistanceInMeters)
            let latitudeDistance = (tolerance / oneDegreeLatitudeDistanceInMeters)

            return BoundingBox(
                southWest: Coordinate3D(
                    latitude: coordinate.latitude - latitudeDistance,
                    longitude: coordinate.longitude - longitudeDistance),
                northEast: Coordinate3D(
                    latitude: coordinate.latitude + latitudeDistance,
                    longitude: coordinate.longitude + longitudeDistance))
            .clamped()
        }
    }

}
