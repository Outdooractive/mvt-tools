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
        prettyPrinted: Bool = false)
        -> Data?
    {
        var allFeatures: [Feature] = []

        for (layerName, layerContainer) in layers {
            if !layerNames.isEmpty, !layerNames.contains(layerName) { continue }

            for feature in layerContainer.features {
                var feature = feature
                feature.setProperty(layerName, for: "vt_layer")
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
        prettyPrinted: Bool = false)
        -> Bool
    {
        guard let data: Data = toGeoJson(
            layerNames: layerNames,
            additionalFeatureProperties: additionalFeatureProperties,
            prettyPrinted: prettyPrinted)
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
        propertyName: String? = nil)
    {
        guard let features = geoJson.flattened?.features else { return }

        let layerName = layerName ?? "Layer-\(layerNames.count)"

        if let propertyName {
            features.divided(
                byKey: { feature in
                    let mapping: String = feature.property(for: propertyName) ?? layerName
                    return mapping
                },
                onKey: { key, features in
                    appendFeatures(features, to: key)
                })
        }
        else {
            appendFeatures(features, to: layerName)
        }
    }

    /// Replace some GeoJSON in this tile
    public mutating func setGeoJson(
        geoJson: GeoJson,
        layerName: String? = nil,
        propertyName: String? = nil)
    {
        guard let features = geoJson.flattened?.features else { return }

        let layerName = layerName ?? "Layer-\(layerNames.count)"

        if let propertyName {
            features.divided(
                byKey: { feature in
                    let mapping: String = feature.property(for: propertyName) ?? layerName
                    return mapping
                },
                onKey: { key, features in
                    setFeatures(features, for: key)
                })
        }
        else {
            setFeatures(features, for: layerName)
        }
    }

}
