import Foundation
import GISTools

// MARK: GeoJSON support

extension VectorTile {

    /// Add features from a ``GeoJson`` object to this tile.
    ///
    /// - Parameter geoJson: The source GeoJSON data.
    /// - Parameter layerName: The target layer name. When `nil`, a layer name is auto-generated.
    /// - Parameter layerProperty: When set, features are divided into layers based on the value of this property,
    ///   and the property is stripped from each feature after routing.
    /// - Parameter layerAllowlist: When non-nil, only layers whose names appear in this set receive features.
    public mutating func addGeoJson(
        geoJson: GeoJson,
        layerName: String? = nil,
        layerProperty: String? = nil,
        layerAllowlist: Set<String>? = nil
    ) {
        guard let features = geoJson.flattened?.features else { return }

        let layerName = layerName ?? "Layer-\(layerNames.count)"

        if let layerProperty {
            features.divided(
                byKey: { feature in
                    let mapping: String = feature.property(for: layerProperty) ?? layerName
                    return mapping
                },
                onKey: { key, features in
                    if let layerAllowlist, !layerAllowlist.contains(key) { return }
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
            if let layerAllowlist, !layerAllowlist.contains(layerName) { return }
            appendFeatures(features, to: layerName)
        }
    }

    /// Replace all features in this tile with those from a ``GeoJson`` object.
    ///
    /// Unlike ``addGeoJson(geoJson:layerName:layerProperty:layerAllowlist:)``,
    /// this method clears existing features from each target layer before adding the new ones.
    ///
    /// - Parameter geoJson: The source GeoJSON data.
    /// - Parameter layerName: The target layer name. When `nil`, a layer name is auto-generated.
    /// - Parameter layerProperty: When set, features are divided into layers based on the value of this property,
    ///   and the property is stripped from each feature after routing.
    /// - Parameter layerAllowlist: When non-nil, only layers whose names appear in this set receive features.
    public mutating func setGeoJson(
        geoJson: GeoJson,
        layerName: String? = nil,
        layerProperty: String? = nil,
        layerAllowlist: Set<String>? = nil
    ) {
        guard let features = geoJson.flattened?.features else { return }

        let layerName = layerName ?? "Layer-\(layerNames.count)"

        if let layerProperty {
            features.divided(
                byKey: { feature in
                    let mapping: String = feature.property(for: layerProperty) ?? layerName
                    return mapping
                },
                onKey: { key, features in
                    if let layerAllowlist, !layerAllowlist.contains(key) { return }
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
            if let layerAllowlist, !layerAllowlist.contains(layerName) { return }
            setFeatures(features, for: layerName)
        }
    }

}
