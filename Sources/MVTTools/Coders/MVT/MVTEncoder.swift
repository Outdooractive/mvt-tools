#if EnableMVT
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
    ///   - layers: A dictionary of layer names to their `VectorTile.LayerContainer`.
    ///   - x: The tile column index.
    ///   - y: The tile row index.
    ///   - z: The tile zoom level.
    ///   - projection: The source projection of the input coordinates (default: `Projection.epsg4326`).
    ///   - options: Export options controlling buffer size, simplification, and compression.
    /// - Returns: The serialized MVT protobuf bytes (optionally gzip-compressed), or `nil` on failure.
    static func encode(
        layers: [String: VectorTile.LayerContainer],
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        options: VectorTile.ExportOptions = .init()
    ) -> Data? {
        var tile = VectorTile_Tile()

        let extent = UInt32(VectorTile.ExportOptions.extent)
        let projectionFunction = Projections.inverseProjection(
            for: projection, x: x, y: y, z: z, extent: Int(extent))

        // Determine the clipping bounding box.
        var clipBoundingBox: BoundingBox?
        if projection.hasSRID {
            clipBoundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: projection)
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

        if bufferSize != 0, let boundingBox = clipBoundingBox {
            clipBoundingBox = VectorTile.expanded(boundingBox, byBufferSize: bufferSize)
        }

        var vectorTileLayers: [VectorTile_Tile.Layer] = []

        for (layerName, layerContainer) in layers.sorted(by: { $0.key < $1.key }) {
            guard layerContainer.features.isNotEmpty else { continue }

            let layerFeatures = VectorTile.processedFeatures(
                layerContainer.features,
                clipBoundingBox: clipBoundingBox,
                simplifyDistance: simplifyDistance)
                .filter({ $0.geometry != nil })

            guard layerFeatures.isNotEmpty else { continue }

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

    /// Encodes a collection of `Feature` values into a version-2 protobuf layer.
    ///
    /// Deduplicates property keys and values across features and assigns them
    /// integer indices in the layer's key/value tables.
    ///
    /// - Parameters:
    ///   - features: The features to encode.
    ///   - extent: The tile extent value for the layer.
    ///   - projectionFunction: A closure that converts a `Coordinate3D` to tile-local
    ///     (x, y) integers.
    /// - Returns: A `VectorTile_Tile.Layer` populated with the encoded features, keys, and values.
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
        var valuePositions: [MVTEncoder.EncodedPropertyValue: UInt32] = [:]

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

                // Encode arrays and dictionaries as JSON encoded strings.
                // The key is a type-tagged enum instead of `AnyHashable`:
                // Foundation bridges numeric `AnyHashable` values, so `Int(1)`
                // and `Double(1.0)`, or `Int64(1)` and `UInt64(1)`, compare
                // equal and would otherwise share one value table entry and
                // lose their original type.
                guard let valueKey = MVTEncoder.encodedPropertyValue(from: propertyValue) else { continue }

                let valueIndex: UInt32 = valuePositions[valueKey] ?? {
                    values.append(valueKey.protobufValue)

                    let index = UInt32(values.count - 1)
                    valuePositions[valueKey] = index

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

    /// Converts a `Feature` into a `VectorTile_Tile.Feature` with encoded geometry.
    ///
    /// Handles all geometry types: `Point`, `MultiPoint`, `LineString`,
    /// `multi-line string`, `Polygon`, and `MultiPolygon`.
    ///
    /// - Parameters:
    ///   - feature: The source feature to encode.
    ///   - projectionFunction: A closure that converts a `Coordinate3D` to tile-local
    ///     (x, y) integers.
    /// - Returns: A protobuf feature with geometry integers, or `nil` if the geometry
    ///   type is unsupported.
    static func vectorTileFeature(
        from feature: Feature,
        projectionFunction: ((Coordinate3D) -> (x: Int, y: Int))
    ) -> VectorTile_Tile.Feature? {
        guard let geometry = feature.geometry else { return nil }

        var geometryIntegers: [UInt32]?
        var geometryType: VectorTile_Tile.GeomType?

        switch geometry {
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
            // MVT requires exterior rings to be clockwise in tile space and
            // holes counter-clockwise. `withWindingOrder(.counterClockwise)`
            // produces that orientation in geographic/GeoJSON coordinates,
            // which the decoder's `isUnprojectedClockwise` check expects.
            let normalized = polygon.withWindingOrder(.counterClockwise)
            geometryIntegers = self.geometryIntegers(
                fromMultiCoordinates: normalized.coordinates,
                ofType: .polygon,
                projectionFunction: projectionFunction)

        case let multiPolygon as MultiPolygon:
            geometryType = .polygon
            let normalized = multiPolygon.withWindingOrder(.counterClockwise)
            let multiCoordinates: [[Coordinate3D]] = Array(normalized.polygons.map({ $0.coordinates }).joined())
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
    ///   - projectionFunction: A closure that converts a `Coordinate3D` to tile-local
    ///     (x, y) integers.
    /// - Returns: An array of encoded geometry integers, or `nil` if the input is invalid.
    static func geometryIntegers(
        fromMultiCoordinates multiCoordinates: [[Coordinate3D]],
        ofType featureType: VectorTile_Tile.GeomType,
        projectionFunction: ((Coordinate3D) -> (x: Int, y: Int))
    ) -> [UInt32]? {
        var geometryIntegers: [UInt32] = []

        var previousX = 0
        var previousY = 0

        /// Projects and appends one coordinate, returning `false` when the
        /// coordinate or its delta cannot be represented in the MVT command
        /// stream (32-bit signed range).
        func appendCoordinate(_ coordinate: Coordinate3D) -> Bool {
            let (x, y) = projectionFunction(coordinate)

            guard MVTEncoder.isRepresentableTileCoordinate(x),
                  MVTEncoder.isRepresentableTileCoordinate(y),
                  let encodedX = MVTEncoder.zigZagEncodedUInt32(x - previousX),
                  let encodedY = MVTEncoder.zigZagEncodedUInt32(y - previousY)
            else { return false }

            geometryIntegers.append(encodedX)
            geometryIntegers.append(encodedY)
            previousX = x
            previousY = y
            return true
        }

        func appendCommand(id: UInt32, count: Int) -> Bool {
            // The command count occupies the upper 29 bits of the command
            // integer, so it must fit into 0 ... 2^29 - 1.
            guard count > 0,
                  count <= 0x1FFF_FFFF,
                  let count = UInt32(exactly: count)
            else { return false }

            geometryIntegers.append((id & 0x7) | (count << 3))
            return true
        }

        // Encode points
        if featureType == .point {
            let pointCount = multiCoordinates.count
            guard pointCount > 0,
                  appendCommand(id: MVTEncoder.commandIdMoveTo, count: pointCount)
            else { return nil }

            for coordinates in multiCoordinates {
                guard let coordinate = coordinates.first,
                      appendCoordinate(coordinate)
                else { return nil }
            }

            return geometryIntegers
        }

        // Else: linestrings or polygons
        guard featureType == .linestring || featureType == .polygon else { return nil }

        for coordinates in multiCoordinates {
            guard coordinates.count > 1,
                  let moveToCoordinate = coordinates.first
            else { continue }

            guard appendCommand(id: MVTEncoder.commandIdMoveTo, count: 1),
                  appendCoordinate(moveToCoordinate)
            else { return nil }

            if featureType == .linestring
                || coordinates.get(at: 0) != coordinates.get(at: -1)
            {
                guard appendCommand(id: MVTEncoder.commandIdLineTo, count: coordinates.count - 1) else { return nil }

                for coordinate in coordinates[1...] {
                    guard appendCoordinate(coordinate) else { return nil }
                }
            }
            else {
                guard appendCommand(id: MVTEncoder.commandIdLineTo, count: coordinates.count - 2) else { return nil }

                for coordinate in coordinates[1 ..< coordinates.count - 1] {
                    guard appendCoordinate(coordinate) else { return nil }
                }
            }

            if featureType == .polygon {
                guard appendCommand(id: MVTEncoder.commandIdClosePath, count: 1) else { return nil }
            }
        }

        return geometryIntegers
    }

    /// A Boolean value indicating whether `value` can be stored in an MVT
    /// geometry command. MVT command parameters are 32-bit signed integers.
    ///
    /// - Parameter value: The projected tile coordinate or coordinate delta.
    /// - Returns: `true` if the value fits into the signed 32-bit range.
    private static func isRepresentableTileCoordinate(_ value: Int) -> Bool {
        value >= Int(Int32.min) && value <= Int(Int32.max)
    }

    /// Zigzag-encodes a signed 32-bit delta into an MVT command parameter.
    ///
    /// - Parameter value: The delta to encode.
    /// - Returns: The encoded unsigned 32-bit value, or `nil` when `value`
    ///   does not fit into the signed 32-bit range.
    private static func zigZagEncodedUInt32(_ value: Int) -> UInt32? {
        guard isRepresentableTileCoordinate(value) else { return nil }

        let encoded = (value << 1) ^ (value >> 31)
        return UInt32(bitPattern: Int32(truncatingIfNeeded: encoded))
    }

    // MARK: - Projections


    // MARK: - Property values

    /// A type-tagged property value used as the key when deduplicating the
    /// MVT value table.
    private enum EncodedPropertyValue: Hashable {

        case string(String)
        case bool(Bool)
        case int(Int)
        case int64(Int64)
        case uint64(UInt64)
        case double(Double)
        case float(Float)

        /// The protobuf representation of this value.
        var protobufValue: VectorTile_Tile.Value {
            var value = VectorTile_Tile.Value()

            switch self {
            case let .string(string): value.stringValue = string
            case let .bool(bool): value.boolValue = bool
            case let .int(int): value.intValue = Int64(int)
            case let .int64(int64): value.intValue = int64
            case let .uint64(uint64): value.uintValue = uint64
            case let .double(double): value.doubleValue = double
            case let .float(float): value.floatValue = float
            }

            return value
        }

    }

    /// Converts a `Feature` property value into a type-tagged MVT value.
    ///
    /// Arrays and dictionaries are JSON-encoded as strings, matching the
    /// decoder's inverse conversion.
    ///
    /// - Parameter propertyValue: The property value from a feature.
    /// - Returns: The encoded value, or `nil` when the value cannot be
    ///   represented.
    private static func encodedPropertyValue(
        from propertyValue: Sendable
    ) -> EncodedPropertyValue? {
        if let array = propertyValue as? [Sendable] {
            guard let data = try? JSONSerialization.data(withJSONObject: array) else { return nil }
            return .string(String(decoding: data, as: UTF8.self))
        }
        if let dictionary = propertyValue as? [String: Sendable] {
            guard let data = try? JSONSerialization.data(withJSONObject: dictionary) else { return nil }
            return .string(String(decoding: data, as: UTF8.self))
        }
        if let string = propertyValue as? String { return .string(string) }
        if let bool = propertyValue as? Bool { return .bool(bool) }
        if let int = propertyValue as? Int { return .int(int) }
        if let int8 = propertyValue as? Int8 { return .int(Int(int8)) }
        if let int16 = propertyValue as? Int16 { return .int(Int(int16)) }
        if let int32 = propertyValue as? Int32 { return .int(Int(int32)) }
        if let int64 = propertyValue as? Int64 { return .int64(int64) }
        if let uint64 = propertyValue as? UInt64 { return .uint64(uint64) }
        if let uint = propertyValue as? UInt { return .uint64(UInt64(uint)) }
        if let uint8 = propertyValue as? UInt8 { return .uint64(UInt64(uint8)) }
        if let uint16 = propertyValue as? UInt16 { return .uint64(UInt64(uint16)) }
        if let uint32 = propertyValue as? UInt32 { return .uint64(UInt64(uint32)) }
        if let double = propertyValue as? Double { return .double(double) }
        if let float = propertyValue as? Float { return .float(float) }

        if let number = propertyValue as? NSNumber {
            // Fallback for Foundation-produced numbers (JSONSerialization on
            // Darwin). Native Swift types are handled above so unsigned
            // values keep their signedness on Linux.
            let cType = number.objCType.pointee
            switch cType {
            case 66 /* 'B' (bool) */, 99 /* 'c' (char → BOOL) */:
                return .bool(number.boolValue)
            case 100 /* 'd' (double) */, 102 /* 'f' (float) */:
                return .double(number.doubleValue)
            case 113 /* 'q' (long long) */, 105 /* 'i' (int) */, 108 /* 'l' (long) */:
                return .int64(number.int64Value)
            case 81 /* 'Q' (unsigned long long) */:
                return .uint64(number.uint64Value)
            default:
                return .double(number.doubleValue)
            }
        }

        // Preserve unknown hashable values (e.g. dates) as text instead of
        // silently writing an empty string.
        if let hashable = propertyValue as? AnyHashable {
            return .string(String(describing: hashable))
        }

        return nil
    }

}
#endif
