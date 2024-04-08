#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools
import struct GISTools.Polygon
import Logging

// MARK: Reading vector tiles

extension VectorTile {

    static func vectorTile(from data: Data) -> VectorTile_Tile? {
        var data = data
        if data.isGzipped {
            data = (try? data.gunzipped()) ?? data
        }

        return try? VectorTile_Tile(serializedData: data)
    }

    static func loadTileFrom(
        data: Data,
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        layerWhitelist: Set<String>?,
        logger: Logger?)
        -> [String: LayerContainer]?
    {
        if data.isGzipped {
            (logger ?? VectorTile.logger)?.info("\(z)/\(x)/\(y): Input data is gzipped")
        }

        guard let tile = vectorTile(from: data) else {
            (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Failed to create a vector tile from data")
            return nil
        }

        var layers: [String: LayerContainer] = [:]

        var lastExtent: Int = 0
        var projectionFunction: ((_ x: Int, _ y: Int) -> Coordinate3D) = passThroughFromTile

        for layer in tile.layers {
            guard (layerWhitelist?.contains(layer.name) ?? true) else { continue }

            let name: String = layer.name
            let extent: Int = Int(layer.extent)
            let version: Int = Int(layer.version)

            if extent != lastExtent {
                lastExtent = extent

                switch projection {
                case .noSRID:
                    projectionFunction = passThroughFromTile
                case .epsg3857:
                    projectionFunction = projectToEpsg3857(x: x, y: y, z: z, extent: extent)
                case .epsg4326:
                    projectionFunction = projectToEpsg4326(x: x, y: y, z: z, extent: extent)
                }
            }

            switch version {
            case 2:
                let layerFeatures: [Feature] = parseVersion2(layer: layer, projectionFunction: projectionFunction)
                let boundingBoxes: [BoundingBox] = layerFeatures.compactMap({ $0.boundingBox })

                var layerBoundingBox: BoundingBox?
                if !boundingBoxes.isEmpty {
                    layerBoundingBox = boundingBoxes.reduce(boundingBoxes[0], +)
                }

                layers[name] = LayerContainer(
                    features: layerFeatures,
                    boundingBox: layerBoundingBox)

            default:
                (logger ?? VectorTile.logger)?.info("\(z)/\(x)/\(y): Layer \(name) has unknown version \(version)")
            }
        }

        return layers
    }

    static func parseVersion2(
        layer: VectorTile_Tile.Layer,
        projectionFunction: ((_ x: Int, _ y: Int) -> Coordinate3D))
        -> [Feature]
    {
        let keys: [String] = layer.keys

        // Note: Some of the more obscure data types are converted
        // to common types so that users don't trip over conversion issues
        let values: [Any] = layer.values.map { (value) in
            if value.hasStringValue {
                let string = value.stringValue

                // Maybe an encoded JSON object?
                if string.hasPrefix("[") || string.hasPrefix("{"),
                    let data = string.data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data)
                {
                    return object
                }

                return string
            }
            else if value.hasIntValue {
                return Int64(value.intValue)
            }
            else if value.hasBoolValue {
                return value.boolValue
            }
            else if value.hasDoubleValue {
                return value.doubleValue
            }
            else if value.hasFloatValue {
                return Double(value.floatValue)
            }
            else if value.hasUintValue {
                return UInt64(value.uintValue)
            }
            else if value.hasSintValue {
                return Int64(value.sintValue)
            }
            else {
                return ""
            }
        }

        var layerFeatures: [Feature] = []
        layerFeatures.reserveCapacity(layer.features.count)

        for feature in layer.features {
            guard var layerFeature: Feature = convertToLayerFeature(geometryIntegers: feature.geometry, ofType: feature.type, projectionFunction: projectionFunction) else { continue }

            var properties: [String: Any] = [:]
            for tags in feature.tags.pairs() {
                guard let key: String = keys.get(at: Int(tags.first)),
                      let value: Any = values.get(at: Int(tags.second))
                else { continue }

                properties[key] = value
            }
            layerFeature.properties = properties

            if feature.hasID {
                layerFeature.id = Feature.Identifier(value: feature.id)
            }
            else {
                layerFeature.id = .string(UUID().uuidString)
            }

            layerFeatures.append(layerFeature)
        }

        return layerFeatures
    }

    static func convertToLayerFeature(
        geometryIntegers: [UInt32],
        ofType featureType: VectorTile_Tile.GeomType,
        projectionFunction: ((_ x: Int, _ y: Int) -> Coordinate3D))
        -> Feature?
    {
        let multiCoordinates: [[Coordinate3D]] = multiCoordinatesFrom(
            geometryIntegers: geometryIntegers,
            ofType: featureType,
            projectionFunction: projectionFunction)

        guard !multiCoordinates.isEmpty else { return nil }

        var feature: Feature?

        switch featureType {
        case .point:
            if multiCoordinates.count == 1,
                let coordinate = multiCoordinates.first?.first
            {
                feature = Feature(Point(coordinate), calculateBoundingBox: true)
            }
            else {
                let flattened: [Coordinate3D] = Array(multiCoordinates.joined())
                guard let multiPoint = MultiPoint(flattened) else { return nil }
                feature = Feature(multiPoint, calculateBoundingBox: true)
            }

        case .linestring:
            if multiCoordinates.count == 1 {
                let coordinates = multiCoordinates[0]
                guard let lineString = LineString(coordinates) else { return nil }
                feature = Feature(lineString, calculateBoundingBox: true)
            }
            else {
                guard let multiLineString = MultiLineString(multiCoordinates) else { return nil }
                feature = Feature(multiLineString, calculateBoundingBox: true)
            }

        case .polygon:
            if multiCoordinates.count == 1 {
                if let polygon = Polygon(multiCoordinates) {
                    feature = Feature(polygon, calculateBoundingBox: true)
                }
            }
            else {
                var polygons: [Polygon] = []

                let rings: [Ring] = multiCoordinates.compactMap { Ring($0) }
                var currentRings: [Ring] = []

                for ring in rings {
                    if ring.isUnprojectedClockwise, !currentRings.isEmpty {
                        polygons.append(ifNotNil: Polygon(currentRings.map({ $0.coordinates })))
                        currentRings = []
                    }
                    currentRings.append(ring)
                }

                if !currentRings.isEmpty {
                    polygons.append(ifNotNil: Polygon(currentRings.map({ $0.coordinates })))
                }

                if let multiPolygon = MultiPolygon(polygons.map({ $0.coordinates })) {
                    feature = Feature(multiPolygon, calculateBoundingBox: true)
                }
            }

        default:
            break
        }

        return feature
    }

    private static let commandIdMoveTo: UInt32 = 1
    private static let commandIdLineTo: UInt32 = 2
    private static let commandIdClosePath: UInt32 = 7

    static func multiCoordinatesFrom(
        geometryIntegers: [UInt32],
        ofType featureType: VectorTile_Tile.GeomType,
        projectionFunction: ((_ x: Int, _ y: Int) -> Coordinate3D))
        -> [[Coordinate3D]]
    {
        var x: Int = 0
        var y: Int = 0

        var commandId: UInt32 = 0
        var commandCount: Int = 0

        var coordinates: [Coordinate3D] = []
        var result: [[Coordinate3D]] = []

        var index: Int = 0
        let geometryCount: Int = geometryIntegers.count

        while index < geometryCount {
            let commandInteger: UInt32 = geometryIntegers[index]
            index += 1

            commandId = commandInteger & 0x7
            commandCount = Int(commandInteger >> 3)

            // ClosePath has no parameter
            if commandId == VectorTile.commandIdClosePath {
                guard featureType != .point,
                      commandCount == 1,
                      coordinates.count > 1
                else {
                    break
                }

                coordinates.append(coordinates[0])

                continue
            }

            // Else: MoveTo or LineTo, with parameters
            guard index + (commandCount * 2) <= geometryCount else { break }

            coordinates.reserveCapacity(commandCount * 2)

            for _ in 0 ..< commandCount {
                defer { index += 2 }

                let dx: UInt32 = geometryIntegers[index]
                let dy: UInt32 = geometryIntegers[index + 1]

                x += VectorTile.zigZagDecode(Int(dx))
                y += VectorTile.zigZagDecode(Int(dy))

                if commandId == VectorTile.commandIdMoveTo,
                    !coordinates.isEmpty
                {
                    result.append(coordinates)
                    coordinates = []
                    coordinates.reserveCapacity(commandCount * 2)
                }

                coordinates.append(projectionFunction(x, y))
            }
        }

        if !coordinates.isEmpty {
            result.append(coordinates)
        }

        return result
    }

    private static func zigZagDecode(_ n: Int) -> Int {
        return (n >> 1) ^ (-(n & 1))
    }

    // MARK: - Projections

    static func passThroughFromTile(
        x: Int,
        y: Int)
        -> Coordinate3D
    {
        return Coordinate3D(x: Double(x), y: Double(y), projection: .noSRID)
    }

    static func projectToEpsg3857(
        x: Int,
        y: Int,
        z: Int,
        extent: Int)
        -> ((Int, Int) -> Coordinate3D)
    {
        let extent: Double = Double(extent)
        let bounds = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)

        let topLeft = Coordinate3D(x: bounds.southWest.x, y: bounds.northEast.y)
        let xSpan: Double = abs(bounds.northEast.x - bounds.southWest.x)
        let ySpan: Double = abs(bounds.northEast.y - bounds.southWest.y)

        return { (x, y) -> Coordinate3D in
            let projectedX = topLeft.x + ((Double(x) / extent) * xSpan)
            let projectedY = topLeft.y - ((Double(y) / extent) * ySpan)
            return Coordinate3D(x: projectedX, y: projectedY)
        }
    }

    // Note: Need to project 4326 to 3857 first
    static func projectToEpsg4326(
        x: Int,
        y: Int,
        z: Int,
        extent: Int)
        -> ((Int, Int) -> Coordinate3D)
    {
        let extent: Double = Double(extent)
        let bounds = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)

        let topLeft = Coordinate3D(x: bounds.southWest.x, y: bounds.northEast.y)
        let xSpan: Double = abs(bounds.northEast.x - bounds.southWest.x)
        let ySpan: Double = abs(bounds.northEast.y - bounds.southWest.y)

        return { (x, y) -> Coordinate3D in
            let projectedX = topLeft.x + ((Double(x) / extent) * xSpan)
            let projectedY = topLeft.y - ((Double(y) / extent) * ySpan)
            return Coordinate3D(x: projectedX, y: projectedY).projected(to: .epsg4326)
        }
    }

}
