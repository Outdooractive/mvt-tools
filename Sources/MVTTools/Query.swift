#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools

extension VectorTile {

    /// A single search result pairing the layer name with a matching feature.
    public typealias QueryResult = (
        layerName: String,
        feature: Feature)

    /// Results for a multi-coordinate query, grouping the feature identifiers found at each coordinate.
    public typealias QueryManyResult = (
        coordinate: Coordinate3D,
        results: [QueryManyLayerAndId])

    /// Identifies a single feature within a ``QueryManyResult`` by its layer name and feature identifier.
    public typealias QueryManyLayerAndId = (
        layerName: String,
        featureId: Feature.Identifier)

    // MARK: - Indexing

    /// Create an R-Tree spatial index on every layer of this tile to accelerate subsequent bounding-box queries.
    ///
    /// - Parameter sortOption: The sort heuristic used during R-Tree construction (default: `.hilbert`).
    public mutating func createIndex(sortOption: RTreeSortOption = .hilbert) {
        for layerName in layerNames {
            guard var layerContainer = layers[layerName],
                  layerContainer.features.isNotEmpty
            else { continue }

            layerContainer.rTree = RTree(layerContainer.features, sortOption: sortOption)

            layers[layerName] = layerContainer
        }

        indexSortOption = sortOption
    }

    // MARK: - Searching

    /// Search for features whose properties match `term`.
    ///
    /// When `term` contains special characters (e.g. `=`, `>`, `<`, `LIKE`, `AND`, `OR`, `NOT`),
    /// it is parsed using the built-in query DSL. Otherwise a simple case-insensitive substring
    /// match is performed against every string-valued property.
    ///
    /// - Parameter term: The search term or query DSL expression.
    /// - Parameter layerName: If provided, only features in this layer are searched.
    /// - Parameter featureFilter: An optional closure for additional filtering of matched features.
    /// - Returns: An array of ``QueryResult`` tuples, one for each matching feature.
    public func query(
        term: String,
        layerName: String? = nil,
        featureFilter: ((Feature) -> Bool)? = nil
    ) -> [QueryResult] {
        let queryLayerNames: [String] = if let layerName {
            [layerName]
        }
        else {
            layerNames
        }

        let queryParser = QueryParser(string: term)

        var result: [QueryResult] = []

        for layerName in queryLayerNames {
            guard let layerFeatureContainer = layers[layerName] else { continue }

            let resultFeatures: [Feature] = layerFeatureContainer.features.filter({ feature in
                if let queryParser,
                   let properties = feature.properties as? [String: AnyHashable]
                {
                    return queryParser.evaluate(on: properties, coordinate: feature.geometry.centroid?.coordinate)
                }
                else {
                    for value in feature.properties.values.compactMap({ $0 as? String }) {
                        if value.localizedCaseInsensitiveContains(term) {
                            return true
                        }
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

    /// Search for features near `coordinate` within the given `tolerance`.
    ///
    /// The search uses a bounding box centered on `coordinate` and expanded by `tolerance`.
    ///
    /// - Note: The meaning of *tolerance* depends on the projection.
    ///   For `epsg3857` and `epsg4326` it is in meters. For `noSRID` it is in the tile's coordinate space.
    ///
    /// - Parameter coordinate: The center point of the search.
    /// - Parameter tolerance: The search radius around `coordinate`.
    /// - Parameter layerName: If provided, only this layer is searched.
    /// - Parameter featureFilter: An optional closure for additional filtering of matched features.
    /// - Returns: An array of ``QueryResult`` tuples, one for each matching feature.
    public func query(
        at coordinate: Coordinate3D,
        tolerance: CLLocationDistance,
        layerName: String? = nil,
        featureFilter: ((Feature) -> Bool)? = nil
    ) -> [QueryResult] {
        let queryBoundingBox = VectorTile.queryBoundingBox(
            at: coordinate,
            tolerance: tolerance,
            projection: projection)

        return query(
            in: queryBoundingBox,
            layerName: layerName,
            featureFilter: featureFilter)
    }

    /// Search for features that intersect `queryBoundingBox`.
    ///
    /// Uses the R-Tree spatial index when available; otherwise performs a linear scan.
    ///
    /// - Parameter queryBoundingBox: The bounding box to test for intersection.
    /// - Parameter layerName: If provided, only this layer is searched.
    /// - Parameter featureFilter: An optional closure for additional filtering of matched features.
    /// - Returns: An array of ``QueryResult`` tuples, one for each matching feature.
    public func query(
        in queryBoundingBox: BoundingBox,
        layerName: String? = nil,
        featureFilter: ((Feature) -> Bool)? = nil
    ) -> [QueryResult] {
        let queryLayerNames: [String] = if let layerName {
            [layerName]
        }
        else {
            layerNames
        }

        var result: [QueryResult] = []

        for layerName in queryLayerNames {
            guard let layerFeatureContainer = layers[layerName],
                  let boundingBox = layerFeatureContainer.boundingBox,
                  boundingBox.intersects(queryBoundingBox)
            else { continue }

            let resultFeatures: [Feature] = if let rTree = layerFeatureContainer.rTree {
                // The search will only return features that intersect with the bounding box
                rTree.search(inBoundingBox: queryBoundingBox)
            }
            else {
                layerFeatureContainer.features.filter({ feature in
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

    /// Search for features near multiple `coordinates` within the given `tolerance`.
    ///
    /// - Note: The meaning of *tolerance* depends on the projection.
    ///   For `epsg3857` and `epsg4326` it is in meters. For `noSRID` it is in the tile's coordinate space.
    ///
    /// - Parameter coordinates: An array of center points to search around.
    /// - Parameter tolerance: The search radius applied to every coordinate.
    /// - Parameter layerName: If provided, only this layer is searched.
    /// - Parameter featureFilter: An optional closure for additional filtering of matched features.
    /// - Parameter includeDuplicates: When `false`, a feature is only reported once even if it matches multiple coordinates.
    /// - Returns: A tuple containing a deduplicated `features` dictionary and a `results` array mapping each coordinate to its matching feature identifiers.
    public func queryMany(
        at coordinates: [Coordinate3D],
        tolerance: CLLocationDistance,
        layerName: String? = nil,
        featureFilter: ((Feature) -> Bool)? = nil,
        includeDuplicates: Bool = true
    ) -> (features: [Feature.Identifier: Feature], results: [QueryManyResult]) {
        let queryBoundingBoxes: [BoundingBox] = coordinates.map { coordinate in
            VectorTile.queryBoundingBox(
                at: coordinate,
                tolerance: tolerance,
                projection: projection)
        }

        let queryLayerNames: [String] = if let layerName {
            [layerName]
        }
        else {
            layerNames
        }

        var results: [QueryManyResult] = []
        var features: [Feature.Identifier: Feature] = [:]

        for (index, queryBoundingBox) in queryBoundingBoxes.enumerated() {
            var currentResult: [QueryManyLayerAndId] = []

            for layerName in queryLayerNames {
                guard let layerFeatureContainer = layers[layerName],
                      let boundingBox = layerFeatureContainer.boundingBox,
                      boundingBox.intersects(queryBoundingBox)
                else { continue }

                let resultFeatures: [Feature] = if let rTree = layerFeatureContainer.rTree {
                    // The search will only return features that intersect with the bounding box
                    rTree.search(inBoundingBox: queryBoundingBox)
                }
                else {
                    layerFeatureContainer.features.filter({ feature in
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

            if currentResult.isNotEmpty {
                results.append(
                    QueryManyResult(
                        coordinate: coordinates[index],
                        results: currentResult))
            }
        }

        return (features: features, results: results)
    }

    /// Compute a bounding box centred on `coordinate` and expanded by `tolerance`.
    ///
    /// - Parameter coordinate: The centre point.
    /// - Parameter tolerance: The distance to extend in each direction.
    /// - Parameter projection: The projection of `coordinate`; determines how `tolerance` is interpreted.
    /// - Returns: A bounding box centred on `coordinate` with the requested padding.
    static func queryBoundingBox(
        at coordinate: Coordinate3D,
        tolerance: CLLocationDistance,
        projection: Projection
    ) -> BoundingBox {
        let tolerance = fabs(tolerance)

        switch projection {
        case .noSRID:
            return BoundingBox(
                coordinates: [
                    Coordinate3D(
                        x: coordinate.longitude - tolerance,
                        y: coordinate.latitude - tolerance,
                        projection: projection),
                    Coordinate3D(
                        x: coordinate.longitude + tolerance,
                        y: coordinate.latitude + tolerance,
                        projection: projection),
                ])!

        case .epsg3857, .epsg4326, .epsg4978:
            return BoundingBox(
                coordinates: [
                    Coordinate3D(
                        x: coordinate.longitude,
                        y: coordinate.latitude,
                        projection: projection),
                    Coordinate3D(
                        x: coordinate.longitude,
                        y: coordinate.latitude,
                        projection: projection),
                ],
                padding: tolerance)!
                .clamped()
        }
    }

}
