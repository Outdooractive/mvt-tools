#if !os(Linux)
import CoreLocation
#endif
import Foundation
import GISTools
import Gzip
import struct GISTools.Polygon

// MARK: Writing vector tiles

extension VectorTile {

    static func tileDataFor(
        layers: [String: LayerContainer],
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        options: VectorTileExportOptions)
        -> Data?
    {
        var tile = VectorTile_Tile()

        let extent: UInt32 = UInt32(options.extent)
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
        }

        var bufferSize: Int = 0
        switch options.bufferSize {
        case let .extent(extent):
            bufferSize = extent
        case let .pixel(pixel):
            bufferSize = Int((Double(pixel) / Double(options.tileSize)) * Double(options.extent))
        }

        var simplifyDistance: CLLocationDistance = 0.0
        switch options.simplifyFeatures {
        case .no:
            simplifyDistance = 0.0
        case let .extent(extent):
            let tileBoundsInMeters = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)
            simplifyDistance = (tileBoundsInMeters.southEast.longitude - tileBoundsInMeters.southWest.longitude) / Double(options.extent) * Double(extent)
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
            let layerFeatures: [Feature]
            if let clippedToBoundingBox = clipBoundingBox {
                if simplifyDistance > 0.0 {
                    layerFeatures = layerContainer.features.compactMap({ $0.clipped(to: clippedToBoundingBox)?.simplified(tolerance: simplifyDistance) })
                }
                else {
                    layerFeatures = layerContainer.features.compactMap({ $0.clipped(to: clippedToBoundingBox ) })
                }
            }
            else {
                layerFeatures = layerContainer.features
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
           let serializedData = serializedData
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

    static func encodeVersion2(
        features: [Feature],
        extent: UInt32,
        projectionFunction: ((Coordinate3D) -> (x: Int, y: Int)))
        -> VectorTile_Tile.Layer
    {
        var layer = VectorTile_Tile.Layer()
        layer.version = 2
        layer.extent = extent

        var vectorTileFeatures: [VectorTile_Tile.Feature] = []

        var keys: [String] = []
        var keyPositions: [String: UInt32] = [:]

        var values: [VectorTile_Tile.Value] = []
        var valuePositions: [AnyHashable: UInt32] = [:]

        for feature in features {
            guard var vectorTileFeature = self.vectorTileFeature(from: feature, projectionFunction: projectionFunction) else { continue }

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
                if let array = propertyValue as? Array<Sendable> {
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

    static func vectorTileFeature(
        from feature: Feature,
        projectionFunction: ((Coordinate3D) -> (x: Int, y: Int)))
        -> VectorTile_Tile.Feature?
    {
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

        if let geometryIntegers = geometryIntegers,
            let geometryType = geometryType
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

    static func geometryIntegers(
        fromMultiCoordinates multiCoordinates: [[Coordinate3D]],
        ofType featureType: VectorTile_Tile.GeomType,
        projectionFunction: ((Coordinate3D) -> (x: Int, y: Int)))
        -> [UInt32]?
    {
        var geometryIntegers: [UInt32] = []

        var dx: Int = 0
        var dy: Int = 0

        var commandId: UInt32 = 0
        var commandCount: UInt32 = 0
        var commandInteger: UInt32 = 0

        // Encode points
        if featureType == .point {
            commandId = VectorTile.commandIdMoveTo
            commandCount = UInt32(multiCoordinates.count)
            commandInteger = (commandId & 0x7) | (commandCount << 3)
            geometryIntegers.append(commandInteger)

            for coordinates in multiCoordinates {
                guard let moveToCoordinate = coordinates.first else { continue }

                let (x, y) = projectionFunction(moveToCoordinate)
                geometryIntegers.append(UInt32(VectorTile.zigZagEncode(Int(x) - dx)))
                geometryIntegers.append(UInt32(VectorTile.zigZagEncode(Int(y) - dy)))
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

            commandId = VectorTile.commandIdMoveTo
            commandCount = 1
            commandInteger = (commandId & 0x7) | (commandCount << 3)
            geometryIntegers.append(commandInteger)

            let (x, y) = projectionFunction(moveToCoordinate)
            geometryIntegers.append(UInt32(VectorTile.zigZagEncode(Int(x) - dx)))
            geometryIntegers.append(UInt32(VectorTile.zigZagEncode(Int(y) - dy)))
            dx = x
            dy = y

            if featureType == .linestring
                || coordinates.get(at: 0) != coordinates.get(at: -1)
            {
                commandId = VectorTile.commandIdLineTo
                commandCount = UInt32(coordinates.count - 1)
                commandInteger = (commandId & 0x7) | (commandCount << 3)
                geometryIntegers.append(commandInteger)

                for coordinate in coordinates[1...] {
                    let (x, y) = projectionFunction(coordinate)
                    geometryIntegers.append(UInt32(VectorTile.zigZagEncode(Int(x) - dx)))
                    geometryIntegers.append(UInt32(VectorTile.zigZagEncode(Int(y) - dy)))
                    dx = x
                    dy = y
                }
            }
            else {
                commandId = VectorTile.commandIdLineTo
                commandCount = UInt32(coordinates.count - 2)
                commandInteger = (commandId & 0x7) | (commandCount << 3)
                geometryIntegers.append(commandInteger)

                for coordinate in coordinates[1 ..<  coordinates.count - 1] {
                    let (x, y) = projectionFunction(coordinate)
                    geometryIntegers.append(UInt32(VectorTile.zigZagEncode(Int(x) - dx)))
                    geometryIntegers.append(UInt32(VectorTile.zigZagEncode(Int(y) - dy)))
                    dx = x
                    dy = y
                }
            }

            if featureType == .polygon {
                commandId = VectorTile.commandIdClosePath
                commandCount = 1
                commandInteger = (commandId & 0x7) | (commandCount << 3)
                geometryIntegers.append(commandInteger)
            }
        }

        return geometryIntegers
    }

    private static func zigZagEncode(_ n: Int) -> Int {
        return (n >> 31) ^ (n << 1)
    }

    // MARK: - Projections

    static func passThroughToTile() -> ((Coordinate3D) -> (x: Int, y: Int)) {
        return { (coordinate) -> (Int, Int) in
            return (x: Int(coordinate.x), y: Int(coordinate.y))
        }
    }

    static func projectFromEpsg3857(
        x: Int,
        y: Int,
        z: Int,
        extent: Int)
        -> ((Coordinate3D) -> (x: Int, y: Int))
    {
        let extent: Double = Double(extent)
        let bounds = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)

        let topLeft = Coordinate3D(x: bounds.southWest.x, y: bounds.northEast.y)
        let xSpan: Double = abs(bounds.northEast.x - bounds.southWest.x)
        let ySpan: Double = abs(bounds.northEast.y - bounds.southWest.y)

        return { (coordinate) -> (Int, Int) in
            let projectedX: Int = Int(((coordinate.x - topLeft.x) / xSpan) * extent)
            let projectedY: Int = Int(((topLeft.y - coordinate.y) / ySpan) * extent)
            return (projectedX, projectedY)
        }
    }

    static func projectFromEpsg4326(
        x: Int,
        y: Int,
        z: Int,
        extent: Int)
        -> ((Coordinate3D) -> (x: Int, y: Int))
    {
        let extent: Double = Double(extent)
        let bounds = MapTile(x: x, y: y, z: z).boundingBox(projection: .epsg3857)

        let topLeft = Coordinate3D(x: bounds.southWest.x, y: bounds.northEast.y)
        let xSpan: Double = abs(bounds.northEast.x - bounds.southWest.x)
        let ySpan: Double = abs(bounds.northEast.y - bounds.southWest.y)

        return { (coordinate) -> (Int, Int) in
            let projectedCoordinate = coordinate.projected(to: .epsg3857)
            let projectedX: Int = Int(((projectedCoordinate.x - topLeft.x) / xSpan) * extent)
            let projectedY: Int = Int(((topLeft.y - projectedCoordinate.y) / ySpan) * extent)
            return (projectedX, projectedY)
        }
    }

}
