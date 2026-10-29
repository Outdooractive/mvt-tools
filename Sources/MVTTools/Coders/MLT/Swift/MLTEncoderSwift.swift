#if EnableMLT
#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools
import Gzip
import struct GISTools.Polygon

/// Pure Swift MLT encoder.
///
/// This first implementation emits a conservative, deterministic subset of
/// MLT: plain varints for integers and lengths, componentwise-delta varints for
/// vertices, plain strings, and boolean RLE for nullable/present streams. It
/// deliberately avoids FSST, FastPFOR, dictionaries and Morton/Hilbert vertex
/// ordering so that its output is easy to verify across decoders.
enum MLTEncoderSwift {

    static func encode(
        layers: [String: VectorTile.LayerContainer],
        x: Int,
        y: Int,
        z: Int,
        projection: Projection = .epsg4326,
        options: VectorTile.ExportOptions = .init()
    ) -> Data? {
        do {
            let data = try encodeTile(
                layers: layers,
                x: x,
                y: y,
                z: z,
                projection: projection,
                options: options)
            return try compress(data, options: options.compression)
        }
        catch {
            return nil
        }
    }

    private static func compress(
        _ data: Data,
        options: VectorTile.ExportOptions.CompressionOptions
    ) throws -> Data {
        switch options {
        case .no:
            return data
        case .default:
            return try data.gzipped(level: .defaultCompression)
        case let .level(level):
            let clamped = max(0, min(9, level))
            return try data.gzipped(level: CompressionLevel(rawValue: Int32(clamped)))
        }
    }

    private static func encodeTile(
        layers: [String: VectorTile.LayerContainer],
        x: Int,
        y: Int,
        z: Int,
        projection: Projection,
        options: VectorTile.ExportOptions
    ) throws -> Data {
        let extent = VectorTile.ExportOptions.extent
        let projectionFunction = Projections.inverseProjection(
            for: projection, x: x, y: y, z: z, extent: extent)

        var clipBoundingBox: BoundingBox?
        if projection.hasSRID {
            clipBoundingBox = MapTile(x: x, y: y, z: z).boundingBox(projection: projection)
        }

        var bufferSize = 0
        switch options.bufferSize {
        case .no:
            bufferSize = 0
        case let .extent(value):
            bufferSize = value
        case let .pixel(pixel):
            bufferSize = Int(
                (Double(pixel) / Double(VectorTile.ExportOptions.tileSize))
                    * Double(VectorTile.ExportOptions.extent))
        }

        var simplifyDistance: Double = 0.0
        switch options.simplifyFeatures {
        case .no:
            simplifyDistance = 0.0
        case let .extent(value):
            let tileBoundsInMeters = MapTile(x: x, y: y, z: z)
                .boundingBox(projection: .epsg3857)
            simplifyDistance = (tileBoundsInMeters.southEast.longitude - tileBoundsInMeters.southWest.longitude)
                / Double(VectorTile.ExportOptions.extent) * Double(value)
        case let .meters(meters):
            simplifyDistance = meters
        }

        if bufferSize != 0, let boundingBox = clipBoundingBox {
            clipBoundingBox = VectorTile.expanded(boundingBox, byBufferSize: bufferSize)
        }

        var tileWriter = MLTByteWriter()

        for (layerName, container) in layers.sorted(by: { $0.key < $1.key }) {
            guard !layerName.isEmpty, container.features.isNotEmpty else { continue }

            let processed = VectorTile.processedFeatures(
                container.features,
                clipBoundingBox: clipBoundingBox,
                simplifyDistance: simplifyDistance)

            let features = processed.compactMap { feature -> MLTEncodableFeature? in
                guard let geometry = feature.geometry,
                      let encoded = encodeGeometry(geometry, project: projectionFunction)
                else {
                    return nil
                }
                return MLTEncodableFeature(
                    id: feature.id?.uint64Value,
                    hasNumericID: feature.id?.uint64Value != nil,
                    geometry: encoded,
                    properties: feature.properties)
            }

            guard features.isNotEmpty else { continue }

            let body = try encodeLayer(
                name: layerName,
                extent: extent,
                features: features)
            MLTTileFraming.writeBlock(
                tag: MLTTileFraming.tag0x01,
                payload: body,
                to: &tileWriter)
        }

        return tileWriter.data
    }

    // MARK: - Layer encoding

    private static func encodeLayer(
        name: String,
        extent: Int,
        features: [MLTEncodableFeature]
    ) throws -> [UInt8] {
        let idColumn = makeIDColumn(features: features)
        let geometryColumn = try makeGeometryColumn(features: features)
        let propertyColumns = try makePropertyColumns(features: features)

        var columns: [MLTEncodedColumn] = []
        if let idColumn {
            columns.append(idColumn)
        }
        columns.append(geometryColumn)
        columns.append(contentsOf: propertyColumns)

        let table = MLTFeatureTable(
            name: name,
            extent: extent,
            columns: columns.map(\.metadata))

        var body = MLTByteWriter()
        try table.encode(to: &body)

        for column in columns {
            try column.writeStreams(to: &body)
        }

        return body.bytes
    }

    // MARK: - ID column

    private static func makeIDColumn(features: [MLTEncodableFeature]) -> MLTEncodedColumn? {
        let hasAny = features.contains { $0.hasNumericID }
        guard hasAny else { return nil }

        let nullable = features.contains { !$0.hasNumericID }
        let longID = features.compactMap(\.id).contains { $0 > UInt64(Int32.max) }
        let values = features.map { $0.hasNumericID ? $0.id : nil }

        return .id(
            nullable: nullable,
            longID: longID,
            values: values,
            featureCount: features.count)
    }

    // MARK: - Geometry column

    private static func makeGeometryColumn(
        features: [MLTEncodableFeature]
    ) throws -> MLTEncodedColumn {
        let hasPolygons = features.contains {
            if case .polygon = $0.geometry { return true }
            if case .multiPolygon = $0.geometry { return true }
            return false
        }

        var types: [UInt32] = []
        var numGeometries: [UInt32] = []
        var numParts: [UInt32] = []
        var numRings: [UInt32] = []
        var vertices: [MLTTileCoordinate] = []

        types.reserveCapacity(features.count)

        for feature in features {
            switch feature.geometry {
            case let .point(coordinate):
                types.append(MLTGeometryType.point.rawValue)
                vertices.append(coordinate)

            case let .multiPoint(coordinates):
                types.append(MLTGeometryType.multiPoint.rawValue)
                numGeometries.append(UInt32(coordinates.count))
                vertices.append(contentsOf: coordinates)

            case let .lineString(coordinates):
                types.append(MLTGeometryType.lineString.rawValue)
                if hasPolygons {
                    numRings.append(UInt32(coordinates.count))
                }
                else {
                    numParts.append(UInt32(coordinates.count))
                }
                vertices.append(contentsOf: coordinates)

            case let .multiLineString(lines):
                types.append(MLTGeometryType.multiLineString.rawValue)
                numGeometries.append(UInt32(lines.count))
                for line in lines {
                    if hasPolygons {
                        numRings.append(UInt32(line.count))
                    }
                    else {
                        numParts.append(UInt32(line.count))
                    }
                    vertices.append(contentsOf: line)
                }

            case let .polygon(rings):
                types.append(MLTGeometryType.polygon.rawValue)
                numParts.append(UInt32(rings.count))
                for ring in rings {
                    numRings.append(UInt32(ring.count))
                    vertices.append(contentsOf: ring)
                }

            case let .multiPolygon(polygons):
                types.append(MLTGeometryType.multiPolygon.rawValue)
                numGeometries.append(UInt32(polygons.count))
                for polygon in polygons {
                    numParts.append(UInt32(polygon.count))
                    for ring in polygon {
                        numRings.append(UInt32(ring.count))
                        vertices.append(contentsOf: ring)
                    }
                }
            }
        }

        var streams: [MLTEncodedStream] = []
        streams.append(try stream(
            physical: .data,
            logical: .dictionary(.none),
            logical1: .none,
            logical2: .none,
            physicalTechnique: .varint,
            values: types))

        if !numGeometries.isEmpty {
            streams.append(try stream(
                physical: .length,
                logical: .length(.geometries),
                logical1: .none,
                logical2: .none,
                physicalTechnique: .varint,
                values: numGeometries))
        }
        if !numParts.isEmpty {
            streams.append(try stream(
                physical: .length,
                logical: .length(.parts),
                logical1: .none,
                logical2: .none,
                physicalTechnique: .varint,
                values: numParts))
        }
        if !numRings.isEmpty {
            streams.append(try stream(
                physical: .length,
                logical: .length(.rings),
                logical1: .none,
                logical2: .none,
                physicalTechnique: .varint,
                values: numRings))
        }

        let vertexPayload = encodeVertices(vertices)
        let vertexMetadata = MLTStreamMetadata(
            physicalStreamType: .data,
            logicalStreamType: .dictionary(.vertex),
            logicalTechnique1: .componentwiseDelta,
            logicalTechnique2: .none,
            physicalTechnique: .varint,
            numValues: vertices.count * 2,
            byteLength: vertexPayload.count)
        streams.append(MLTEncodedStream(metadata: vertexMetadata, payload: vertexPayload))

        return .geometry(streams: streams)
    }

    private static func encodeVertices(_ vertices: [MLTTileCoordinate]) -> [UInt8] {
        var writer = MLTByteWriter()
        var previousX: Int32 = 0
        var previousY: Int32 = 0
        for vertex in vertices {
            let deltaX = vertex.x &- previousX
            let deltaY = vertex.y &- previousY
            writer.writeVarint32(MLTZigZag.encode(deltaX))
            writer.writeVarint32(MLTZigZag.encode(deltaY))
            previousX = vertex.x
            previousY = vertex.y
        }
        return writer.bytes
    }

    // MARK: - Property columns

    private static func makePropertyColumns(
        features: [MLTEncodableFeature]
    ) throws -> [MLTEncodedColumn] {
        var keys = Set<String>()
        for feature in features {
            keys.formUnion(feature.properties.keys)
        }

        var columns: [MLTEncodedColumn] = []
        for key in keys.sorted() {
            let values: [any Sendable?] = features.map { $0.properties[key] }
            guard values.contains(where: { $0 != nil }) else { continue }
            let inferred = inferScalarType(values)
            columns.append(
                try makePropertyColumn(
                    name: key,
                    type: inferred,
                    values: values,
                    featureCount: features.count))
        }
        return columns
    }

    private struct PropertyInference {
        var hasBool = false
        var hasInt = false
        var hasUInt = false
        var hasFloat = false
        var hasDouble = false
        var hasString = false
        var allInt32 = true
        var allUInt32 = true
        var minInt: Int64 = .max
        var maxInt: Int64 = .min
        var maxUInt: UInt64 = 0
    }

    private static func inferScalarType(_ values: [any Sendable?]) -> MLTScalarType {
        var state = PropertyInference()

        for value in values {
            guard let value else {
                continue
            }
            switch value {
            case let value as Bool:
                _ = value
                state.hasBool = true
            case let value as Int:
                state.hasInt = true
                let wide = Int64(value)
                state.minInt = min(state.minInt, wide)
                state.maxInt = max(state.maxInt, wide)
                if wide < Int64(Int32.min) || wide > Int64(Int32.max) {
                    state.allInt32 = false
                }
            case let value as Int8:
                state.hasInt = true
                state.minInt = min(state.minInt, Int64(value))
                state.maxInt = max(state.maxInt, Int64(value))
            case let value as Int16:
                state.hasInt = true
                state.minInt = min(state.minInt, Int64(value))
                state.maxInt = max(state.maxInt, Int64(value))
            case let value as Int32:
                state.hasInt = true
                state.minInt = min(state.minInt, Int64(value))
                state.maxInt = max(state.maxInt, Int64(value))
            case let value as Int64:
                state.hasInt = true
                state.minInt = min(state.minInt, value)
                state.maxInt = max(state.maxInt, value)
                if value < Int64(Int32.min) || value > Int64(Int32.max) {
                    state.allInt32 = false
                }
            case let value as UInt:
                state.hasUInt = true
                state.maxUInt = max(state.maxUInt, UInt64(value))
                if value > UInt(UInt32.max) {
                    state.allUInt32 = false
                }
            case let value as UInt8:
                state.hasUInt = true
                state.maxUInt = max(state.maxUInt, UInt64(value))
            case let value as UInt16:
                state.hasUInt = true
                state.maxUInt = max(state.maxUInt, UInt64(value))
            case let value as UInt32:
                state.hasUInt = true
                state.maxUInt = max(state.maxUInt, UInt64(value))
            case let value as UInt64:
                state.hasUInt = true
                state.maxUInt = max(state.maxUInt, value)
                if value > UInt64(UInt32.max) {
                    state.allUInt32 = false
                }
            case let value as Float:
                _ = value
                state.hasFloat = true
            case let value as Double:
                _ = value
                state.hasDouble = true
            case let value as String:
                _ = value
                state.hasString = true
            default:
                state.hasString = true
            }
        }

        if state.hasString {
            return .string
        }
        if state.hasBool {
            return state.hasInt || state.hasUInt || state.hasFloat || state.hasDouble
                ? .string
                : .boolean
        }
        if state.hasDouble || (state.hasFloat && state.hasInt) || (state.hasFloat && state.hasUInt) {
            return .double
        }
        if state.hasFloat {
            return .float
        }
        if state.hasInt, state.hasUInt {
            if state.minInt >= 0, state.maxUInt <= UInt64(Int32.max) {
                return .int32
            }
            return .int64
        }
        if state.hasInt {
            return state.allInt32 ? .int32 : .int64
        }
        if state.hasUInt {
            return state.allUInt32 ? .uint32 : .uint64
        }
        return .string
    }

    private static func makePropertyColumn(
        name: String,
        type: MLTScalarType,
        values: [any Sendable?],
        featureCount: Int
    ) throws -> MLTEncodedColumn {
        let nullable = values.contains { $0 == nil }
        var encoded: [MLTEncodedValue?] = []
        encoded.reserveCapacity(featureCount)

        for value in values {
            guard let value else {
                encoded.append(nil)
                continue
            }
            switch type {
            case .boolean:
                guard let bool = value as? Bool else {
                    return try stringColumn(
                        name: name,
                        values: values,
                        featureCount: featureCount)
                }
                encoded.append(.bool(bool))
            case .int32:
                guard let int = int64Value(value, allowUnsigned: true) else {
                    return try stringColumn(name: name, values: values, featureCount: featureCount)
                }
                encoded.append(.int(int))
            case .int64:
                guard let int = int64Value(value, allowUnsigned: true) else {
                    return try stringColumn(name: name, values: values, featureCount: featureCount)
                }
                encoded.append(.int(int))
            case .uint32, .uint64:
                guard let uint = uint64Value(value) else {
                    return try stringColumn(name: name, values: values, featureCount: featureCount)
                }
                encoded.append(.uint(uint))
            case .float, .double:
                guard let double = doubleValue(value) else {
                    return try stringColumn(name: name, values: values, featureCount: featureCount)
                }
                encoded.append(.double(double))
            case .int8, .uint8:
                guard let int = int64Value(value, allowUnsigned: true) else {
                    return try stringColumn(name: name, values: values, featureCount: featureCount)
                }
                encoded.append(.int(int))
            case .string:
                encoded.append(.string(stringValue(value)))
            }
        }

        return .property(
            name: name,
            type: type,
            nullable: nullable,
            values: encoded,
            featureCount: featureCount)
    }

    private static func stringColumn(
        name: String,
        values: [any Sendable?],
        featureCount: Int
    ) throws -> MLTEncodedColumn {
        .property(
            name: name,
            type: .string,
            nullable: values.contains { $0 == nil },
            values: values.map { $0.map { MLTEncodedValue.string(stringValue($0)) } },
            featureCount: featureCount)
    }

    private static func int64Value(_ value: any Sendable, allowUnsigned: Bool) -> Int64? {
        switch value {
        case let value as Int: return Int64(exactly: value)
        case let value as Int8: return Int64(value)
        case let value as Int16: return Int64(value)
        case let value as Int32: return Int64(value)
        case let value as Int64: return value
        case let value as UInt where allowUnsigned: return Int64(exactly: value)
        case let value as UInt8 where allowUnsigned: return Int64(value)
        case let value as UInt16 where allowUnsigned: return Int64(value)
        case let value as UInt32 where allowUnsigned: return Int64(value)
        case let value as UInt64 where allowUnsigned: return Int64(exactly: value)
        default: return nil
        }
    }

    private static func uint64Value(_ value: any Sendable) -> UInt64? {
        switch value {
        case let value as UInt: return UInt64(exactly: value)
        case let value as UInt8: return UInt64(value)
        case let value as UInt16: return UInt64(value)
        case let value as UInt32: return UInt64(value)
        case let value as UInt64: return value
        case let value as Int where value >= 0: return UInt64(exactly: value)
        case let value as Int8 where value >= 0: return UInt64(value)
        case let value as Int16 where value >= 0: return UInt64(value)
        case let value as Int32 where value >= 0: return UInt64(value)
        case let value as Int64 where value >= 0: return UInt64(value)
        default: return nil
        }
    }

    private static func doubleValue(_ value: any Sendable) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as Float: return Double(value)
        case let value as Int: return Double(value)
        case let value as Int8: return Double(value)
        case let value as Int16: return Double(value)
        case let value as Int32: return Double(value)
        case let value as Int64: return Double(value)
        case let value as UInt: return Double(value)
        case let value as UInt8: return Double(value)
        case let value as UInt16: return Double(value)
        case let value as UInt32: return Double(value)
        case let value as UInt64: return Double(value)
        default: return nil
        }
    }

    private static func stringValue(_ value: any Sendable) -> String {
        if let value = value as? String { return value }
        if let value = value as? Bool { return value ? "true" : "false" }
        return String(describing: value)
    }

    // MARK: - Stream helpers

    private static func stream(
        physical: MLTPhysicalStreamType,
        logical: MLTLogicalStreamType,
        logical1: MLTLogicalTechnique,
        logical2: MLTLogicalTechnique,
        physicalTechnique: MLTPhysicalTechnique,
        values: [UInt32]
    ) throws -> MLTEncodedStream {
        var writer = MLTByteWriter()
        for value in values {
            writer.writeVarint32(value)
        }
        let metadata = MLTStreamMetadata(
            physicalStreamType: physical,
            logicalStreamType: logical,
            logicalTechnique1: logical1,
            logicalTechnique2: logical2,
            physicalTechnique: physicalTechnique,
            numValues: values.count,
            byteLength: writer.count)
        return MLTEncodedStream(metadata: metadata, payload: writer.bytes)
    }

}

// MARK: - Encoded model

private struct MLTEncodableFeature {
    var id: UInt64?
    var hasNumericID: Bool
    var geometry: MLTGeometry
    var properties: [String: Sendable]
}

private struct MLTEncodedStream {
    var metadata: MLTStreamMetadata
    var payload: [UInt8]

    func write(to writer: inout MLTByteWriter) {
        metadata.encode(to: &writer)
        writer.write(contentsOf: payload)
    }
}

private enum MLTEncodedValue {
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case string(String)
}

private enum MLTEncodedColumn {
    case id(nullable: Bool, longID: Bool, values: [UInt64?], featureCount: Int)
    case geometry(streams: [MLTEncodedStream])
    case property(
        name: String,
        type: MLTScalarType,
        nullable: Bool,
        values: [MLTEncodedValue?],
        featureCount: Int)

    var metadata: MLTColumn {
        switch self {
        case let .id(nullable, longID, _, _):
            return MLTColumn(
                name: "id",
                nullable: nullable,
                scope: .feature,
                kind: .id(longID: longID),
                children: [])
        case .geometry:
            return MLTColumn(
                name: "geometry",
                nullable: false,
                scope: .feature,
                kind: .geometry,
                children: [])
        case let .property(name, type, nullable, _, _):
            return MLTColumn(
                name: name,
                nullable: nullable,
                scope: .feature,
                kind: .scalar(type),
                children: [])
        }
    }

    func writeStreams(to writer: inout MLTByteWriter) throws {
        switch self {
        case let .id(nullable, longID, values, featureCount):
            if nullable {
                try Self.writePresentStream(
                    values: values.map { $0 != nil },
                    featureCount: featureCount,
                    to: &writer)
            }
            var payload = MLTByteWriter()
            for value in values.compactMap({ $0 }) {
                if longID {
                    payload.writeVarint64(value)
                }
                else {
                    payload.writeVarint32(UInt32(truncatingIfNeeded: value))
                }
            }
            let metadata = MLTStreamMetadata(
                physicalStreamType: .data,
                logicalStreamType: .dictionary(.none),
                logicalTechnique1: .none,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: values.compactMap({ $0 }).count,
                byteLength: payload.count)
            MLTEncodedStream(metadata: metadata, payload: payload.bytes).write(to: &writer)

        case let .geometry(streams):
            writer.writeVarint32(UInt32(streams.count))
            for stream in streams {
                stream.write(to: &writer)
            }

        case let .property(_, type, nullable, values, featureCount):
            if type == .string {
                writer.writeVarint32(UInt32(2 + (nullable ? 1 : 0)))
            }
            if nullable {
                try Self.writePresentStream(
                    values: values.map { $0 != nil },
                    featureCount: featureCount,
                    to: &writer)
            }

            let dense = values.compactMap { $0 }
            switch type {
            case .boolean:
                let bools: [Bool] = dense.map {
                    if case let .bool(value) = $0 { return value }
                    return false
                }
                let packed = MLTByteRLE.packBool(bools)
                let encoded = MLTByteRLE.encode(packed)
                let metadata = MLTStreamMetadata(
                    physicalStreamType: .data,
                    logicalStreamType: .dictionary(.none),
                    logicalTechnique1: .rle,
                    logicalTechnique2: .none,
                    physicalTechnique: .none,
                    numValues: bools.count,
                    byteLength: encoded.count)
                MLTEncodedStream(metadata: metadata, payload: encoded).write(to: &writer)

            case .int32, .int64:
                var payload = MLTByteWriter()
                let isLong = type == .int64
                for value in dense {
                    guard case let .int(int) = value else {
                        throw MLTError.invalidData("Unexpected value type in integer column")
                    }
                    if isLong {
                        payload.writeVarint64(MLTZigZag.encode(int))
                    }
                    else {
                        payload.writeVarint32(MLTZigZag.encode(Int32(truncatingIfNeeded: int)))
                    }
                }
                let metadata = MLTStreamMetadata(
                    physicalStreamType: .data,
                    logicalStreamType: .dictionary(.none),
                    logicalTechnique1: .none,
                    logicalTechnique2: .none,
                    physicalTechnique: .varint,
                    numValues: dense.count,
                    byteLength: payload.count)
                MLTEncodedStream(metadata: metadata, payload: payload.bytes).write(to: &writer)

            case .uint32, .uint64:
                var payload = MLTByteWriter()
                let isLong = type == .uint64
                for value in dense {
                    guard case let .uint(uint) = value else {
                        throw MLTError.invalidData("Unexpected value type in unsigned column")
                    }
                    if isLong {
                        payload.writeVarint64(uint)
                    }
                    else {
                        payload.writeVarint32(UInt32(truncatingIfNeeded: uint))
                    }
                }
                let metadata = MLTStreamMetadata(
                    physicalStreamType: .data,
                    logicalStreamType: .dictionary(.none),
                    logicalTechnique1: .none,
                    logicalTechnique2: .none,
                    physicalTechnique: .varint,
                    numValues: dense.count,
                    byteLength: payload.count)
                MLTEncodedStream(metadata: metadata, payload: payload.bytes).write(to: &writer)

            case .float, .double:
                var payload = MLTByteWriter()
                let isDouble = type == .double
                for value in dense {
                    guard case let .double(double) = value else {
                        throw MLTError.invalidData("Unexpected value type in floating-point column")
                    }
                    if isDouble {
                        payload.writeUInt64(Double(double).bitPattern)
                    }
                    else {
                        payload.writeUInt32(Float(double).bitPattern)
                    }
                }
                let metadata = MLTStreamMetadata(
                    physicalStreamType: .data,
                    logicalStreamType: .dictionary(.none),
                    logicalTechnique1: .none,
                    logicalTechnique2: .none,
                    physicalTechnique: .none,
                    numValues: dense.count,
                    byteLength: payload.count)
                MLTEncodedStream(metadata: metadata, payload: payload.bytes).write(to: &writer)

            case .string:
                var lengthWriter = MLTByteWriter()
                var data: [UInt8] = []
                data.reserveCapacity(dense.count * 8)
                for value in dense {
                    guard case let .string(string) = value else {
                        throw MLTError.invalidData("Unexpected value type in string column")
                    }
                    let utf8 = Array(string.utf8)
                    lengthWriter.writeVarint32(UInt32(utf8.count))
                    data.append(contentsOf: utf8)
                }
                let lengthMetadata = MLTStreamMetadata(
                    physicalStreamType: .length,
                    logicalStreamType: .length(.varBinary),
                    logicalTechnique1: .none,
                    logicalTechnique2: .none,
                    physicalTechnique: .varint,
                    numValues: dense.count,
                    byteLength: lengthWriter.count)
                MLTEncodedStream(metadata: lengthMetadata, payload: lengthWriter.bytes).write(to: &writer)

                let dataMetadata = MLTStreamMetadata(
                    physicalStreamType: .data,
                    logicalStreamType: .dictionary(.none),
                    logicalTechnique1: .none,
                    logicalTechnique2: .none,
                    physicalTechnique: .none,
                    numValues: dense.count,
                    byteLength: data.count)
                MLTEncodedStream(metadata: dataMetadata, payload: data).write(to: &writer)

            case .int8, .uint8:
                throw MLTError.unsupported("8-bit property columns")
            }
        }
    }

    private static func writePresentStream(
        values: [Bool],
        featureCount: Int,
        to writer: inout MLTByteWriter
    ) throws {
        guard values.count == featureCount else {
            throw MLTError.invalidData("Present stream count mismatch")
        }
        let packed = MLTByteRLE.packBool(values)
        let encoded = MLTByteRLE.encode(packed)
        let metadata = MLTStreamMetadata(
            physicalStreamType: .present,
            logicalStreamType: .none,
            logicalTechnique1: .rle,
            logicalTechnique2: .none,
            physicalTechnique: .none,
            numValues: featureCount,
            byteLength: encoded.count)
        MLTEncodedStream(metadata: metadata, payload: encoded).write(to: &writer)
    }

}

// MARK: - Geometry conversion

extension MLTEncoderSwift {

    fileprivate static func encodeGeometry(
        _ geometry: GeoJsonGeometry,
        project: (Coordinate3D) -> (Int, Int)
    ) -> MLTGeometry? {
        switch geometry.type {
        case .point:
            guard let point = geometry as? Point else { return nil }
            return .point(tileCoordinate(point.coordinate, project: project))

        case .multiPoint:
            guard let multiPoint = geometry as? MultiPoint else { return nil }
            return .multiPoint(multiPoint.coordinates.map { tileCoordinate($0, project: project) })

        case .lineString:
            guard let line = geometry as? LineString else { return nil }
            return .lineString(line.coordinates.map { tileCoordinate($0, project: project) })

        case .multiLineString:
            guard let multiLine = geometry as? MultiLineString else { return nil }
            return .multiLineString(
                multiLine.coordinates.map { line in
                    line.map { tileCoordinate($0, project: project) }
                })

        case .polygon:
            guard let polygon = geometry as? Polygon else { return nil }
            let rings = polygon.rings.map { ring -> [MLTTileCoordinate] in
                var coordinates = ring.coordinates.map { tileCoordinate($0, project: project) }
                if coordinates.count > 1, coordinates.first == coordinates.last {
                    coordinates.removeLast()
                }
                return coordinates
            }
            return .polygon(normalizePolygonWinding(rings))

        case .multiPolygon:
            guard let multiPolygon = geometry as? MultiPolygon else { return nil }
            let polygons = multiPolygon.coordinates.map { polygon -> [[MLTTileCoordinate]] in
                let rings = polygon.map { ring -> [MLTTileCoordinate] in
                    var coordinates = ring.map { tileCoordinate($0, project: project) }
                    if coordinates.count > 1, coordinates.first == coordinates.last {
                        coordinates.removeLast()
                    }
                    return coordinates
                }
                return normalizePolygonWinding(rings)
            }
            return .multiPolygon(polygons)

        default:
            return nil
        }
    }

    private static func tileCoordinate(
        _ coordinate: Coordinate3D,
        project: (Coordinate3D) -> (Int, Int)
    ) -> MLTTileCoordinate {
        let projected = project(coordinate)
        return MLTTileCoordinate(
            x: Int32(clamping: projected.0),
            y: Int32(clamping: projected.1))
    }

    private static func tileArea(_ ring: [MLTTileCoordinate]) -> Double {
        guard ring.count > 2 else { return 0.0 }
        var sum = 0.0
        for index in ring.indices {
            let current = ring[index]
            let next = ring[(index + 1) % ring.count]
            sum += Double(next.x - current.x) * Double(current.y + next.y)
        }
        return sum
    }

    private static func normalizePolygonWinding(
        _ rings: [[MLTTileCoordinate]]
    ) -> [[MLTTileCoordinate]] {
        guard var exterior = rings.first else { return rings }
        if tileArea(exterior) > 0 {
            exterior.reverse()
        }
        var result: [[MLTTileCoordinate]] = [exterior]
        for hole in rings.dropFirst() {
            var value = hole
            if tileArea(value) < 0 {
                value.reverse()
            }
            result.append(value)
        }
        return result
    }

}

#endif
