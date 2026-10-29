import Foundation

// String dictionary and shared-dictionary layouts follow the upstream
// `maplibre-tile-spec` decoder (MIT OR Apache-2.0).
// MARK: - Property values

/// A typed MLT property value.
package enum MLTValue: Equatable, Sendable {
    case bool(Bool)
    case int8(Int8)
    case uint8(UInt8)
    case int32(Int32)
    case uint32(UInt32)
    case int64(Int64)
    case uint64(UInt64)
    case float(Float)
    case double(Double)
    case string(String)

    package var sendableValue: any Sendable {
        switch self {
        case let .bool(value): return value
        case let .int8(value): return Int64(value)
        case let .uint8(value): return UInt64(value)
        case let .int32(value): return Int64(value)
        case let .uint32(value): return UInt64(value)
        case let .int64(value): return value
        case let .uint64(value): return value
        case let .float(value): return Double(value)
        case let .double(value): return value
        case let .string(value): return value
        }
    }

}

struct MLTPropertyColumn {
    var name: String
    var values: [MLTValue?]
    var featureCount: Int
}

// MARK: - Property decoder

enum MLTPropertyDecoder {

    static func decode(
        from reader: inout MLTByteReader,
        column: MLTColumn,
        numStreams: Int
    ) throws -> MLTPropertyColumn {
        guard let scalarType = column.scalarType else {
            throw MLTError.unsupported("Non-scalar property column '\(column.name)'")
        }

        var presentBits: [UInt8]?
        var presentCount = 0
        var remainingStreams = numStreams

        if column.nullable {
            guard remainingStreams >= 1 else {
                throw MLTError.invalidData("Nullable column '\(column.name)' has no present stream")
            }
            let presentMetadata = try MLTStreamMetadata.decode(from: &reader)
            presentCount = presentMetadata.numValues
            presentBits = try MLTByteRLE.decodeBool(
                &reader,
                numValues: presentMetadata.numValues,
                byteLength: presentMetadata.byteLength)
            remainingStreams -= 1
        }

        switch scalarType {
        case .string:
            let strings = try MLTStringDecoder.decode(
                from: &reader, numStreams: remainingStreams)
            let values = try expand(
                strings.map { MLTValue.string($0) },
                presentBits: presentBits,
                presentCount: presentCount,
                columnName: column.name)
            return MLTPropertyColumn(
                name: column.name,
                values: values,
                featureCount: values.count)

        case .boolean:
            let metadata = try MLTStreamMetadata.decode(from: &reader)
            let bits = try MLTByteRLE.decodeBool(
                &reader,
                numValues: metadata.numValues,
                byteLength: metadata.byteLength)
            let dense = (0 ..< metadata.numValues).map {
                MLTValue.bool(MLTByteRLE.bit(bits, at: $0))
            }
            let values = try expand(
                dense,
                presentBits: presentBits,
                presentCount: presentCount,
                columnName: column.name)
            return MLTPropertyColumn(
                name: column.name,
                values: values,
                featureCount: values.count)

        case .int8, .uint8, .int32, .uint32:
            let metadata = try MLTStreamMetadata.decode(from: &reader)
            let decoded = try MLTIntegerDecoder.decodeUInt32(
                from: &reader,
                metadata: metadata,
                signed: scalarType == .int8 || scalarType == .int32)

            let dense: [MLTValue]
            switch scalarType {
            case .int8:
                dense = decoded.map { .int8(Int8(truncatingIfNeeded: $0)) }
            case .uint8:
                dense = decoded.map { .uint8(UInt8(truncatingIfNeeded: $0)) }
            case .int32:
                dense = decoded.map { .int32(Int32(bitPattern: $0)) }
            case .uint32:
                dense = decoded.map { .uint32($0) }
            default:
                dense = []
            }

            let values = try expand(
                dense,
                presentBits: presentBits,
                presentCount: presentCount,
                columnName: column.name)
            return MLTPropertyColumn(
                name: column.name,
                values: values,
                featureCount: values.count)

        case .int64, .uint64:
            let metadata = try MLTStreamMetadata.decode(from: &reader)
            let decoded = try MLTIntegerDecoder.decodeUInt64(
                from: &reader,
                metadata: metadata,
                signed: scalarType == .int64)

            let dense: [MLTValue]
            switch scalarType {
            case .int64:
                dense = decoded.map { .int64(Int64(bitPattern: $0)) }
            case .uint64:
                dense = decoded.map { .uint64($0) }
            default:
                dense = []
            }

            let values = try expand(
                dense,
                presentBits: presentBits,
                presentCount: presentCount,
                columnName: column.name)
            return MLTPropertyColumn(
                name: column.name,
                values: values,
                featureCount: values.count)

        case .float:
            let metadata = try MLTStreamMetadata.decode(from: &reader)
            let raw = try MLTIntegerDecoder.decodeUInt32(
                from: &reader, metadata: metadata, signed: false)
            let dense = raw.map { MLTValue.float(Float(bitPattern: $0)) }
            let values = try expand(
                dense,
                presentBits: presentBits,
                presentCount: presentCount,
                columnName: column.name)
            return MLTPropertyColumn(
                name: column.name,
                values: values,
                featureCount: values.count)

        case .double:
            let metadata = try MLTStreamMetadata.decode(from: &reader)
            let dense: [MLTValue]
            if metadata.byteLength == metadata.numValues * 8 {
                let raw = try MLTIntegerDecoder.decodeUInt64(
                    from: &reader, metadata: metadata, signed: false)
                dense = raw.map { MLTValue.double(Double(bitPattern: $0)) }
            }
            else if metadata.byteLength == metadata.numValues * 4 {
                let raw = try MLTIntegerDecoder.decodeUInt32(
                    from: &reader, metadata: metadata, signed: false)
                dense = raw.map { MLTValue.double(Double(Float(bitPattern: $0))) }
            }
            else {
                throw MLTError.invalidData("Double column '\(column.name)' has an invalid byte length")
            }
            let values = try expand(
                dense,
                presentBits: presentBits,
                presentCount: presentCount,
                columnName: column.name)
            return MLTPropertyColumn(
                name: column.name,
                values: values,
                featureCount: values.count)
        }
    }

    private static func expand(
        _ dense: [MLTValue],
        presentBits: [UInt8]?,
        presentCount: Int,
        columnName: String
    ) throws -> [MLTValue?] {
        guard let presentBits else {
            return dense.map { Optional($0) }
        }
        guard presentCount >= 0, presentCount <= MLTIntegerDecoder.maximumValues else {
            throw MLTError.invalidData("Invalid present count for column '\(columnName)'")
        }
        var result: [MLTValue?] = Array(repeating: nil, count: presentCount)
        var denseIndex = 0
        for index in 0 ..< presentCount where MLTByteRLE.bit(presentBits, at: index) {
            guard denseIndex < dense.count else {
                throw MLTError.invalidData("Present stream has more values than column '\(columnName)'")
            }
            result[index] = dense[denseIndex]
            denseIndex += 1
        }
        guard denseIndex == dense.count else {
            throw MLTError.invalidData("Present stream has fewer values than column '\(columnName)'")
        }
        return result
    }

    static func decodeSharedDictionary(
        from reader: inout MLTByteReader,
        column: MLTColumn,
        numStreams: Int
    ) throws -> [(String, [MLTValue?])] {
        guard column.isStructure, !column.children.isEmpty else {
            throw MLTError.invalidData("Shared dictionary column has no children")
        }

        var dictionaryLengths: [UInt32] = []
        var dictionaryBytes: [UInt8] = []
        var symbolLengths: [UInt32] = []
        var symbolBytes: [UInt8] = []
        var dictionaryDecoded = false
        var streamsLeft = numStreams

        while !dictionaryDecoded, streamsLeft > 0 {
            streamsLeft -= 1
            let metadata = try MLTStreamMetadata.decode(from: &reader)
            switch metadata.physicalStreamType {
            case .length:
                guard case let .length(type) = metadata.logicalStreamType else {
                    throw MLTError.invalidData("Shared dictionary length stream has no logical type")
                }
                if type == .dictionary {
                    dictionaryLengths = try MLTIntegerDecoder.decodeUInt32(
                        from: &reader, metadata: metadata, signed: false)
                }
                else {
                    symbolLengths = try MLTIntegerDecoder.decodeUInt32(
                        from: &reader, metadata: metadata, signed: false)
                }

            case .data:
                guard case let .dictionary(type) = metadata.logicalStreamType else {
                    throw MLTError.invalidData("Shared dictionary data stream has no dictionary type")
                }
                let bytes = try reader.readBytesArray(metadata.byteLength)
                if type == .single || type == .shared {
                    dictionaryBytes = bytes
                    dictionaryDecoded = true
                }
                else {
                    symbolBytes = bytes
                }

            case .offset, .present:
                throw MLTError.unsupported("Unexpected stream in a shared dictionary")
            }
        }

        guard dictionaryDecoded else {
            throw MLTError.invalidData("Shared dictionary is missing its data stream")
        }

        let dictionary: [String]
        if !dictionaryLengths.isEmpty, !symbolLengths.isEmpty, !symbolBytes.isEmpty {
            let decoded = try MLTFSST.decode(
                symbols: symbolBytes,
                symbolLengths: symbolLengths,
                compressedData: dictionaryBytes,
                decompressedLength: max(dictionaryBytes.count * 2, 1))
            dictionary = try MLTStringDecoder.dictionaryValues(
                lengths: dictionaryLengths,
                bytes: decoded,
                offsets: nil)
        }
        else if !dictionaryLengths.isEmpty {
            dictionary = try MLTStringDecoder.dictionaryValues(
                lengths: dictionaryLengths,
                bytes: dictionaryBytes,
                offsets: nil)
        }
        else {
            throw MLTError.invalidData("Shared dictionary is missing its length or symbol streams")
        }

        var results: [(String, [MLTValue?])] = []
        for child in column.children {
            let childStreams = Int(try reader.readVarint32())
            let name = column.name + child.name

            if childStreams == 0 {
                results.append((name, []))
                continue
            }

            guard child.scalarType == .string else {
                throw MLTError.unsupported("Shared dictionary child '\(name)' is not a string")
            }

            var consumed = 0
            var presentBits: [UInt8]?
            var presentCount = 0
            if child.nullable {
                guard consumed < childStreams else {
                    throw MLTError.invalidData("Shared dictionary child '\(name)' has no present stream")
                }
                let presentMetadata = try MLTStreamMetadata.decode(from: &reader)
                presentCount = presentMetadata.numValues
                presentBits = try MLTByteRLE.decodeBool(
                    &reader,
                    numValues: presentMetadata.numValues,
                    byteLength: presentMetadata.byteLength)
                consumed += 1
            }

            guard consumed < childStreams else {
                throw MLTError.invalidData("Shared dictionary child '\(name)' has no data stream")
            }
            let dataMetadata = try MLTStreamMetadata.decode(from: &reader)
            let offsets = try MLTIntegerDecoder.decodeUInt32(
                from: &reader, metadata: dataMetadata, signed: false)
            consumed += 1

            var strings: [String] = []
            strings.reserveCapacity(offsets.count)
            for offset in offsets {
                guard Int(offset) < dictionary.count else {
                    throw MLTError.invalidData("Shared dictionary index is out of bounds")
                }
                strings.append(dictionary[Int(offset)])
            }

            let values = try expand(
                strings.map { MLTValue.string($0) },
                presentBits: presentBits,
                presentCount: presentCount,
                columnName: name)

            if consumed < childStreams {
                try skipStreams(
                    from: &reader,
                    count: childStreams - consumed)
            }
            results.append((name, values))
        }

        return results
    }

    private static func skipStreams(
        from reader: inout MLTByteReader,
        count: Int
    ) throws {
        for _ in 0 ..< count {
            let metadata = try MLTStreamMetadata.decode(from: &reader)
            try reader.skip(metadata.byteLength)
        }
    }

}

enum MLTStringDecoder {

    static func decode(
        from reader: inout MLTByteReader,
        numStreams: Int
    ) throws -> [String] {
        guard numStreams >= 1 else {
            throw MLTError.invalidData("String column has no streams")
        }

        var dictionaryBytes: [UInt8] = []
        var symbolBytes: [UInt8] = []
        var offsets: [UInt32] = []
        var dictionaryLengths: [UInt32] = []
        var symbolLengths: [UInt32] = []

        for _ in 0 ..< numStreams {
            let metadata = try MLTStreamMetadata.decode(from: &reader)

            switch metadata.physicalStreamType {
            case .offset:
                offsets = try MLTIntegerDecoder.decodeUInt32(
                    from: &reader, metadata: metadata, signed: false)

            case .length:
                guard case let .length(type) = metadata.logicalStreamType else {
                    throw MLTError.invalidData("Length stream is missing its logical type")
                }
                if type == .dictionary {
                    dictionaryLengths = try MLTIntegerDecoder.decodeUInt32(
                        from: &reader, metadata: metadata, signed: false)
                }
                else {
                    symbolLengths = try MLTIntegerDecoder.decodeUInt32(
                        from: &reader, metadata: metadata, signed: false)
                }

            case .data:
                guard case let .dictionary(type) = metadata.logicalStreamType else {
                    throw MLTError.invalidData("Data stream is missing its dictionary type")
                }
                let bytes = try reader.readBytesArray(metadata.byteLength)
                if type == .single || type == .shared {
                    dictionaryBytes = bytes
                }
                else {
                    symbolBytes = bytes
                }

            case .present:
                throw MLTError.unsupported("Present stream inside a string column")
            }
        }

        if !dictionaryLengths.isEmpty, !symbolLengths.isEmpty {
            let decoded = try MLTFSST.decode(
                symbols: symbolBytes,
                symbolLengths: symbolLengths,
                compressedData: dictionaryBytes,
                decompressedLength: max(dictionaryBytes.count * 2, 1))
            return try dictionaryValues(
                lengths: dictionaryLengths,
                bytes: decoded,
                offsets: offsets)
        }

        if !dictionaryLengths.isEmpty {
            let dictionary = try dictionaryValues(
                lengths: dictionaryLengths,
                bytes: dictionaryBytes,
                offsets: nil)
            return try applyOffsets(offsets, to: dictionary)
        }

        if !symbolLengths.isEmpty {
            return try plainValues(lengths: symbolLengths, bytes: symbolBytes)
        }

        throw MLTError.invalidData("String column is missing its length or dictionary streams")
    }

    private static func plainValues(
        lengths: [UInt32],
        bytes: [UInt8]
    ) throws -> [String] {
        var offset = 0
        var result: [String] = []
        result.reserveCapacity(lengths.count)
        for length in lengths {
            let end = offset + Int(length)
            guard end <= bytes.count else {
                throw MLTError.invalidData("String data is shorter than its length stream")
            }
            result.append(try string(from: bytes[offset ..< end]))
            offset = end
        }
        guard offset == bytes.count else {
            throw MLTError.invalidData("String data has trailing bytes")
        }
        return result
    }

    static func dictionaryValues(
        lengths: [UInt32],
        bytes: [UInt8],
        offsets: [UInt32]?
    ) throws -> [String] {
        var offset = 0
        var dictionary: [String] = []
        dictionary.reserveCapacity(lengths.count)
        for length in lengths {
            let end = offset + Int(length)
            guard end <= bytes.count else {
                throw MLTError.invalidData("Dictionary data is shorter than its length stream")
            }
            dictionary.append(try string(from: bytes[offset ..< end]))
            offset = end
        }
        if let offsets {
            return try applyOffsets(offsets, to: dictionary)
        }
        return dictionary
    }

    private static func applyOffsets(
        _ offsets: [UInt32],
        to dictionary: [String]
    ) throws -> [String] {
        var result: [String] = []
        result.reserveCapacity(offsets.count)
        for offset in offsets {
            guard Int(offset) < dictionary.count else {
                throw MLTError.invalidData("String dictionary offset is out of bounds")
            }
            result.append(dictionary[Int(offset)])
        }
        return result
    }

    private static func string(from bytes: ArraySlice<UInt8>) throws -> String {
        var bytes = bytes
        if bytes.count >= 3,
           bytes[bytes.startIndex] == 0xEF,
           bytes[bytes.startIndex + 1] == 0xBB,
           bytes[bytes.startIndex + 2] == 0xBF
        {
            bytes = bytes.dropFirst(3)
        }
        guard let value = String(bytes: bytes, encoding: .utf8) else {
            throw MLTError.invalidData("Invalid UTF-8 string in MLT column")
        }
        return value
    }

}
