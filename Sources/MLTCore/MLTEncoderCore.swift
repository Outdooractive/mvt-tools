import Foundation

/// A feature ready to be encoded into MLT.
package struct MLTEncodableFeature {

    package var id: UInt64?
    package var hasNumericID: Bool
    package var geometry: MLTGeometry
    package var properties: [String: any Sendable]

    package init(
        id: UInt64?,
        hasNumericID: Bool,
        geometry: MLTGeometry,
        properties: [String: any Sendable]
    ) {
        self.id = id
        self.hasNumericID = hasNumericID
        self.geometry = geometry
        self.properties = properties
    }

}

/// A layer ready to be encoded into MLT.
package struct MLTEncodableLayer {

    package var name: String
    package var extent: Int
    package var features: [MLTEncodableFeature]

    package init(name: String, extent: Int, features: [MLTEncodableFeature]) {
        self.name = name
        self.extent = extent
        self.features = features
    }

}

/// Encodes neutral MLT layers into a tag `0x01` tile.
package enum MLTEncoderCore {

    package static func encode(layers: [MLTEncodableLayer]) throws -> Data {
        var tileWriter = MLTByteWriter()

        for layer in layers.sorted(by: { $0.name < $1.name }) {
            guard !layer.name.isEmpty, !layer.features.isEmpty else {
                continue
            }

            let body = try encodeLayer(
                name: layer.name,
                extent: layer.extent,
                features: layer.features)
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
            let values: [(any Sendable)?] = features.map { $0.properties[key] }
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

    private static func inferScalarType(_ values: [(any Sendable)?]) -> MLTScalarType {
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
        values: [(any Sendable)?],
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

        if type == .string {
            return try makeStringColumn(
                name: name,
                values: encoded,
                featureCount: featureCount)
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
        values: [(any Sendable)?],
        featureCount: Int
    ) throws -> MLTEncodedColumn {
        try makeStringColumn(
            name: name,
            values: values.map { $0.map { MLTEncodedValue.string(stringValue($0)) } },
            featureCount: featureCount)
    }

    private static func makeStringColumn(
        name: String,
        values: [MLTEncodedValue?],
        featureCount: Int
    ) throws -> MLTEncodedColumn {
        let denseStrings = values.compactMap { value -> String? in
            if case let .string(string) = value { return string }
            return nil
        }
        let nullable = values.contains { $0 == nil }

        let plainSize = encodedStringSize(denseStrings)
        let dictionary = buildStringDictionary(denseStrings)
        let dictionarySize = dictionary.map {
            encodedStringSize($0.dictionary)
                + encodedOffsetSize($0.offsets)
                + 16
        } ?? Int.max

        let encoding: MLTStringEncoding
        if dictionarySize < plainSize, let dictionary {
            encoding = .dictionary(dictionary: dictionary.dictionary, offsets: dictionary.offsets)
        }
        else {
            encoding = .plain
        }

        return .stringProperty(
            name: name,
            nullable: nullable,
            values: values,
            featureCount: featureCount,
            encoding: encoding)
    }

    private static func buildStringDictionary(
        _ strings: [String]
    ) -> (dictionary: [String], offsets: [UInt32])? {
        guard strings.count > 1 else { return nil }

        var indexByString: [String: UInt32] = [:]
        var dictionary: [String] = []
        var offsets: [UInt32] = []
        offsets.reserveCapacity(strings.count)

        for string in strings {
            if let index = indexByString[string] {
                offsets.append(index)
            }
            else {
                let index = UInt32(dictionary.count)
                indexByString[string] = index
                dictionary.append(string)
                offsets.append(index)
            }
        }

        return dictionary.count < strings.count
            ? (dictionary, offsets)
            : nil
    }

    private static func encodedStringSize(_ strings: [String]) -> Int {
        var lengthWriter = MLTByteWriter()
        var dataSize = 0
        for string in strings {
            let utf8 = Array(string.utf8)
            lengthWriter.writeVarint32(UInt32(utf8.count))
            dataSize += utf8.count
        }
        return lengthWriter.count + dataSize
    }

    private static func encodedOffsetSize(_ offsets: [UInt32]) -> Int {
        var writer = MLTByteWriter()
        for offset in offsets {
            writer.writeVarint32(offset)
        }
        return writer.count
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

private enum MLTStringEncoding {
    case plain
    case dictionary(dictionary: [String], offsets: [UInt32])

    var isPlain: Bool {
        if case .plain = self { return true }
        return false
    }
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
    case stringProperty(
        name: String,
        nullable: Bool,
        values: [MLTEncodedValue?],
        featureCount: Int,
        encoding: MLTStringEncoding)

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
        case let .stringProperty(name, nullable, _, _, _):
            return MLTColumn(
                name: name,
                nullable: nullable,
                scope: .feature,
                kind: .scalar(.string),
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

        case let .stringProperty(_, nullable, values, featureCount, encoding):
            let streamCount = (nullable ? 1 : 0) + (encoding.isPlain ? 2 : 3)
            writer.writeVarint32(UInt32(streamCount))
            if nullable {
                try Self.writePresentStream(
                    values: values.map { $0 != nil },
                    featureCount: featureCount,
                    to: &writer)
            }

            let denseStrings = values.compactMap { value -> String? in
                if case let .string(string) = value { return string }
                return nil
            }

            switch encoding {
            case .plain:
                var lengthWriter = MLTByteWriter()
                var data: [UInt8] = []
                data.reserveCapacity(denseStrings.count * 8)
                for string in denseStrings {
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
                    numValues: denseStrings.count,
                    byteLength: lengthWriter.count)
                MLTEncodedStream(metadata: lengthMetadata, payload: lengthWriter.bytes).write(to: &writer)

                let dataMetadata = MLTStreamMetadata(
                    physicalStreamType: .data,
                    logicalStreamType: .dictionary(.none),
                    logicalTechnique1: .none,
                    logicalTechnique2: .none,
                    physicalTechnique: .none,
                    numValues: denseStrings.count,
                    byteLength: data.count)
                MLTEncodedStream(metadata: dataMetadata, payload: data).write(to: &writer)

            case let .dictionary(dictionary, offsets):
                var dictionaryLengthWriter = MLTByteWriter()
                var dictionaryData: [UInt8] = []
                dictionaryData.reserveCapacity(dictionary.count * 8)
                for string in dictionary {
                    let utf8 = Array(string.utf8)
                    dictionaryLengthWriter.writeVarint32(UInt32(utf8.count))
                    dictionaryData.append(contentsOf: utf8)
                }

                let dictionaryLengthMetadata = MLTStreamMetadata(
                    physicalStreamType: .length,
                    logicalStreamType: .length(.dictionary),
                    logicalTechnique1: .none,
                    logicalTechnique2: .none,
                    physicalTechnique: .varint,
                    numValues: dictionary.count,
                    byteLength: dictionaryLengthWriter.count)
                MLTEncodedStream(
                    metadata: dictionaryLengthMetadata,
                    payload: dictionaryLengthWriter.bytes).write(to: &writer)

                var offsetWriter = MLTByteWriter()
                for offset in offsets {
                    offsetWriter.writeVarint32(offset)
                }
                let offsetMetadata = MLTStreamMetadata(
                    physicalStreamType: .offset,
                    logicalStreamType: .offset(.string),
                    logicalTechnique1: .none,
                    logicalTechnique2: .none,
                    physicalTechnique: .varint,
                    numValues: offsets.count,
                    byteLength: offsetWriter.count)
                MLTEncodedStream(
                    metadata: offsetMetadata,
                    payload: offsetWriter.bytes).write(to: &writer)

                let dictionaryDataMetadata = MLTStreamMetadata(
                    physicalStreamType: .data,
                    logicalStreamType: .dictionary(.single),
                    logicalTechnique1: .none,
                    logicalTechnique2: .none,
                    physicalTechnique: .none,
                    numValues: dictionary.count,
                    byteLength: dictionaryData.count)
                MLTEncodedStream(
                    metadata: dictionaryDataMetadata,
                    payload: dictionaryData).write(to: &writer)
            }

        case let .property(_, type, nullable, values, featureCount):
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

            case .int8, .uint8:
                throw MLTError.unsupported("8-bit property columns")

            case .string:
                throw MLTError.invalidData("String columns must use stringProperty")
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

