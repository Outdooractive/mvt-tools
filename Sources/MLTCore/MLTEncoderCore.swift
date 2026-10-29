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
        streams.append(encodedUInt32Stream(
            values: types,
            physical: .data,
            logical: .dictionary(.none)))

        if !numGeometries.isEmpty {
            streams.append(encodedUInt32Stream(
                values: numGeometries,
                physical: .length,
                logical: .length(.geometries)))
        }
        if !numParts.isEmpty {
            streams.append(encodedUInt32Stream(
                values: numParts,
                physical: .length,
                logical: .length(.parts)))
        }
        if !numRings.isEmpty {
            streams.append(encodedUInt32Stream(
                values: numRings,
                physical: .length,
                logical: .length(.rings)))
        }

        let plainVertex = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: .data,
                logicalStreamType: .dictionary(.vertex),
                logicalTechnique1: .componentwiseDelta,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: vertices.count * 2,
                byteLength: encodeVertices(vertices).count),
            payload: encodeVertices(vertices))

        if let dictionary = makeVertexDictionary(vertices),
           dictionary.offset.encodedSize + dictionary.data.encodedSize < plainVertex.encodedSize
        {
            streams.append(dictionary.offset)
            streams.append(dictionary.data)
        }
        else {
            streams.append(plainVertex)
        }

        return .geometry(streams: streams)
    }

    private struct VertexDictionary {
        var offset: MLTEncodedStream
        var data: MLTEncodedStream
    }

    private static func makeVertexDictionary(
        _ vertices: [MLTTileCoordinate]
    ) -> VertexDictionary? {
        guard vertices.count > 1 else { return nil }

        var indexByVertex: [MLTTileCoordinate: UInt32] = [:]
        var uniqueVertices: [MLTTileCoordinate] = []
        var offsets: [UInt32] = []
        offsets.reserveCapacity(vertices.count)

        for vertex in vertices {
            if let index = indexByVertex[vertex] {
                offsets.append(index)
            }
            else {
                let index = UInt32(uniqueVertices.count)
                indexByVertex[vertex] = index
                uniqueVertices.append(vertex)
                offsets.append(index)
            }
        }

        guard uniqueVertices.count < vertices.count else {
            return nil
        }

        let minX = uniqueVertices.map(\.x).min() ?? 0
        let minY = uniqueVertices.map(\.y).min() ?? 0
        let maxX = uniqueVertices.map(\.x).max() ?? 0
        let maxY = uniqueVertices.map(\.y).max() ?? 0
        let range = max(Int64(maxX) - Int64(minX), Int64(maxY) - Int64(minY))
        let bits = MLTHilbert.bits(for: range)

        let sorted = uniqueVertices.indices.sorted { lhsIndex, rhsIndex in
            let lhs = uniqueVertices[lhsIndex]
            let rhs = uniqueVertices[rhsIndex]
            let lhsCode = MLTHilbert.index(
                x: lhs.x, y: lhs.y, minX: minX, minY: minY, bits: bits)
            let rhsCode = MLTHilbert.index(
                x: rhs.x, y: rhs.y, minX: minX, minY: minY, bits: bits)
            if lhsCode != rhsCode { return lhsCode < rhsCode }
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            return lhs.y < rhs.y
        }

        var oldToNew = [UInt32](repeating: 0, count: uniqueVertices.count)
        for (newIndex, oldIndex) in sorted.enumerated() {
            oldToNew[oldIndex] = UInt32(newIndex)
        }
        let sortedVertices = sorted.map { uniqueVertices[$0] }
        let sortedOffsets = offsets.map { oldToNew[Int($0)] }

        let vertexPayload = encodeVertices(sortedVertices)
        let data = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: .data,
                logicalStreamType: .dictionary(.vertex),
                logicalTechnique1: .componentwiseDelta,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: sortedVertices.count * 2,
                byteLength: vertexPayload.count),
            payload: vertexPayload)

        var offsetWriter = MLTByteWriter()
        for offset in sortedOffsets {
            offsetWriter.writeVarint32(offset)
        }
        let offset = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: .offset,
                logicalStreamType: .offset(.vertex),
                logicalTechnique1: .none,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: sortedOffsets.count,
                byteLength: offsetWriter.count),
            payload: offsetWriter.bytes)

        return VertexDictionary(offset: offset, data: data)
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

        var inferredTypes: [String: MLTScalarType] = [:]
        for key in keys.sorted() {
            let values: [(any Sendable)?] = features.map { $0.properties[key] }
            guard values.contains(where: { $0 != nil }) else { continue }
            inferredTypes[key] = inferScalarType(values)
        }

        let stringKeys = inferredTypes
            .filter { $0.value == .string }
            .map(\.key)
        let groups = sharedStringGroups(stringKeys)
        var groupedKeys = Set<String>()
        var columns: [MLTEncodedColumn] = []

        for group in groups {
            groupedKeys.formUnion(group.keys)
            columns.append(
                try makeSharedStringColumn(
                    root: group.root,
                    keys: group.keys,
                    features: features))
        }

        for key in inferredTypes.keys.sorted() where !groupedKeys.contains(key) {
            let values: [(any Sendable)?] = features.map { $0.properties[key] }
            columns.append(
                try makePropertyColumn(
                    name: key,
                    type: inferredTypes[key] ?? .string,
                    values: values,
                    featureCount: features.count))
        }

        return columns
    }

    private struct SharedStringGroup {
        var root: String
        var keys: [String]
    }

    private static func sharedStringGroups(_ keys: [String]) -> [SharedStringGroup] {
        var byRoot: [String: [String]] = [:]

        for key in keys {
            guard let separator = key.firstIndex(of: "_"), separator != key.startIndex else {
                continue
            }
            let root = String(key[..<separator])
            byRoot[root, default: []].append(key)
        }

        return byRoot.compactMap { root, members in
            guard members.count > 1 else { return nil }
            return SharedStringGroup(root: root, keys: members.sorted())
        }
        .sorted { $0.root < $1.root }
    }

    private static func makeSharedStringColumn(
        root: String,
        keys: [String],
        features: [MLTEncodableFeature]
    ) throws -> MLTEncodedColumn {
        let children = keys.map { key -> MLTSharedStringChild in
            let suffix = key == root ? "" : String(key.dropFirst(root.count))
            let values = features.map { feature -> MLTEncodedValue? in
                guard let value = feature.properties[key] else { return nil }
                return .string(stringValue(value))
            }
            return MLTSharedStringChild(name: suffix, values: values)
        }

        return .sharedStringProperty(
            rootName: root,
            children: children,
            featureCount: features.count)
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

    fileprivate static func encodedUInt32Stream(
        values: [UInt32],
        physical: MLTPhysicalStreamType,
        logical: MLTLogicalStreamType
    ) -> MLTEncodedStream {
        var plainWriter = MLTByteWriter()
        for value in values {
            plainWriter.writeVarint32(value)
        }
        let plain = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .none,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: values.count,
                byteLength: plainWriter.count),
            payload: plainWriter.bytes)

        var deltaWriter = MLTByteWriter()
        var previous: UInt32 = 0
        for value in values {
            deltaWriter.writeVarint32(MLTZigZag.encode(Int32(bitPattern: value &- previous)))
            previous = value
        }
        let delta = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .delta,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: values.count,
                byteLength: deltaWriter.count),
            payload: deltaWriter.bytes)

        let runs = buildRuns(values)
        guard !runs.isEmpty else {
            return plain
        }

        var rleWriter = MLTByteWriter()
        for run in runs {
            rleWriter.writeVarint32(run.length)
        }
        for run in runs {
            rleWriter.writeVarint32(run.value)
        }
        let rle = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .rle,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: runs.count * 2,
                byteLength: rleWriter.count,
                runs: runs.count,
                numRleValues: values.count),
            payload: rleWriter.bytes)

        var deltaRleWriter = MLTByteWriter()
        for run in runs {
            deltaRleWriter.writeVarint32(run.length)
        }
        var previousRunValue: UInt32 = 0
        for run in runs {
            let deltaValue = run.value &- previousRunValue
            deltaRleWriter.writeVarint32(MLTZigZag.encode(Int32(bitPattern: deltaValue)))
            previousRunValue = run.value
        }
        let deltaRle = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .delta,
                logicalTechnique2: .rle,
                physicalTechnique: .varint,
                numValues: runs.count * 2,
                byteLength: deltaRleWriter.count,
                runs: runs.count,
                numRleValues: values.count),
            payload: deltaRleWriter.bytes)

        return [plain, delta, rle, deltaRle].min {
            $0.encodedSize < $1.encodedSize
        } ?? plain
    }

    fileprivate static func encodedUInt64Stream(
        values: [UInt64],
        physical: MLTPhysicalStreamType,
        logical: MLTLogicalStreamType
    ) -> MLTEncodedStream {
        var plainWriter = MLTByteWriter()
        for value in values {
            plainWriter.writeVarint64(value)
        }
        let plain = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .none,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: values.count,
                byteLength: plainWriter.count),
            payload: plainWriter.bytes)

        var deltaWriter = MLTByteWriter()
        var previous: UInt64 = 0
        for value in values {
            deltaWriter.writeVarint64(MLTZigZag.encode(Int64(bitPattern: value &- previous)))
            previous = value
        }
        let delta = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .delta,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: values.count,
                byteLength: deltaWriter.count),
            payload: deltaWriter.bytes)

        let runs = buildRuns64(values)
        guard !runs.isEmpty else {
            return plain
        }

        var rleWriter = MLTByteWriter()
        for run in runs {
            rleWriter.writeVarint64(UInt64(run.length))
        }
        for run in runs {
            rleWriter.writeVarint64(run.value)
        }
        let rle = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .rle,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: runs.count * 2,
                byteLength: rleWriter.count,
                runs: runs.count,
                numRleValues: values.count),
            payload: rleWriter.bytes)

        var deltaRleWriter = MLTByteWriter()
        for run in runs {
            deltaRleWriter.writeVarint64(UInt64(run.length))
        }
        var previousRunValue: UInt64 = 0
        for run in runs {
            let deltaValue = run.value &- previousRunValue
            deltaRleWriter.writeVarint64(MLTZigZag.encode(Int64(bitPattern: deltaValue)))
            previousRunValue = run.value
        }
        let deltaRle = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .delta,
                logicalTechnique2: .rle,
                physicalTechnique: .varint,
                numValues: runs.count * 2,
                byteLength: deltaRleWriter.count,
                runs: runs.count,
                numRleValues: values.count),
            payload: deltaRleWriter.bytes)

        return [plain, delta, rle, deltaRle].min {
            $0.encodedSize < $1.encodedSize
        } ?? plain
    }

    fileprivate static func encodedInt32Stream(
        values: [Int32],
        physical: MLTPhysicalStreamType,
        logical: MLTLogicalStreamType
    ) -> MLTEncodedStream {
        var plainWriter = MLTByteWriter()
        for value in values {
            plainWriter.writeVarint32(MLTZigZag.encode(value))
        }
        let plain = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .none,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: values.count,
                byteLength: plainWriter.count),
            payload: plainWriter.bytes)

        var deltaWriter = MLTByteWriter()
        var previous: Int32 = 0
        for value in values {
            deltaWriter.writeVarint32(MLTZigZag.encode(value &- previous))
            previous = value
        }
        let delta = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .delta,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: values.count,
                byteLength: deltaWriter.count),
            payload: deltaWriter.bytes)

        let runs = buildRuns32(values)
        guard !runs.isEmpty else {
            return plain
        }

        var rleWriter = MLTByteWriter()
        for run in runs {
            rleWriter.writeVarint32(UInt32(run.length))
        }
        for run in runs {
            rleWriter.writeVarint32(MLTZigZag.encode(run.value))
        }
        let rle = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .rle,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: runs.count * 2,
                byteLength: rleWriter.count,
                runs: runs.count,
                numRleValues: values.count),
            payload: rleWriter.bytes)

        var deltaRleWriter = MLTByteWriter()
        for run in runs {
            deltaRleWriter.writeVarint32(UInt32(run.length))
        }
        var previousRunValue: Int32 = 0
        for run in runs {
            deltaRleWriter.writeVarint32(MLTZigZag.encode(run.value &- previousRunValue))
            previousRunValue = run.value
        }
        let deltaRle = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .delta,
                logicalTechnique2: .rle,
                physicalTechnique: .varint,
                numValues: runs.count * 2,
                byteLength: deltaRleWriter.count,
                runs: runs.count,
                numRleValues: values.count),
            payload: deltaRleWriter.bytes)

        return [plain, delta, rle, deltaRle].min {
            $0.encodedSize < $1.encodedSize
        } ?? plain
    }

    fileprivate static func encodedInt64Stream(
        values: [Int64],
        physical: MLTPhysicalStreamType,
        logical: MLTLogicalStreamType
    ) -> MLTEncodedStream {
        var plainWriter = MLTByteWriter()
        for value in values {
            plainWriter.writeVarint64(MLTZigZag.encode(value))
        }
        let plain = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .none,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: values.count,
                byteLength: plainWriter.count),
            payload: plainWriter.bytes)

        var deltaWriter = MLTByteWriter()
        var previous: Int64 = 0
        for value in values {
            deltaWriter.writeVarint64(MLTZigZag.encode(value &- previous))
            previous = value
        }
        let delta = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .delta,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: values.count,
                byteLength: deltaWriter.count),
            payload: deltaWriter.bytes)

        let runs = buildRuns64(values)
        guard !runs.isEmpty else {
            return plain
        }

        var rleWriter = MLTByteWriter()
        for run in runs {
            rleWriter.writeVarint64(UInt64(run.length))
        }
        for run in runs {
            rleWriter.writeVarint64(MLTZigZag.encode(run.value))
        }
        let rle = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .rle,
                logicalTechnique2: .none,
                physicalTechnique: .varint,
                numValues: runs.count * 2,
                byteLength: rleWriter.count,
                runs: runs.count,
                numRleValues: values.count),
            payload: rleWriter.bytes)

        var deltaRleWriter = MLTByteWriter()
        for run in runs {
            deltaRleWriter.writeVarint64(UInt64(run.length))
        }
        var previousRunValue: Int64 = 0
        for run in runs {
            deltaRleWriter.writeVarint64(MLTZigZag.encode(run.value &- previousRunValue))
            previousRunValue = run.value
        }
        let deltaRle = MLTEncodedStream(
            metadata: MLTStreamMetadata(
                physicalStreamType: physical,
                logicalStreamType: logical,
                logicalTechnique1: .delta,
                logicalTechnique2: .rle,
                physicalTechnique: .varint,
                numValues: runs.count * 2,
                byteLength: deltaRleWriter.count,
                runs: runs.count,
                numRleValues: values.count),
            payload: deltaRleWriter.bytes)

        return [plain, delta, rle, deltaRle].min {
            $0.encodedSize < $1.encodedSize
        } ?? plain
    }

    private struct UInt64Run {
        var length: Int
        var value: UInt64
    }

    private static func buildRuns64(_ values: [UInt64]) -> [UInt64Run] {
        var runs: [UInt64Run] = []
        var index = 0
        while index < values.count {
            let value = values[index]
            var end = index + 1
            while end < values.count, values[end] == value {
                end += 1
            }
            runs.append(UInt64Run(length: end - index, value: value))
            index = end
        }
        return runs
    }

    private struct Int32Run {
        var length: Int
        var value: Int32
    }

    private static func buildRuns32(_ values: [Int32]) -> [Int32Run] {
        var runs: [Int32Run] = []
        var index = 0
        while index < values.count {
            let value = values[index]
            var end = index + 1
            while end < values.count, values[end] == value {
                end += 1
            }
            runs.append(Int32Run(length: end - index, value: value))
            index = end
        }
        return runs
    }

    private struct Int64Run {
        var length: Int
        var value: Int64
    }

    private static func buildRuns64(_ values: [Int64]) -> [Int64Run] {
        var runs: [Int64Run] = []
        var index = 0
        while index < values.count {
            let value = values[index]
            var end = index + 1
            while end < values.count, values[end] == value {
                end += 1
            }
            runs.append(Int64Run(length: end - index, value: value))
            index = end
        }
        return runs
    }

    private struct UInt32Run {
        var length: UInt32
        var value: UInt32
    }

    private static func buildRuns(_ values: [UInt32]) -> [UInt32Run] {
        var runs: [UInt32Run] = []
        var index = 0
        while index < values.count {
            let value = values[index]
            var end = index + 1
            while end < values.count, values[end] == value {
                end += 1
            }
            runs.append(UInt32Run(length: UInt32(end - index), value: value))
            index = end
        }
        return runs
    }
}

// MARK: - Encoded model

private struct MLTEncodedStream {
    var metadata: MLTStreamMetadata
    var payload: [UInt8]

    var encodedSize: Int {
        var writer = MLTByteWriter()
        write(to: &writer)
        return writer.count
    }

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

private struct MLTSharedStringChild {
    var name: String
    var values: [MLTEncodedValue?]
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
    case sharedStringProperty(
        rootName: String,
        children: [MLTSharedStringChild],
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
        case let .stringProperty(name, nullable, _, _, _):
            return MLTColumn(
                name: name,
                nullable: nullable,
                scope: .feature,
                kind: .scalar(.string),
                children: [])
        case let .sharedStringProperty(rootName, children, _):
            return MLTColumn(
                name: rootName,
                nullable: false,
                scope: .feature,
                kind: .structure,
                children: children.map {
                    MLTColumn(
                        name: $0.name,
                        nullable: true,
                        scope: .feature,
                        kind: .scalar(.string),
                        children: [])
                })
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
            let denseIDs = values.compactMap { $0 }
            if longID {
                MLTEncoderCore.encodedUInt64Stream(
                    values: denseIDs,
                    physical: .data,
                    logical: .dictionary(.none)).write(to: &writer)
            }
            else {
                MLTEncoderCore.encodedUInt32Stream(
                    values: denseIDs.map { UInt32(truncatingIfNeeded: $0) },
                    physical: .data,
                    logical: .dictionary(.none)).write(to: &writer)
            }

        case let .geometry(streams):
            writer.writeVarint32(UInt32(streams.count))
            for stream in streams {
                stream.write(to: &writer)
            }

        case let .sharedStringProperty(rootName, children, featureCount):
            _ = rootName
            var dictionary: [String] = []
            var indexByString: [String: UInt32] = [:]
            var childOffsets: [[UInt32]] = []
            childOffsets.reserveCapacity(children.count)

            for child in children {
                var offsets: [UInt32] = []
                for value in child.values {
                    guard let value else { continue }
                    guard case let .string(string) = value else {
                        throw MLTError.invalidData("Unexpected value type in shared dictionary column")
                    }
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
                childOffsets.append(offsets)
            }

            writer.writeVarint32(UInt32(2 + children.count * 2))

            var dictionaryLengths: [UInt32] = []
            var dictionaryData: [UInt8] = []
            for string in dictionary {
                let utf8 = Array(string.utf8)
                dictionaryLengths.append(UInt32(utf8.count))
                dictionaryData.append(contentsOf: utf8)
            }
            MLTEncoderCore.encodedUInt32Stream(
                values: dictionaryLengths,
                physical: .length,
                logical: .length(.dictionary)).write(to: &writer)

            let dictionaryDataMetadata = MLTStreamMetadata(
                physicalStreamType: .data,
                logicalStreamType: .dictionary(.shared),
                logicalTechnique1: .none,
                logicalTechnique2: .none,
                physicalTechnique: .none,
                numValues: dictionary.count,
                byteLength: dictionaryData.count)
            MLTEncodedStream(
                metadata: dictionaryDataMetadata,
                payload: dictionaryData).write(to: &writer)

            for (index, child) in children.enumerated() {
                let dense = child.values.compactMap { $0 }
                if dense.isEmpty {
                    writer.writeVarint32(0)
                    continue
                }

                writer.writeVarint32(2)
                try Self.writePresentStream(
                    values: child.values.map { $0 != nil },
                    featureCount: featureCount,
                    to: &writer)

                MLTEncoderCore.encodedUInt32Stream(
                    values: childOffsets[index],
                    physical: .offset,
                    logical: .offset(.string)).write(to: &writer)
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
                var lengths: [UInt32] = []
                var data: [UInt8] = []
                lengths.reserveCapacity(denseStrings.count)
                data.reserveCapacity(denseStrings.count * 8)
                for string in denseStrings {
                    let utf8 = Array(string.utf8)
                    lengths.append(UInt32(utf8.count))
                    data.append(contentsOf: utf8)
                }
                MLTEncoderCore.encodedUInt32Stream(
                    values: lengths,
                    physical: .length,
                    logical: .length(.varBinary)).write(to: &writer)

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
                var dictionaryLengths: [UInt32] = []
                var dictionaryData: [UInt8] = []
                dictionaryLengths.reserveCapacity(dictionary.count)
                dictionaryData.reserveCapacity(dictionary.count * 8)
                for string in dictionary {
                    let utf8 = Array(string.utf8)
                    dictionaryLengths.append(UInt32(utf8.count))
                    dictionaryData.append(contentsOf: utf8)
                }

                MLTEncoderCore.encodedUInt32Stream(
                    values: dictionaryLengths,
                    physical: .length,
                    logical: .length(.dictionary)).write(to: &writer)

                MLTEncoderCore.encodedUInt32Stream(
                    values: offsets,
                    physical: .offset,
                    logical: .offset(.string)).write(to: &writer)

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

            case .int32:
                var values: [Int32] = []
                values.reserveCapacity(dense.count)
                for value in dense {
                    guard case let .int(int) = value else {
                        throw MLTError.invalidData("Unexpected value type in integer column")
                    }
                    values.append(Int32(truncatingIfNeeded: int))
                }
                MLTEncoderCore.encodedInt32Stream(
                    values: values,
                    physical: .data,
                    logical: .dictionary(.none)).write(to: &writer)

            case .int64:
                var values: [Int64] = []
                values.reserveCapacity(dense.count)
                for value in dense {
                    guard case let .int(int) = value else {
                        throw MLTError.invalidData("Unexpected value type in integer column")
                    }
                    values.append(int)
                }
                MLTEncoderCore.encodedInt64Stream(
                    values: values,
                    physical: .data,
                    logical: .dictionary(.none)).write(to: &writer)

            case .uint32:
                var values: [UInt32] = []
                values.reserveCapacity(dense.count)
                for value in dense {
                    guard case let .uint(uint) = value else {
                        throw MLTError.invalidData("Unexpected value type in unsigned column")
                    }
                    values.append(UInt32(truncatingIfNeeded: uint))
                }
                MLTEncoderCore.encodedUInt32Stream(
                    values: values,
                    physical: .data,
                    logical: .dictionary(.none)).write(to: &writer)

            case .uint64:
                var values: [UInt64] = []
                values.reserveCapacity(dense.count)
                for value in dense {
                    guard case let .uint(uint) = value else {
                        throw MLTError.invalidData("Unexpected value type in unsigned column")
                    }
                    values.append(uint)
                }
                MLTEncoderCore.encodedUInt64Stream(
                    values: values,
                    physical: .data,
                    logical: .dictionary(.none)).write(to: &writer)

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

