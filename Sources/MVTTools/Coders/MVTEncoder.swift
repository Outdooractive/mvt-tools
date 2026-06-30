#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
import struct GISTools.Polygon
import Gzip

// MARK: Writing vector tiles

enum MVTEncoder {

    /// Encodes layers into MVT protocol buffer data, with optional clipping, simplification,
    /// buffering, and compression.
    ///
    /// This is the main entry point for writing a vector tile. It projects each feature's
    /// coordinates, optionally clips and simplifies them, serializes to protobuf, and
    /// applies gzip compression if requested.
    ///
    /// - Parameters:
    ///   - layers: A dictionary of layer names to their ``VectorTile.LayerContainer``.
    ///   - x: The tile column index.
    ///   - y: The tile row index.
    ///   - z: The tile zoom level.
    ///   - projection: The source projection of the input coordinates (default: ``Projection/epsg4326``).
    ///   - options: Export options controlling buffer size, simplification, and compression.
    /// - Returns: The serialized MVT protobuf bytes (optionally gzip-compressed), or `nil` on failure.
    static func mvtDataFor(
        layers: [String: VectorTile.LayerContainer],
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        options: VectorTile.ExportOptions
    ) -> Data? {
        var tile = VectorTile_Tile()

        let extent = UInt32(VectorTile.ExportOptions.extent)
        let projectionFunction: ((Coordinate3D) -> (x: Int, y: Int))
        var clipBoundingBox: BoundingBox?

        switch projection {
        case .noSRID:
            projectionFunction = passThroughToTile()
        case .epsg3857:
            projectionFunction = projectFromEpsg3857(x: x, y: y, z: z, extent: Int(extent))
            clipBoundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)
        case .epsg4326:
            projectionFunction = projectFromEpsg4326(x: x, y: y, z: z, extent: Int(extent))
            clipBoundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg4326)
        case .epsg4978:
            projectionFunction = projectFromEpsg4978(x: x, y: y, z: z, extent: Int(extent))
            clipBoundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg4978)
        }

        var bufferSize = 0
        switch options.bufferSize {
        case .no:
            bufferSize = 0
        case let .extent(extent):
            bufferSize = extent
        case let .pixel(pixel):
            bufferSize = Int((Double(pixel) / Double(VectorTile.ExportOptions.tileSize)) * Double(VectorTile.ExportOptions.extent))
        }

        var simplifyDistance: CLLocationDistance = 0.0
        switch options.simplifyFeatures {
        case .no:
            simplifyDistance = 0.0
        case let .extent(extent):
            let tileBoundsInMeters = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)
            simplifyDistance = (tileBoundsInMeters.southEast.longitude - tileBoundsInMeters.southWest.longitude) / Double(VectorTile.ExportOptions.extent) * Double(extent)
        case let .meters(meters):
            simplifyDistance = meters
        }

        if bufferSize != 0,
           let boundingBoxToExpand = clipBoundingBox
        {
            let sqrt2 = 2.0.squareRoot()
            let diagonal = Double(extent) * sqrt2
            let bufferDiagonal = Double(bufferSize) * sqrt2
            let factor = bufferDiagonal / diagonal

            let diagonalLength = boundingBoxToExpand.southWest.distance(from: boundingBoxToExpand.northEast)
            let distance = diagonalLength * factor

            clipBoundingBox = boundingBoxToExpand.expanded(byDistance: distance)
        }

        var vectorTileLayers: [VectorTile_Tile.Layer] = []

        for (layerName, layerContainer) in layers {
            let layerFeatures: [Feature] = if let clippedToBoundingBox = clipBoundingBox {
                if simplifyDistance > 0.0 {
                    layerContainer.features.compactMap({ $0.clipped(to: clippedToBoundingBox)?.simplified(tolerance: simplifyDistance) })
                }
                else {
                    layerContainer.features.compactMap({ $0.clipped(to: clippedToBoundingBox) })
                }
            }
            else {
                layerContainer.features
            }

            var layer: VectorTile_Tile.Layer = encodeVersion2(
                features: layerFeatures,
                extent: extent,
                projectionFunction: projectionFunction)
            layer.name = layerName

            vectorTileLayers.append(layer)
        }

        tile.layers = vectorTileLayers

        let serializedData = try? tile.serializedData()

        if options.compression != .no,
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

    /// Encodes a collection of ``Feature`` values into a version-2 protobuf layer.
    ///
    /// Deduplicates property keys and values across features and assigns them
    /// integer indices in the layer's key/value tables.
    ///
    /// - Parameters:
    ///   - features: The features to encode.
    ///   - extent: The tile extent value for the layer.
    ///   - projectionFunction: A closure that converts a ``Coordinate3D`` to tile-local
    ///     (x, y) integers.
    /// - Returns: A ``VectorTile_Tile.Layer`` populated with the encoded features, keys, and values.
    static func encodeVersion2(
        features: [Feature],
        extent: UInt32,
        projectionFunction: ((Coordinate3D) -> (x: Int, y: Int))
    ) -> VectorTile_Tile.Layer {
        var layer = VectorTile_Tile.Layer()
        layer.version = 2
        layer.extent = extent

        var vectorTileFeatures: [VectorTile_Tile.Feature] = []

        var keys: [String] = []
        var keyPositions: [String: UInt32] = [:]

        var values: [VectorTile_Tile.Value] = []
        var valuePositions: [AnyHashable: UInt32] = [:]

        for feature in features {
            guard var vectorTileFeature = vectorTileFeature(from: feature, projectionFunction: projectionFunction) else { continue }

            var tags: [UInt32] = []

            for (propertyKey, propertyValue) in feature.properties {
                let keyIndex: UInt32 = keyPositions[propertyKey] ?? {
                    keys.append(propertyKey)

                    let index = UInt32(keys.count - 1)
                    keyPositions[propertyKey] = index

                    return index
                }()

                // Encode arrays and dictionaries as JSON encoded strings
                var hashablePropertyValue: AnyHashable
                if let array = propertyValue as? [Sendable] {
                    guard let data: Data = (try? JSONSerialization.data(withJSONObject: array)) else { continue }
                    hashablePropertyValue = String(data: data, encoding: .utf8) ?? ""
                }
                else if let dictionary = propertyValue as? [String: Sendable] {
                    guard let data: Data = (try? JSONSerialization.data(withJSONObject: dictionary)) else { continue }
                    hashablePropertyValue = String(data: data, encoding: .utf8) ?? ""
                }
                else if propertyValue is AnyHashable {
                    hashablePropertyValue = propertyValue as! AnyHashable
                }
                else {
                    // TODO: Check this
                    continue
                }

                let valueIndex: UInt32 = valuePositions[hashablePropertyValue] ?? {
                    var encodedPropertyValue = VectorTile_Tile.Value()

                    switch hashablePropertyValue {
                    case let string as String:
                        encodedPropertyValue.stringValue = string
                    case let int as Int:
                        encodedPropertyValue.intValue = Int64(int)
                    case let bool as Bool:
                        encodedPropertyValue.boolValue = bool
                    case let double as Double:
                        encodedPropertyValue.doubleValue = double
                    case let float as Float:
                        encodedPropertyValue.floatValue = float
                    case let uint as UInt64:
                        encodedPropertyValue.uintValue = uint
                    case let sint as Int64:
                        encodedPropertyValue.sintValue = sint
                    default:
                        encodedPropertyValue.stringValue = ""
                    }

                    values.append(encodedPropertyValue)

                    let index = UInt32(values.count - 1)
                    valuePositions[hashablePropertyValue] = index

                    return index
                }()

                tags.append(keyIndex)
                tags.append(valueIndex)
            }

            vectorTileFeature.tags = tags

            vectorTileFeatures.append(vectorTileFeature)
        }

        layer.features = vectorTileFeatures
        layer.keys = keys
        layer.values = values

        return layer
    }

    /// Converts a ``Feature`` into a ``VectorTile_Tile.Feature`` with encoded geometry.
    ///
    /// Handles all geometry types: ``Point``, ``MultiPoint``, ``LineString``,
    /// ``MultiLineString``, ``Polygon``, and ``MultiPolygon``.
    ///
    /// - Parameters:
    ///   - feature: The source feature to encode.
    ///   - projectionFunction: A closure that converts a ``Coordinate3D`` to tile-local
    ///     (x, y) integers.
    /// - Returns: A protobuf feature with geometry integers, or `nil` if the geometry
    ///   type is unsupported.
    static func vectorTileFeature(
        from feature: Feature,
        projectionFunction: ((Coordinate3D) -> (x: Int, y: Int))
    ) -> VectorTile_Tile.Feature? {
        var geometryIntegers: [UInt32]?
        var geometryType: VectorTile_Tile.GeomType?

        switch feature.geometry {
        case let point as Point:
            geometryType = .point
            geometryIntegers = self.geometryIntegers(
                fromMultiCoordinates: [[point.coordinate]],
                ofType: .point,
                projectionFunction: projectionFunction)

        case let multiPoint as MultiPoint:
            geometryType = .point
            geometryIntegers = self.geometryIntegers(
                fromMultiCoordinates: multiPoint.coordinates.map({ [$0] }),
                ofType: .point,
                projectionFunction: projectionFunction)

        case let lineString as LineString:
            geometryType = .linestring
            geometryIntegers = self.geometryIntegers(
                fromMultiCoordinates: [lineString.coordinates],
                ofType: .linestring,
                projectionFunction: projectionFunction)

        case let multiLineString as MultiLineString:
            geometryType = .linestring
            geometryIntegers = self.geometryIntegers(
                fromMultiCoordinates: multiLineString.coordinates,
                ofType: .linestring,
                projectionFunction: projectionFunction)

        case let polygon as Polygon:
            geometryType = .polygon
            geometryIntegers = self.geometryIntegers(
                fromMultiCoordinates: polygon.coordinates,
                ofType: .polygon,
                projectionFunction: projectionFunction)

        case let multiPolygon as MultiPolygon:
            geometryType = .polygon
            let multiCoordinates: [[Coordinate3D]] = Array(multiPolygon.polygons.map({ $0.coordinates }).joined())
            geometryIntegers = self.geometryIntegers(
                fromMultiCoordinates: multiCoordinates,
                ofType: .polygon,
                projectionFunction: projectionFunction)

        default:
            return nil
        }

        if let geometryIntegers,
           let geometryType
        {
            var vectorTileFeature = VectorTile_Tile.Feature()
            vectorTileFeature.type = geometryType
            vectorTileFeature.geometry = geometryIntegers

            if let featureId = feature.id?.uint64Value {
                vectorTileFeature.id = featureId
            }

            return vectorTileFeature
        }

        return nil
    }

    private static let commandIdMoveTo: UInt32 = 1
    private static let commandIdLineTo: UInt32 = 2
    private static let commandIdClosePath: UInt32 = 7

    /// Encodes coordinate arrays into an MVT geometry integer stream using zigzag encoding.
    ///
    /// Produces MoveTo, LineTo, and ClosePath commands appropriate for the geometry type.
    /// Polygon rings are automatically closed with a ClosePath command.
    ///
    /// - Parameters:
    ///   - multiCoordinates: An array of coordinate rings to encode.
    ///   - featureType: The protobuf geometry type (point, linestring, polygon).
    ///   - projectionFunction: A closure that converts a ``Coordinate3D`` to tile-local
    ///     (x, y) integers.
    /// - Returns: An array of encoded geometry integers, or `nil` if the input is invalid.
    static func geometryIntegers(
        fromMultiCoordinates multiCoordinates: [[Coordinate3D]],
        ofType featureType: VectorTile_Tile.GeomType,
        projectionFunction: ((Coordinate3D) -> (x: Int, y: Int))
    ) -> [UInt32]? {
        var geometryIntegers: [UInt32] = []

        var dx = 0
        var dy = 0

        var commandId: UInt32 = 0
        var commandCount: UInt32 = 0
        var commandInteger: UInt32 = 0

        // Encode points
        if featureType == .point {
            commandId = MVTEncoder.commandIdMoveTo
            commandCount = UInt32(multiCoordinates.count)
            commandInteger = (commandId & 0x7) | (commandCount << 3)
            geometryIntegers.append(commandInteger)

            for coordinates in multiCoordinates {
                guard let moveToCoordinate = coordinates.first else { continue }

                let (x, y) = projectionFunction(moveToCoordinate)
                geometryIntegers.append(UInt32(MVTEncoder.zigZagEncode(Int(x) - dx)))
                geometryIntegers.append(UInt32(MVTEncoder.zigZagEncode(Int(y) - dy)))
                dx = x
                dy = y
            }

            return geometryIntegers
        }

        // Else: linestrings or polygons
        guard featureType == .linestring || featureType == .polygon else { return nil }

        for coordinates in multiCoordinates {
            guard coordinates.count > 1,
                  let moveToCoordinate = coordinates.first
            else { continue }

            commandId = MVTEncoder.commandIdMoveTo
            commandCount = 1
            commandInteger = (commandId & 0x7) | (commandCount << 3)
            geometryIntegers.append(commandInteger)

            let (x, y) = projectionFunction(moveToCoordinate)
            geometryIntegers.append(UInt32(MVTEncoder.zigZagEncode(Int(x) - dx)))
            geometryIntegers.append(UInt32(MVTEncoder.zigZagEncode(Int(y) - dy)))
            dx = x
            dy = y

            if featureType == .linestring
                || coordinates.get(at: 0) != coordinates.get(at: -1)
            {
                commandId = MVTEncoder.commandIdLineTo
                commandCount = UInt32(coordinates.count - 1)
                commandInteger = (commandId & 0x7) | (commandCount << 3)
                geometryIntegers.append(commandInteger)

                for coordinate in coordinates[1...] {
                    let (x, y) = projectionFunction(coordinate)
                    geometryIntegers.append(UInt32(MVTEncoder.zigZagEncode(Int(x) - dx)))
                    geometryIntegers.append(UInt32(MVTEncoder.zigZagEncode(Int(y) - dy)))
                    dx = x
                    dy = y
                }
            }
            else {
                commandId = MVTEncoder.commandIdLineTo
                commandCount = UInt32(coordinates.count - 2)
                commandInteger = (commandId & 0x7) | (commandCount << 3)
                geometryIntegers.append(commandInteger)

                for coordinate in coordinates[1 ..< coordinates.count - 1] {
                    let (x, y) = projectionFunction(coordinate)
                    geometryIntegers.append(UInt32(MVTEncoder.zigZagEncode(Int(x) - dx)))
                    geometryIntegers.append(UInt32(MVTEncoder.zigZagEncode(Int(y) - dy)))
                    dx = x
                    dy = y
                }
            }

            if featureType == .polygon {
                commandId = MVTEncoder.commandIdClosePath
                commandCount = 1
                commandInteger = (commandId & 0x7) | (commandCount << 3)
                geometryIntegers.append(commandInteger)
            }
        }

        return geometryIntegers
    }

    private static func zigZagEncode(_ n: Int) -> Int {
        (n >> 31) ^ (n << 1)
    }

    // MARK: - Projections

    /// Returns a projection function that passes coordinate values through as-is.
    ///
    /// Used when the source projection is ``Projection/noSRID``.
    ///
    /// - Returns: A closure that converts a ``Coordinate3D`` to tile-local (x, y) integers
    ///   by truncating the coordinate values.
    static func passThroughToTile() -> ((Coordinate3D) -> (x: Int, y: Int)) {
        { (coordinate) -> (Int, Int) in
            (x: Int(coordinate.x), y: Int(coordinate.y))
        }
    }

    /// Returns a projection function that converts EPSG:3857 (Web Mercator) coordinates
    /// to tile-local integer values.
    ///
    /// - Parameters:
    ///   - x: The tile column index.
    ///   - y: The tile row index.
    ///   - z: The tile zoom level.
    ///   - extent: The tile extent in pixels.
    /// - Returns: A closure that maps a ``Coordinate3D`` in EPSG:3857 to tile-local (x, y) integers.
    static func projectFromEpsg3857(
        x: Int,
        y: Int,
        z: Int,
        extent: Int
    ) -> ((Coordinate3D) -> (x: Int, y: Int)) {
        let extent = Double(extent)
        let bounds = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)

        let topLeft = Coordinate3D(x: bounds.southWest.x, y: bounds.northEast.y)
        let xSpan: Double = abs(bounds.northEast.x - bounds.southWest.x)
        let ySpan: Double = abs(bounds.northEast.y - bounds.southWest.y)

        return { (coordinate) -> (Int, Int) in
            let projectedX = Int(((coordinate.x - topLeft.x) / xSpan) * extent)
            let projectedY = Int(((topLeft.y - coordinate.y) / ySpan) * extent)
            return (projectedX, projectedY)
        }
    }

    /// Returns a projection function that converts EPSG:4978 (ECEF) coordinates
    /// to tile-local integer values.
    ///
    /// The conversion first re-projects from EPSG:4978 to EPSG:4326, then to tile space.
    ///
    /// - Parameters:
    ///   - x: The tile column index.
    ///   - y: The tile row index.
    ///   - z: The tile zoom level.
    ///   - extent: The tile extent in pixels.
    /// - Returns: A closure that maps a ``Coordinate3D`` in EPSG:4978 to tile-local (x, y) integers.
    static func projectFromEpsg4978(
        x: Int,
        y: Int,
        z: Int,
        extent: Int
    ) -> ((Coordinate3D) -> (x: Int, y: Int)) {
        let projectedFrom4326 = projectFromEpsg4326(x: x, y: y, z: z, extent: extent)
        return { (coordinate) -> (Int, Int) in
            projectedFrom4326(coordinate.projected(to: .epsg4326))
        }
    }

    /// Returns a projection function that converts EPSG:4326 (WGS84) coordinates
    /// to tile-local integer values.
    ///
    /// The conversion first re-projects from EPSG:4326 to EPSG:3857, then maps into tile space.
    ///
    /// - Parameters:
    ///   - x: The tile column index.
    ///   - y: The tile row index.
    ///   - z: The tile zoom level.
    ///   - extent: The tile extent in pixels.
    /// - Returns: A closure that maps a ``Coordinate3D`` in EPSG:4326 to tile-local (x, y) integers.
    static func projectFromEpsg4326(
        x: Int,
        y: Int,
        z: Int,
        extent: Int
    ) -> ((Coordinate3D) -> (x: Int, y: Int)) {
        let extent = Double(extent)
        let bounds = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)

        let topLeft = Coordinate3D(x: bounds.southWest.x, y: bounds.northEast.y)
        let xSpan: Double = abs(bounds.northEast.x - bounds.southWest.x)
        let ySpan: Double = abs(bounds.northEast.y - bounds.southWest.y)

        return { (coordinate) -> (Int, Int) in
            let projectedCoordinate = coordinate.projected(to: .epsg3857)
            let projectedX = Int(((projectedCoordinate.x - topLeft.x) / xSpan) * extent)
            let projectedY = Int(((topLeft.y - projectedCoordinate.y) / ySpan) * extent)
            return (projectedX, projectedY)
        }
    }

}
