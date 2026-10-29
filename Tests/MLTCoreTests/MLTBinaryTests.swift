#if EnableMLT
import Foundation
@testable import MLTCore
import Testing

struct MLTBinaryTests {

    // MARK: - Varint

    @Test
    func varint32RoundTrip() throws {
        let values: [UInt32] = [
            0, 1, 127, 128, 16_383, 16_384,
            UInt32(Int32.max), UInt32.max,
        ]

        for value in values {
            var writer = MLTByteWriter()
            writer.writeVarint32(value)
            var reader = MLTByteReader(writer.bytes)
            #expect(try reader.readVarint32() == value)
            #expect(reader.isAtEnd)
        }
    }

    @Test
    func varint64RoundTrip() throws {
        let values: [UInt64] = [
            0, 1, 127, 128, 16_383, 16_384,
            UInt64(Int64.max), UInt64.max,
        ]

        for value in values {
            var writer = MLTByteWriter()
            writer.writeVarint64(value)
            var reader = MLTByteReader(writer.bytes)
            #expect(try reader.readVarint64() == value)
            #expect(reader.isAtEnd)
        }
    }

    @Test
    func truncatedVarintThrows() {
        let reader = MLTByteReader([0x80])
        #expect(throws: (any Error).self) {
            var reader = reader
            _ = try reader.readVarint32()
        }
    }

    @Test
    func overlongVarintThrows() {
        let reader = MLTByteReader([0x80, 0x80, 0x80, 0x80, 0x10])
        #expect(throws: (any Error).self) {
            var reader = reader
            _ = try reader.readVarint32()
        }
    }

    // MARK: - ZigZag

    @Test
    func zigZagRoundTrip() {
        let values: [Int32] = [0, 1, -1, Int32.max, Int32.min, 12345, -12345]
        for value in values {
            #expect(MLTZigZag.decode(MLTZigZag.encode(value)) == value)
        }

        let values64: [Int64] = [0, 1, -1, Int64.max, Int64.min, 9_000_000_000, -9_000_000_000]
        for value in values64 {
            #expect(MLTZigZag.decode(MLTZigZag.encode(value)) == value)
        }
    }

    // MARK: - Byte RLE

    @Test
    func byteRLERoundTrip() throws {
        let inputs: [[UInt8]] = [
            [],
            [1],
            [1, 2],
            [1, 2, 3],
            [7, 7, 7],
            Array(repeating: 0, count: 200),
            Array(repeating: 255, count: 3) + [1, 2] + Array(repeating: 9, count: 130),
            (0 ... 255).map(UInt8.init),
        ]

        for input in inputs {
            let encoded = MLTByteRLE.encode(input)
            var decoder = MLTByteRLE.Decoder(encoded)
            let decoded = try decoder.read(input.count)
            #expect(decoded == input)
            #expect(decoder.remainingBytes == 0)
        }
    }

    @Test
    func byteRLEThrowsOnTruncatedInput() {
        // Literal run of 5 bytes but only 2 bytes follow.
        #expect(throws: (any Error).self) {
            var decoder = MLTByteRLE.Decoder([UInt8(256 - 5), 1, 2])
            _ = try decoder.read(5)
        }
    }

    @Test
    func primitiveReaderAndWriter() throws {
        var writer = MLTByteWriter()
        writer.writeUInt16(0x1234)
        writer.writeUInt32(0x1234_5678)
        writer.writeUInt64(0x1234_5678_9ABC_DEF0)
        writer.writeUInt32(Float(1.5).bitPattern)
        writer.writeUInt64(Double(2.25).bitPattern)
        writer.writeString("hello")
        writer.write(contentsOf: [9, 8, 7])

        var reader = MLTByteReader(writer.bytes)
        #expect(try reader.readUInt16() == 0x1234)
        #expect(try reader.readUInt32() == 0x1234_5678)
        #expect(try reader.readUInt64() == 0x1234_5678_9ABC_DEF0)
        #expect(try reader.readFloat() == 1.5)
        #expect(try reader.readDouble() == 2.25)
        #expect(try reader.readString() == "hello")
        #expect(try reader.readBytesArray(3) == [9, 8, 7])
        #expect(reader.isAtEnd)
    }

    @Test
    func subReaderAndSkip() throws {
        var reader = MLTByteReader([1, 2, 3, 4, 5])
        try reader.skip(1)
        var sub = try reader.readSubReader(3)
        #expect(try sub.readBytesArray(3) == [2, 3, 4])
        #expect(try reader.readByte() == 5)
    }

    @Test
    func readerBoundsAndStringValidation() {
        let reader = MLTByteReader([1])
        #expect(throws: (any Error).self) {
            var reader = reader
            _ = try reader.readBytesArray(2)
        }

        // Length 1 followed by an invalid UTF-8 byte.
        let invalid = MLTByteReader([1, 0xFF])
        #expect(throws: (any Error).self) {
            var invalid = invalid
            _ = try invalid.readString()
        }
    }


    @Test
    func booleanRLEStreamRoundTrip() throws {
        for count in [0, 1, 7, 8, 9, 31, 32, 33, 1000] {
            let values = (0 ..< count).map { ($0 % 3) == 0 }
            let packed = MLTByteRLE.packBool(values)
            let encoded = MLTByteRLE.encode(packed)

            var writer = MLTByteWriter()
            writer.write(contentsOf: encoded)
            var reader = MLTByteReader(writer.bytes)
            let decoded = try MLTByteRLE.decodeBool(
                &reader,
                numValues: count,
                byteLength: encoded.count)

            for index in 0 ..< count {
                #expect(MLTByteRLE.bit(decoded, at: index) == values[index])
            }
        }
    }

}

#endif
