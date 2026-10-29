import Foundation

// MARK: - Stream metadata

enum MLTPhysicalStreamType: UInt8 {
    case present = 0
    case data = 1
    case offset = 2
    case length = 3
}

enum MLTDictionaryType: UInt8 {
    case none = 0
    case single = 1
    case shared = 2
    case vertex = 3
    case morton = 4
    case fsst = 5
}

enum MLTOffsetType: UInt8 {
    case vertex = 0
    case index = 1
    case string = 2
    case key = 3
}

enum MLTLengthType: UInt8 {
    case varBinary = 0
    case geometries = 1
    case parts = 2
    case rings = 3
    case triangles = 4
    case symbol = 5
    case dictionary = 6
}

enum MLTLogicalTechnique: UInt8 {
    case none = 0
    case delta = 1
    case componentwiseDelta = 2
    case rle = 3
    case morton = 4
    case pde = 5
}

enum MLTPhysicalTechnique: UInt8 {
    case none = 0
    case fastPFOR = 1
    case varint = 2
}

enum MLTLogicalStreamType: Equatable {
    case none
    case dictionary(MLTDictionaryType)
    case offset(MLTOffsetType)
    case length(MLTLengthType)
}

struct MLTStreamMetadata {

    var physicalStreamType: MLTPhysicalStreamType
    var logicalStreamType: MLTLogicalStreamType
    var logicalTechnique1: MLTLogicalTechnique
    var logicalTechnique2: MLTLogicalTechnique
    var physicalTechnique: MLTPhysicalTechnique
    var numValues: Int
    var byteLength: Int
    var runs: Int?
    var numRleValues: Int?
    var mortonNumBits: Int?
    var mortonCoordinateShift: Int?

    var isRle: Bool {
        runs != nil && numRleValues != nil
    }

    var isMorton: Bool {
        mortonNumBits != nil && mortonCoordinateShift != nil
    }

    /// The number of values after logical decoding.
    var decodedCount: Int {
        if let numRleValues, logicalTechnique1 == .rle || logicalTechnique2 == .rle {
            return numRleValues
        }
        return numValues
    }

    static func decode(from reader: inout MLTByteReader) throws -> MLTStreamMetadata {
        let streamType = try reader.readByte()
        let physicalStreamTypeRaw = streamType >> 4
        let logicalTypeRaw = streamType & 0x0F

        guard let physicalStreamType = MLTPhysicalStreamType(rawValue: physicalStreamTypeRaw) else {
            throw MLTError.invalidData("Invalid physical stream type \(physicalStreamTypeRaw)")
        }

        let logicalStreamType: MLTLogicalStreamType
        switch physicalStreamType {
        case .present:
            logicalStreamType = .none
        case .data:
            guard let type = MLTDictionaryType(rawValue: logicalTypeRaw) else {
                throw MLTError.invalidData("Invalid dictionary type \(logicalTypeRaw)")
            }
            logicalStreamType = .dictionary(type)
        case .offset:
            guard let type = MLTOffsetType(rawValue: logicalTypeRaw) else {
                throw MLTError.invalidData("Invalid offset type \(logicalTypeRaw)")
            }
            logicalStreamType = .offset(type)
        case .length:
            guard let type = MLTLengthType(rawValue: logicalTypeRaw) else {
                throw MLTError.invalidData("Invalid length type \(logicalTypeRaw)")
            }
            logicalStreamType = .length(type)
        }

        let encodingHeader = try reader.readByte()
        guard let logical1 = MLTLogicalTechnique(rawValue: (encodingHeader >> 5) & 0x07) else {
            throw MLTError.invalidData("Invalid logical technique")
        }
        guard let logical2 = MLTLogicalTechnique(rawValue: (encodingHeader >> 2) & 0x07) else {
            throw MLTError.invalidData("Invalid logical technique")
        }
        guard let physical = MLTPhysicalTechnique(rawValue: encodingHeader & 0x03) else {
            throw MLTError.invalidData("Invalid physical technique")
        }

        let numValues = Int(try reader.readVarint32())
        let byteLength = Int(try reader.readVarint32())
        guard numValues >= 0, byteLength >= 0 else {
            throw MLTError.invalidData("Negative stream size")
        }
        guard byteLength <= reader.remaining else {
            throw MLTError.unexpectedEnd(
                offset: reader.offset,
                needed: byteLength,
                available: reader.remaining)
        }

        var result = MLTStreamMetadata(
            physicalStreamType: physicalStreamType,
            logicalStreamType: logicalStreamType,
            logicalTechnique1: logical1,
            logicalTechnique2: logical2,
            physicalTechnique: physical,
            numValues: numValues,
            byteLength: byteLength)

        if logical1 == .morton {
            result.mortonNumBits = Int(try reader.readVarint32())
            result.mortonCoordinateShift = Int(try reader.readVarint32())
        }

        if (logical1 == .rle || logical2 == .rle), physical != .none {
            result.runs = Int(try reader.readVarint32())
            result.numRleValues = Int(try reader.readVarint32())
        }

        return result
    }

    func encode(to writer: inout MLTByteWriter) {
        let logicalType: UInt8
        switch logicalStreamType {
        case .none:
            logicalType = 0
        case let .dictionary(type):
            logicalType = type.rawValue
        case let .offset(type):
            logicalType = type.rawValue
        case let .length(type):
            logicalType = type.rawValue
        }

        writer.write((physicalStreamType.rawValue << 4) | logicalType)
        writer.write(
            (logicalTechnique1.rawValue << 5)
                | (logicalTechnique2.rawValue << 2)
                | physicalTechnique.rawValue)
        writer.writeVarint32(UInt32(numValues))
        writer.writeVarint32(UInt32(byteLength))
        if let mortonNumBits, let mortonCoordinateShift {
            writer.writeVarint32(UInt32(mortonNumBits))
            writer.writeVarint32(UInt32(mortonCoordinateShift))
        }
        if let runs, let numRleValues {
            writer.writeVarint32(UInt32(runs))
            writer.writeVarint32(UInt32(numRleValues))
        }
    }

}

// MARK: - Column metadata

enum MLTScalarType: UInt8 {
    case boolean = 0
    case int8 = 1
    case uint8 = 2
    case int32 = 3
    case uint32 = 4
    case int64 = 5
    case uint64 = 6
    case float = 7
    case double = 8
    case string = 9
}

enum MLTComplexType: UInt8 {
    case geometry = 0
    case structure = 1
}

enum MLTColumnScope: UInt8 {
    case feature = 0
    case vertex = 1
}

enum MLTColumnKind: Equatable {
    case id(longID: Bool)
    case geometry
    case scalar(MLTScalarType)
    case structure
}

struct MLTColumn {

    var name: String
    var nullable: Bool
    var scope: MLTColumnScope
    var kind: MLTColumnKind
    var children: [MLTColumn]

    var isID: Bool {
        if case .id = kind { return true }
        return false
    }

    var isGeometry: Bool {
        kind == .geometry
    }

    var isStructure: Bool {
        kind == .structure
    }

    var scalarType: MLTScalarType? {
        if case let .scalar(type) = kind { return type }
        return nil
    }

    var longID: Bool {
        if case let .id(longID) = kind { return longID }
        return false
    }

    /// Whether a stream count is stored for this column.
    var hasStreamCount: Bool {
        switch kind {
        case .id:
            return false
        case .geometry, .structure:
            return true
        case let .scalar(type):
            return type == .string
        }
    }

    static func decode(from reader: inout MLTByteReader) throws -> MLTColumn {
        let typeCode = try reader.readVarint32()
        let typeCodeInt = Int(typeCode)

        let nullable = (typeCodeInt & 1) != 0
        let kind: MLTColumnKind
        switch typeCodeInt {
        case 0, 1, 2, 3:
            kind = .id(longID: (typeCodeInt & 2) != 0)
        case 4:
            kind = .geometry
        case 30:
            kind = .structure
        case 10 ... 29:
            guard let type = MLTScalarType(rawValue: UInt8((typeCodeInt - 10) / 2)) else {
                throw MLTError.invalidData("Invalid scalar type code \(typeCodeInt)")
            }
            kind = .scalar(type)
        default:
            throw MLTError.unsupported("column type code \(typeCodeInt)")
        }

        var name = ""
        if typeCodeInt >= 10 {
            name = try reader.readString()
        }
        else if kind == .geometry {
            name = "geometry"
        }
        else if case .id = kind {
            name = "id"
        }

        var children: [MLTColumn] = []
        if kind == .structure {
            let childCount = Int(try reader.readVarint32())
            children.reserveCapacity(childCount)
            for _ in 0 ..< childCount {
                children.append(try decode(from: &reader))
            }
        }

        return MLTColumn(
            name: name,
            nullable: nullable,
            scope: .feature,
            kind: kind,
            children: children)
    }

    func encode(to writer: inout MLTByteWriter) throws {
        let typeCode: Int
        switch kind {
        case let .id(longID):
            typeCode = (longID ? 2 : 0) | (nullable ? 1 : 0)
        case .geometry:
            guard !nullable, children.isEmpty else {
                throw MLTError.invalidData("Geometry columns must be non-nullable and childless")
            }
            typeCode = 4
        case let .scalar(type):
            typeCode = 10 + (Int(type.rawValue) * 2) + (nullable ? 1 : 0)
        case .structure:
            guard !nullable, !children.isEmpty else {
                throw MLTError.invalidData("Struct columns must be non-nullable and have children")
            }
            typeCode = 30
        }

        writer.writeVarint32(UInt32(typeCode))
        if typeCode >= 10 {
            writer.writeString(name)
        }
        if typeCode == 30 {
            writer.writeVarint32(UInt32(children.count))
            for child in children {
                try child.encode(to: &writer)
            }
        }
    }

}

struct MLTFeatureTable {

    var name: String
    var extent: Int
    var columns: [MLTColumn]

    static func decode(from reader: inout MLTByteReader) throws -> MLTFeatureTable {
        let name = try reader.readString()
        guard !name.isEmpty else {
            throw MLTError.invalidData("Missing layer name")
        }
        let extent = Int(try reader.readVarint32())
        guard extent > 0 else {
            throw MLTError.invalidData("Invalid extent \(extent) for layer \(name)")
        }
        let columnCount = Int(try reader.readVarint32())
        guard columnCount >= 0 else {
            throw MLTError.invalidData("Negative column count")
        }
        var columns: [MLTColumn] = []
        columns.reserveCapacity(columnCount)
        for _ in 0 ..< columnCount {
            columns.append(try MLTColumn.decode(from: &reader))
        }
        return MLTFeatureTable(name: name, extent: extent, columns: columns)
    }

    func encode(to writer: inout MLTByteWriter) throws {
        guard !name.isEmpty else {
            throw MLTError.invalidData("Missing layer name")
        }
        writer.writeString(name)
        writer.writeVarint32(UInt32(extent))
        writer.writeVarint32(UInt32(columns.count))
        for column in columns {
            try column.encode(to: &writer)
        }
    }

}

// MARK: - Tile framing

enum MLTTileFraming {

    static let tag0x01: UInt32 = 1

    struct Block {
        var tag: UInt32
        var payload: [UInt8]
    }

    static func readBlocks(from reader: inout MLTByteReader) throws -> [Block] {
        var blocks: [Block] = []
        while !reader.isAtEnd {
            let length = Int(try reader.readVarint32())
            guard length >= 0, length <= reader.remaining else {
                throw MLTError.unexpectedEnd(
                    offset: reader.offset,
                    needed: length,
                    available: reader.remaining)
            }
            let payload = try reader.readBytesArray(length)
            var payloadReader = MLTByteReader(payload)
            let tag = try payloadReader.readVarint32()
            blocks.append(Block(tag: tag, payload: try payloadReader.readBytesArray(payloadReader.remaining)))
        }
        return blocks
    }

    static func writeBlock(tag: UInt32, payload: [UInt8], to writer: inout MLTByteWriter) {
        var body = MLTByteWriter()
        body.writeVarint32(tag)
        body.write(contentsOf: payload)

        writer.writeVarint32(UInt32(body.count))
        writer.write(contentsOf: body.bytes)
    }

}
