#if !os(Linux)
    import CoreLocation
#endif
import Foundation
import GISTools

// MARK: GeoJSON write support

extension VectorTile {

    /// Export the tile's content as GeoJSON
    public func toGeoJson(
        layerNames: [String] = [],
        additionalFeatureProperties: [String: Sendable]? = nil,
        prettyPrinted: Bool = false,
        layerProperty: String? = VectorTile.defaultLayerPropertyName)
        -> Data?
    {
        var allFeatures: [Feature] = []

        for (layerName, layerContainer) in layers {
            if !layerNames.isEmpty, !layerNames.contains(layerName) { continue }

            for feature in layerContainer.features {
                var feature = feature
                if let layerProperty {
                    feature.setProperty(layerName, for: layerProperty)
                }
                if let additionalFeatureProperties {
                    feature.properties.merge(additionalFeatureProperties, uniquingKeysWith: { (current, _) in current })
                }
                allFeatures.append(feature)
            }
        }

        let json = FeatureCollection(allFeatures).asJson

        var options: JSONSerialization.WritingOptions = []
        if prettyPrinted {
            options.insert(.prettyPrinted)
        }
        return try? JSONSerialization.data(withJSONObject: json, options: options)
    }

    /// Write the tile's content as GeoJSON to `url`
    @discardableResult
    public func writeGeoJson(
        to url: URL,
        layerNames: [String] = [],
        additionalFeatureProperties: [String: Sendable]? = nil,
        prettyPrinted: Bool = false,
        layerProperty: String? = VectorTile.defaultLayerPropertyName)
        -> Bool
    {
        guard let data: Data = toGeoJson(
            layerNames: layerNames,
            additionalFeatureProperties: additionalFeatureProperties,
            prettyPrinted: prettyPrinted,
            layerProperty: layerProperty)
        else { return false }

        do {
            try data.write(to: url)
        }
        catch {
            return false
        }

        return true
    }

    // MARK: - GeoJSON support

    /// Add some GeoJSON to this tile
    public mutating func addGeoJson(
        geoJson: GeoJson,
        layerName: String? = nil,
        layerProperty: String? = nil,
        layerAllowList: Set<String>? = nil)
    {
        guard let features = geoJson.flattened?.features else { return }

        let layerName = layerName ?? "Layer-\(layerNames.count)"

        if let layerProperty {
            features.divided(
                byKey: { feature in
                    let mapping: String = feature.property(for: layerProperty) ?? layerName
                    return mapping
                },
                onKey: { key, features in
                    if let layerAllowList, !layerAllowList.contains(key) { return }
                    appendFeatures(
                        features.map({ feature in
                            var feature = feature
                            feature.removeProperty(for: layerProperty)
                            return feature
                        }),
                        to: key)
                })
        }
        else {
            if let layerAllowList, !layerAllowList.contains(layerName) { return }
            appendFeatures(features, to: layerName)
        }
    }

    /// Replace some GeoJSON in this tile
    public mutating func setGeoJson(
        geoJson: GeoJson,
        layerName: String? = nil,
        layerProperty: String? = nil,
        layerAllowList: Set<String>? = nil)
    {
        guard let features = geoJson.flattened?.features else { return }

        let layerName = layerName ?? "Layer-\(layerNames.count)"

        if let layerProperty {
            features.divided(
                byKey: { feature in
                    let mapping: String = feature.property(for: layerProperty) ?? layerName
                    return mapping
                },
                onKey: { key, features in
                    if let layerAllowList, !layerAllowList.contains(key) { return }
                    setFeatures(
                        features.map({ feature in
                            var feature = feature
                            feature.removeProperty(for: layerProperty)
                            return feature
                        }),
                        for: key)
                })
        }
        else {
            if let layerAllowList, !layerAllowList.contains(layerName) { return }
            setFeatures(features, for: layerName)
        }
    }

}
