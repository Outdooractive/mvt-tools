#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools

extension VectorTile {

    // MARK: - GeoJSON write support

    public func toGeoJson(
        layerNames: [String] = [],
        prettyPrinted: Bool = false)
        -> Data?
    {
        var allFeatures: [Feature] = []

        for (layerName, layerContainer) in layers {
            if !layerNames.isEmpty, !layerNames.contains(layerName) { continue }

            for feature in layerContainer.features {
                var feature = feature
                feature.setProperty(layerName, for: "vt_layer")
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

    @discardableResult
    public func writeGeoJson(
        to url: URL,
        layerNames: [String] = [],
        prettyPrinted: Bool = false)
        -> Bool
    {
        guard let data: Data = self.toGeoJson(layerNames: layerNames, prettyPrinted: prettyPrinted) else { return false }

        do {
            try data.write(to: url)
        }
        catch {
            return false
        }

        return true
    }

    // MARK: - GeoJSON support

    public mutating func addGeoJson(geoJson: GeoJson, layerName: String? = nil) {
        guard let features = geoJson.flattened?.features else { return }

        let layerName = layerName ?? "Layer-\(layerNames.count)"
        appendFeatures(features, to: layerName)
    }

    public mutating func setGeoJson(geoJson: GeoJson, layerName: String? = nil) {
        guard let features = geoJson.flattened?.features else { return }

        let layerName = layerName ?? "Layer-\(layerNames.count)"
        setFeatures(features, for: layerName)
    }

}
