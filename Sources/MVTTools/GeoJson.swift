#if !os(Linux)
    import CoreLocation
#endif
import Foundation
import GISTools
import Gzip

// MARK: GeoJSON write support

extension VectorTile {

    /// Export the tile's content as GeoJSON
    public func toGeoJson(
        layerNames: [String] = [],
        additionalFeatureProperties: [String: Sendable]? = nil,
        prettyPrinted: Bool = false,
        layerProperty: String? = nil,
        options: VectorTile.ExportOptions? = nil)
        -> Data?
    {
        var simplifyDistance: CLLocationDistance = 0.0
        var clipBoundingBox: BoundingBox?

        if let options {
            var bufferSize = 0
            switch options.bufferSize {
            case .no:
                bufferSize = 0
            case let .extent(extent):
                bufferSize = extent
            case let .pixel(pixel):
                bufferSize = Int((Double(pixel) / Double(VectorTile.ExportOptions.tileSize)) * Double(VectorTile.ExportOptions.extent))
            }

            switch options.simplifyFeatures {
            case .no:
                simplifyDistance = 0.0
            case let .extent(extent):
                let tileBoundsInMeters = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)
                simplifyDistance = (tileBoundsInMeters.southEast.longitude - tileBoundsInMeters.southWest.longitude) / Double(VectorTile.ExportOptions.extent) * Double(extent)
            case let .meters(meters):
                simplifyDistance = meters
            }

            if bufferSize != 0 {
                clipBoundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg4326)

                if let boundingBoxToExpand = clipBoundingBox {
                    let sqrt2 = 2.0.squareRoot()
                    let diagonal = Double(VectorTile.ExportOptions.extent) * sqrt2
                    let bufferDiagonal = Double(bufferSize) * sqrt2
                    let factor = bufferDiagonal / diagonal

                    let diagonalLength = boundingBoxToExpand.southWest.distance(from: boundingBoxToExpand.northEast)
                    let distance = diagonalLength * factor

                    clipBoundingBox = boundingBoxToExpand.expanded(byDistance: distance)
                }
            }
        }

        var allFeatures: [Feature] = []

        for (layerName, layerContainer) in layers {
            if !layerNames.isEmpty, !layerNames.contains(layerName) { continue }

            let layerFeatures: [Feature] = if let clipBoundingBox {
                if simplifyDistance > 0.0 {
                    layerContainer.features.compactMap({ $0.clipped(to: clipBoundingBox)?.simplified(tolerance: simplifyDistance) })
                }
                else {
                    layerContainer.features.compactMap({ $0.clipped(to: clipBoundingBox) })
                }
            }
            else if simplifyDistance > 0.0 {
                layerContainer.features.compactMap({ $0.simplified(tolerance: simplifyDistance) })
            }
            else {
                layerContainer.features
            }

            for feature in layerFeatures {
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

        var jsonOptions: JSONSerialization.WritingOptions = []
        if prettyPrinted {
            jsonOptions.insert(.prettyPrinted)
        }

        let serializedData = try? JSONSerialization.data(withJSONObject: json, options: jsonOptions)

        if let options,
           options.compression != .no,
           let serializedData
        {
            var value = 6 // default
            if case let .level(compressionLevel) = options.compression {
                value = max(0, min(9, compressionLevel))
            }
            let level = CompressionLevel(rawValue: Int32(value))
            return (try? serializedData.gzipped(level: level)) ?? serializedData
        }
        else {
            return serializedData
        }
    }

    /// Write the tile's content as GeoJSON to `url`
    @discardableResult
    public func writeGeoJson(
        to url: URL,
        layerNames: [String] = [],
        additionalFeatureProperties: [String: Sendable]? = nil,
        prettyPrinted: Bool = false,
        layerProperty: String? = nil,
        options: VectorTile.ExportOptions? = nil)
        -> Bool
    {
        guard let data: Data = toGeoJson(
            layerNames: layerNames,
            additionalFeatureProperties: additionalFeatureProperties,
            prettyPrinted: prettyPrinted,
            layerProperty: layerProperty,
            options: options)
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
