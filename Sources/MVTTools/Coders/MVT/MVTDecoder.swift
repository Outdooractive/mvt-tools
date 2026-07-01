#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
import struct GISTools.Polygon
import Logging

// MARK: Reading vector tiles

enum MVTDecoder {

    /// Deserializes raw MVT protocol buffer data into a ``VectorTile_Tile``.
    ///
    /// Automatically decompresses gzipped input before deserializing.
    ///
    /// - Parameter mvtData: The raw MVT protobuf bytes, optionally gzip-compressed.
    /// - Returns: A decoded ``VectorTile_Tile``, or `nil` if deserialization fails.
    static func vectorTile(from mvtData: Data) -> VectorTile_Tile? {
        var data = mvtData
        if data.isGzipped {
            data = (try? data.gunzipped()) ?? data
        }

        return try? VectorTile_Tile(serializedBytes: data)
    }

    /// Decodes all layers from MVT data into ``VectorTile.LayerContainer`` values.
    ///
    /// This is the main entry point for reading a vector tile. It decompresses the data,
    /// deserializes the protobuf, and parses each layer's features into the appropriate
    /// projection.
    ///
    /// - Parameters:
    ///   - mvtData: The raw MVT protobuf bytes.
    ///   - x: The tile column index.
    ///   - y: The tile row index.
    ///   - z: The tile zoom level.
    ///   - projection: The target projection for coordinates (default: ``Projection/epsg4326``).
    ///   - layerAllowlist: An optional set of layer names to include; `nil` includes all layers.
    ///   - calculateBoundingBox: When `true`, calculate a bounding box for each feature.
    ///   - logger: An optional ``Logger`` for diagnostic messages.
    /// - Returns: A dictionary mapping layer names to their ``VectorTile.LayerContainer``,
    ///   or `nil` if the data could not be decoded.
    static func layers(
        from mvtData: Data,
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        layerAllowlist: Set<String>?,
        calculateBoundingBox: Bool = false,
        logger: Logger?
    ) -> [String: VectorTile.LayerContainer]? {
        if mvtData.isGzipped {
            (logger ?? VectorTile.logger)?.info("\(z)/\(x)/\(y): Input data is gzipped")
        }

        guard let tile = vectorTile(from: mvtData) else {
            (logger ?? VectorTile.logger)?.warning("\(z)/\(x)/\(y): Failed to create a vector tile from data")
            return nil
        }

        var layers: [String: VectorTile.LayerContainer] = [:]

        var lastExtent = 0
        var projectionFunction: ((_ x: Int, _ y: Int) -> Coordinate3D) = Projections.passThroughFromTile(x: 0, y: 0)

        for layer in tile.layers {
            guard (layerAllowlist?.contains(layer.name) ?? true) else { continue }

            let name: String = layer.name
            let extent = Int(layer.extent)
            let version = Int(layer.version)

            if extent != lastExtent {
                lastExtent = extent
                projectionFunction = Projections.forwardProjection(
                    for: projection, x: x, y: y, z: z, extent: extent)
            }

            switch version {
            case 2:
                let layerFeatures: [Feature] = parseVersion2(
                    layer: layer,
                    projectionFunction: projectionFunction,
                    calculateBoundingBox: calculateBoundingBox)
                let boundingBoxes: [BoundingBox] = layerFeatures.compactMap({ $0.boundingBox })

                var layerBoundingBox: BoundingBox?
                if boundingBoxes.isNotEmpty {
                    layerBoundingBox = boundingBoxes.reduce(boundingBoxes[0], +)
                }

                layers[name] = VectorTile.LayerContainer(
                    features: layerFeatures,
                    boundingBox: layerBoundingBox)

            default:
                (logger ?? VectorTile.logger)?.info("\(z)/\(x)/\(y): Layer \(name) has unknown version \(version)")
            }
        }

        return layers
    }

    /// Parses a version-2 MVT layer into an array of ``Feature`` values.
    ///
    /// Decodes the protobuf geometry, extracts property key/value pairs, and assigns
    /// a unique identifier to each feature.
    ///
    /// - Parameters:
    ///   - layer: The protobuf ``VectorTile_Tile.Layer`` to parse.
    ///   - projectionFunction: A closure that converts tile-local (x, y) integers to
    ///     ``Coordinate3D`` in the target projection.
    ///   - calculateBoundingBox: When `true`, calculate a bounding box for each feature.
    /// - Returns: An array of decoded ``Feature`` values.
    static func parseVersion2(
        layer: VectorTile_Tile.Layer,
        projectionFunction: ((_ x: Int, _ y: Int) -> Coordinate3D),
        calculateBoundingBox: Bool
    ) -> [Feature] {
        let (keys, values) = keysAndValues(forLayer: layer)

        var layerFeatures: [Feature] = []
        layerFeatures.reserveCapacity(layer.features.count)

        for feature in layer.features {
            guard var layerFeature: Feature = convertToLayerFeature(
                geometryIntegers: feature.geometry,
                ofType: feature.type,
                projectionFunction: projectionFunction,
                calculateBoundingBox: calculateBoundingBox)
            else { continue }

            var properties: [String: Sendable] = [:]
            for tags in feature.tags.pairs() {
                guard let key: String = keys.get(at: Int(tags.first)),
                      let value: Sendable = values.get(at: Int(tags.second))
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

    /// Extracts the key and value arrays from a protobuf layer.
    ///
    /// Property values are converted from their protobuf representation to common Swift
    /// types. JSON-encoded strings (arrays and dictionaries) are deserialized transparently.
    ///
    /// - Parameter layer: The protobuf layer to extract from.
    /// - Returns: A tuple of parallel `keys` and `values` arrays.
    static func keysAndValues(
        forLayer layer: VectorTile_Tile.Layer
    ) -> (keys: [String], values: [Sendable]) {
        let keys: [String] = layer.keys

        // Note: Some of the more obscure data types are converted
        // to common types so that users don't trip over conversion issues
        let values: [Sendable] = layer.values.map { (value) in
            if value.hasStringValue {
                let string = value.stringValue

                // Maybe an encoded JSON object?
                if string.hasPrefix("["),
                   let data = string.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [Sendable]
                {
                    return object
                }
                if string.hasPrefix("{"),
                   let data = string.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Sendable]
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

        return (keys, values)
    }

    /// Converts raw geometry integers and a protobuf geometry type into a ``Feature``.
    ///
    /// Decodes the integer command stream into ``Coordinate3D`` values and constructs
    /// the appropriate ``GISTools`` geometry (``Point``, ``MultiPoint``, ``LineString``,
    /// ``MultiLineString``, ``Polygon``, or ``MultiPolygon``).
    ///
    /// - Parameters:
    ///   - geometryIntegers: The raw protobuf geometry integer array.
    ///   - featureType: The protobuf geometry type (point, linestring, polygon).
    ///   - projectionFunction: A closure that converts tile-local (x, y) integers to
    ///     ``Coordinate3D`` in the target projection.
    /// - Returns: A ``Feature`` with the decoded geometry, or `nil` if decoding fails.
    static func convertToLayerFeature(
        geometryIntegers: [UInt32],
        ofType featureType: VectorTile_Tile.GeomType,
        projectionFunction: ((_ x: Int, _ y: Int) -> Coordinate3D),
        calculateBoundingBox: Bool
    ) -> Feature? {
        let multiCoordinates: [[Coordinate3D]] = multiCoordinatesFrom(
            geometryIntegers: geometryIntegers,
            ofType: featureType,
            projectionFunction: projectionFunction)

        guard multiCoordinates.isNotEmpty else { return nil }

        var feature: Feature?

        switch featureType {
        case .point:
            if multiCoordinates.count == 1,
               let coordinate = multiCoordinates.first?.first
            {
                feature = Feature(Point(coordinate), calculateBoundingBox: calculateBoundingBox)
            }
            else {
                let flattened: [Coordinate3D] = Array(multiCoordinates.joined())
                guard let multiPoint = MultiPoint(flattened) else { return nil }
                feature = Feature(multiPoint, calculateBoundingBox: calculateBoundingBox)
            }

        case .linestring:
            if multiCoordinates.count == 1 {
                let coordinates = multiCoordinates[0]
                guard let lineString = LineString(coordinates) else { return nil }
                feature = Feature(lineString, calculateBoundingBox: calculateBoundingBox)
            }
            else {
                guard let multiLineString = MultiLineString(multiCoordinates) else { return nil }
                feature = Feature(multiLineString, calculateBoundingBox: calculateBoundingBox)
            }

        case .polygon:
            if multiCoordinates.count == 1 {
                if let polygon = Polygon(multiCoordinates) {
                    feature = Feature(polygon, calculateBoundingBox: calculateBoundingBox)
                }
            }
            else {
                var polygons: [Polygon] = []

                let rings: [Ring] = multiCoordinates.compactMap { Ring($0) }
                var currentRings: [Ring] = []

                for ring in rings {
                    if ring.isUnprojectedClockwise, currentRings.isNotEmpty {
                        polygons.append(ifNotNil: Polygon(currentRings.map({ $0.coordinates })))
                        currentRings = []
                    }
                    currentRings.append(ring)
                }

                if currentRings.isNotEmpty {
                    polygons.append(ifNotNil: Polygon(currentRings.map({ $0.coordinates })))
                }

                if let multiPolygon = MultiPolygon(polygons.map({ $0.coordinates })) {
                    feature = Feature(multiPolygon, calculateBoundingBox: calculateBoundingBox)
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

    /// Decodes a raw MVT geometry integer stream into an array of coordinate arrays.
    ///
    /// Interprets MoveTo, LineTo, and ClosePath commands using zigzag decoding and
    /// applies the projection function to each coordinate.
    ///
    /// - Parameters:
    ///   - geometryIntegers: The raw protobuf geometry integer array.
    ///   - featureType: The protobuf geometry type (used to validate ClosePath).
    ///   - projectionFunction: A closure that converts tile-local (x, y) integers to
    ///     ``Coordinate3D`` in the target projection.
    /// - Returns: An array of coordinate rings, where each ring is an array of ``Coordinate3D``.
    static func multiCoordinatesFrom(
        geometryIntegers: [UInt32],
        ofType featureType: VectorTile_Tile.GeomType,
        projectionFunction: ((_ x: Int, _ y: Int) -> Coordinate3D)
    ) -> [[Coordinate3D]] {
        var x = 0
        var y = 0

        var commandId: UInt32 = 0
        var commandCount = 0

        var coordinates: [Coordinate3D] = []
        var result: [[Coordinate3D]] = []

        var index = 0
        let geometryCount: Int = geometryIntegers.count

        while index < geometryCount {
            let commandInteger: UInt32 = geometryIntegers[index]
            index += 1

            commandId = commandInteger & 0x7
            commandCount = Int(commandInteger >> 3)

            // ClosePath has no parameter
            if commandId == MVTDecoder.commandIdClosePath {
                guard featureType != .point,
                      commandCount == 1,
                      coordinates.count > 1
                else { break }

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

                x += MVTDecoder.zigZagDecode(Int(dx))
                y += MVTDecoder.zigZagDecode(Int(dy))

                if commandId == MVTDecoder.commandIdMoveTo,
                   coordinates.isNotEmpty
                {
                    result.append(coordinates)
                    coordinates = []
                    coordinates.reserveCapacity(commandCount * 2)
                }

                coordinates.append(projectionFunction(x, y))
            }
        }

        if coordinates.isNotEmpty {
            result.append(coordinates)
        }

        return result
    }

    private static func zigZagDecode(_ n: Int) -> Int {
        (n >> 1) ^ (-(n & 1))
    }

}
