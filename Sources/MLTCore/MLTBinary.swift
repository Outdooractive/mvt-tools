import Foundation

/// Errors thrown by the pure Swift MLT codec.
package enum MLTError: Error, Equatable, CustomStringConvertible {
    case unexpectedEnd(offset: Int, needed: Int, available: Int)
    case invalidVarint(offset: Int)
    case varintOverflow(offset: Int)
    case invalidData(String)
    case unsupported(String)

    package var description: String {
        switch self {
        case let .unexpectedEnd(offset, needed, available):
            return "Unexpected end of MLT data at byte \(offset): needed \(needed), available \(available)"
        case let .invalidVarint(offset):
            return "Invalid varint at byte \(offset)"
        case let .varintOverflow(offset):
            return "Varint overflow at byte \(offset)"
        case let .invalidData(reason):
            return "Invalid MLT data: \(reason)"
        case let .unsupported(feature):
            return "Unsupported MLT feature: \(feature)"
        }
    }
}

// MARK: - Reader

/// Bounds-checked reader over an MLT byte buffer.
struct MLTByteReader {

    private let bytes: [UInt8]
    private(set) var offset: Int

    init(_ data: Data) {
        self.bytes = Array(data)
        self.offset = 0
    }

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
        self.offset = 0
    }

    var count: Int { bytes.count }
    var remaining: Int { bytes.count - offset }
    var isAtEnd: Bool { offset >= bytes.count }

    mutating func readByte() throws -> UInt8 {
        guard offset < bytes.count else {
            throw MLTError.unexpectedEnd(offset: offset, needed: 1, available: 0)
        }
        let value = bytes[offset]
        offset += 1
        return value
    }

    mutating func readBytes(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0 else {
            throw MLTError.invalidData("Negative byte count \(count)")
        }
        guard offset + count <= bytes.count else {
            throw MLTError.unexpectedEnd(
                offset: offset,
                needed: count,
                available: bytes.count - offset)
        }
        let start = offset
        offset += count
        return bytes[start ..< offset]
    }

    mutating func readBytesArray(_ count: Int) throws -> [UInt8] {
        Array(try readBytes(count))
    }

    mutating func skip(_ count: Int) throws {
        _ = try readBytes(count)
    }

    mutating func readUInt16() throws -> UInt16 {
        let b = try readBytes(2)
        return UInt16(b[b.startIndex])
            | (UInt16(b[b.startIndex + 1]) << 8)
    }

    mutating func readUInt32() throws -> UInt32 {
        let b = try readBytes(4)
        return UInt32(b[b.startIndex])
            | (UInt32(b[b.startIndex + 1]) << 8)
            | (UInt32(b[b.startIndex + 2]) << 16)
            | (UInt32(b[b.startIndex + 3]) << 24)
    }

    mutating func readUInt64() throws -> UInt64 {
        let low = UInt64(try readUInt32())
        let high = UInt64(try readUInt32())
        return low | (high << 32)
    }

    mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    mutating func readInt64() throws -> Int64 {
        Int64(bitPattern: try readUInt64())
    }

    mutating func readFloat() throws -> Float {
        Float(bitPattern: try readUInt32())
    }

    mutating func readDouble() throws -> Double {
        Double(bitPattern: try readUInt64())
    }

    mutating func readVarint32() throws -> UInt32 {
        var result: UInt32 = 0
        var shift: UInt32 = 0
        while shift < 35 {
            let byte = try readByte()
            if shift == 28, (byte & 0x7F) > 0x0F {
                throw MLTError.varintOverflow(offset: offset - 1)
            }
            result |= UInt32(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
        }
        throw MLTError.varintOverflow(offset: offset)
    }

    mutating func readVarint64() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while shift < 64 {
            let byte = try readByte()
            if shift == 63, (byte & 0x7F) > 1 {
                throw MLTError.varintOverflow(offset: offset - 1)
            }
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
        }
        throw MLTError.varintOverflow(offset: offset)
    }

    /// Reads a varint using a caller-selected width. MLT uses 32-bit varints
    /// for metadata and most streams, and 64-bit varints for 64-bit columns.
    mutating func readVarint(_ width: Int) throws -> UInt64 {
        switch width {
        case 32: return UInt64(try readVarint32())
        case 64: return try readVarint64()
        default: throw MLTError.invalidData("Unsupported varint width \(width)")
        }
    }

    mutating func readString() throws -> String {
        let length = Int(try readVarint32())
        let bytes = try readBytes(length)
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            throw MLTError.invalidData("Invalid UTF-8 string at byte \(offset - length)")
        }
        return string
    }

    /// Returns a sub-reader for `count` bytes and advances the receiver.
    mutating func readSubReader(_ count: Int) throws -> MLTByteReader {
        let bytes = try readBytesArray(count)
        return MLTByteReader(bytes)
    }

}

// MARK: - Writer

/// Growable MLT byte writer.
struct MLTByteWriter {

    private(set) var bytes: [UInt8] = []

    var count: Int { bytes.count }
    var data: Data { Data(bytes) }

    mutating func write(_ value: UInt8) {
        bytes.append(value)
    }

    mutating func write(contentsOf values: some Sequence<UInt8>) {
        bytes.append(contentsOf: values)
    }

    mutating func writeUInt16(_ value: UInt16) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func writeUInt32(_ value: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    mutating func writeUInt64(_ value: UInt64) {
        writeUInt32(UInt32(truncatingIfNeeded: value))
        writeUInt32(UInt32(truncatingIfNeeded: value >> 32))
    }

    mutating func writeVarint32(_ value: UInt32) {
        var remaining = value
        while remaining >= 0x80 {
            bytes.append(UInt8(truncatingIfNeeded: remaining) | 0x80)
            remaining >>= 7
        }
        bytes.append(UInt8(truncatingIfNeeded: remaining))
    }

    mutating func writeVarint64(_ value: UInt64) {
        var remaining = value
        while remaining >= 0x80 {
            bytes.append(UInt8(truncatingIfNeeded: remaining) | 0x80)
            remaining >>= 7
        }
        bytes.append(UInt8(truncatingIfNeeded: remaining))
    }

    mutating func writeString(_ value: String) {
        let utf8 = Array(value.utf8)
        writeVarint32(UInt32(utf8.count))
        bytes.append(contentsOf: utf8)
    }


}

// MARK: - ZigZag

enum MLTZigZag {

    static func encode(_ value: Int32) -> UInt32 {
        let bits = UInt32(bitPattern: value)
        return (bits &<< 1) ^ (0 &- (bits >> 31))
    }

    static func encode(_ value: Int64) -> UInt64 {
        let bits = UInt64(bitPattern: value)
        return (bits &<< 1) ^ (0 &- (bits >> 63))
    }

    static func decode(_ value: UInt32) -> Int32 {
        Int32(bitPattern: (value >> 1) ^ (0 &- (value & 1)))
    }

    static func decode(_ value: UInt64) -> Int64 {
        Int64(bitPattern: (value >> 1) ^ (0 &- (value & 1)))
    }

}

// MARK: - Boolean / byte RLE

enum MLTByteRLE {

    /// ORC-compatible byte RLE decoder.
    struct Decoder {

        private let bytes: [UInt8]
        private var offset: Int
        private var remainingValues: Int = 0
        private var repeatedValue: UInt8 = 0
        private var isRepeating = false

        init(_ bytes: ArraySlice<UInt8>) {
            self.bytes = Array(bytes)
            self.offset = 0
        }

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
            self.offset = 0
        }

        var remainingBytes: Int { bytes.count - offset }

        mutating func read(_ count: Int) throws -> [UInt8] {
            var result: [UInt8] = []
            result.reserveCapacity(count)
            while result.count < count {
                if remainingValues == 0 {
                    try readHeader()
                }
                let take = min(count - result.count, remainingValues)
                if isRepeating {
                    result.append(contentsOf: repeatElement(repeatedValue, count: take))
                }
                else {
                    guard offset + take <= bytes.count else {
                        throw MLTError.unexpectedEnd(
                            offset: offset,
                            needed: take,
                            available: bytes.count - offset)
                    }
                    result.append(contentsOf: bytes[offset ..< (offset + take)])
                    offset += take
                }
                remainingValues -= take
            }
            return result
        }

        private mutating func readHeader() throws {
            guard offset < bytes.count else {
                throw MLTError.unexpectedEnd(offset: offset, needed: 1, available: 0)
            }
            let header = bytes[offset]
            offset += 1
            if (header & 0x80) != 0 {
                // Literal run, length 1...128.
                remainingValues = 256 - Int(header)
                isRepeating = false
            }
            else {
                // Repeated run, length 3...130.
                remainingValues = Int(header) + 3
                isRepeating = true
                guard offset < bytes.count else {
                    throw MLTError.unexpectedEnd(offset: offset, needed: 1, available: 0)
                }
                repeatedValue = bytes[offset]
                offset += 1
            }
        }

    }

    /// Decodes a boolean stream into a bit-packed byte array.
    static func decodeBool(
        _ reader: inout MLTByteReader,
        numValues: Int,
        byteLength: Int
    ) throws -> [UInt8] {
        guard numValues >= 0, byteLength >= 0 else {
            throw MLTError.invalidData("Negative boolean stream size")
        }
        let bytes = try reader.readBytesArray(byteLength)
        let numBytes = (numValues + 7) / 8
        var decoder = Decoder(bytes)
        let decoded = try decoder.read(numBytes)
        guard decoded.count == numBytes else {
            throw MLTError.invalidData("Boolean RLE stream produced the wrong number of bytes")
        }
        return decoded
    }

    static func bit(_ bits: [UInt8], at index: Int) -> Bool {
        guard index >= 0, index / 8 < bits.count else { return false }
        return (bits[index / 8] & (UInt8(1) << UInt8(index % 8))) != 0
    }

    /// Packs booleans into a byte array using least-significant-bit numbering.
    static func packBool(_ values: [Bool]) -> [UInt8] {
        let byteCount = (values.count + 7) / 8
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for (index, value) in values.enumerated() where value {
            bytes[index / 8] |= UInt8(1) << UInt8(index % 8)
        }
        return bytes
    }

    /// ORC-compatible byte RLE encoder.
    static func encode(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = 0

        while index < bytes.count {
            let value = bytes[index]
            var runLength = 1
            while index + runLength < bytes.count,
                  bytes[index + runLength] == value
            {
                runLength += 1
            }

            if runLength >= 3 {
                // Repeated runs: header 0...127, length = header + 3.
                var remaining = runLength
                while remaining > 0 {
                    let chunk = min(remaining, 130)
                    result.append(UInt8(chunk - 3))
                    result.append(value)
                    remaining -= chunk
                }
                index += runLength
            }
            else {
                // Literal runs: header 128...255, length = 256 - header.
                let start = index
                while index < bytes.count, index - start < 128 {
                    let current = bytes[index]
                    var currentRun = 1
                    while index + currentRun < bytes.count,
                          bytes[index + currentRun] == current
                    {
                        currentRun += 1
                    }
                    if currentRun >= 3 {
                        break
                    }
                    index += 1
                }
                let count = index - start
                result.append(UInt8(256 - count))
                result.append(contentsOf: bytes[start ..< index])
            }
        }

        return result
    }

}

// MARK: - Integer arrays

enum MLTIntegerArray {

    /// Reads `count` fixed-width little-endian values.
    static func readUInt32(_ reader: inout MLTByteReader, count: Int) throws -> [UInt32] {
        guard count >= 0 else { throw MLTError.invalidData("Negative value count") }
        var result: [UInt32] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            result.append(try reader.readUInt32())
        }
        return result
    }

    static func readUInt64(_ reader: inout MLTByteReader, count: Int) throws -> [UInt64] {
        guard count >= 0 else { throw MLTError.invalidData("Negative value count") }
        var result: [UInt64] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            result.append(try reader.readUInt64())
        }
        return result
    }

    static func readFloat(_ reader: inout MLTByteReader, count: Int) throws -> [Float] {
        guard count >= 0 else { throw MLTError.invalidData("Negative value count") }
        var result: [Float] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            result.append(try reader.readFloat())
        }
        return result
    }

    static func readDouble(_ reader: inout MLTByteReader, count: Int) throws -> [Double] {
        guard count >= 0 else { throw MLTError.invalidData("Negative value count") }
        var result: [Double] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            result.append(try reader.readDouble())
        }
        return result
    }

    /// Decodes `count` varints with the requested width.
    static func readVarints(
        _ reader: inout MLTByteReader,
        count: Int,
        width: Int
    ) throws -> [UInt64] {
        guard count >= 0 else { throw MLTError.invalidData("Negative value count") }
        var result: [UInt64] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            result.append(try reader.readVarint(width))
        }
        return result
    }

}
