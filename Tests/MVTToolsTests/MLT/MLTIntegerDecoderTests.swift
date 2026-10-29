#if EnableMLT
import Foundation
@testable import MVTTools
import Testing

struct MLTIntegerDecoderTests {

    // MARK: - 32-bit

    @Test
    func plainVarintUnsigned() throws {
        let metadata = meta(
            numValues: 3,
            byteLength: 4,
            logical1: .none,
            physical: .varint)
        let payload = varints32([1, 2, 300])
        let values = try decode32(payload, metadata, signed: false)
        #expect(values == [1, 2, 300])
    }

    @Test
    func plainVarintSigned() throws {
        let metadata = meta(
            numValues: 3,
            byteLength: 3,
            logical1: .none,
            physical: .varint)
        let payload = varints32([
            MLTZigZag.encode(Int32(-2)),
            MLTZigZag.encode(Int32(0)),
            MLTZigZag.encode(Int32(7)),
        ])
        let values = try decode32(payload, metadata, signed: true)
        #expect(values.map { Int32(bitPattern: $0) } == [-2, 0, 7])
    }

    @Test
    func delta() throws {
        let metadata = meta(
            numValues: 4,
            byteLength: 4,
            logical1: .delta,
            physical: .varint)
        let payload = varints32([
            MLTZigZag.encode(Int32(10)),
            MLTZigZag.encode(Int32(5)),
            MLTZigZag.encode(Int32(-3)),
            MLTZigZag.encode(Int32(0)),
        ])
        let values = try decode32(payload, metadata, signed: false)
        #expect(values.map { Int32(bitPattern: $0) } == [10, 15, 12, 12])
    }

    @Test
    func deltaRLE() throws {
        let metadata = meta(
            numValues: 4,
            byteLength: 4,
            logical1: .delta,
            logical2: .rle,
            physical: .varint,
            runs: 2,
            numRleValues: 5)
        let payload = varints32([
            3, 2,
            MLTZigZag.encode(Int32(5)),
            MLTZigZag.encode(Int32(-2)),
        ])
        let values = try decode32(payload, metadata, signed: false)
        #expect(values.map { Int32(bitPattern: $0) } == [5, 10, 15, 13, 11])
    }

    @Test
    func rle() throws {
        let metadata = meta(
            numValues: 4,
            byteLength: 4,
            logical1: .rle,
            physical: .varint,
            runs: 2,
            numRleValues: 5)
        let payload = varints32([3, 2, 10, 20])
        let values = try decode32(payload, metadata, signed: false)
        #expect(values == [10, 10, 10, 20, 20])
    }

    @Test
    func componentwiseDelta() throws {
        let metadata = meta(
            numValues: 4,
            byteLength: 4,
            logical1: .componentwiseDelta,
            physical: .varint)
        let payload = varints32([
            MLTZigZag.encode(Int32(10)),
            MLTZigZag.encode(Int32(20)),
            MLTZigZag.encode(Int32(5)),
            MLTZigZag.encode(Int32(-3)),
        ])
        let values = try decode32(payload, metadata, signed: true)
        #expect(values.map { Int32(bitPattern: $0) } == [10, 20, 15, 17])
    }

    @Test
    func fixedWidth32() throws {
        var writer = MLTByteWriter()
        writer.writeUInt32(10)
        writer.writeUInt32(20)
        writer.writeUInt32(30)
        let metadata = meta(
            numValues: 3,
            byteLength: 12,
            logical1: .none,
            physical: .none)
        let values = try decode32(writer.bytes, metadata, signed: false)
        #expect(values == [10, 20, 30])
    }

    // MARK: - 64-bit

    @Test
    func plainVarint64() throws {
        let metadata = meta(
            numValues: 2,
            byteLength: 6,
            logical1: .none,
            physical: .varint)
        let payload = varints64([9_000_000_000, 42])
        let values = try decode64(payload, metadata, signed: false)
        #expect(values == [9_000_000_000, 42])
    }

    @Test
    func delta64() throws {
        let metadata = meta(
            numValues: 3,
            byteLength: 4,
            logical1: .delta,
            physical: .varint)
        let payload = varints64([
            MLTZigZag.encode(Int64(100)),
            MLTZigZag.encode(Int64(-30)),
            MLTZigZag.encode(Int64(10)),
        ])
        let values = try decode64(payload, metadata, signed: false)
        #expect(values.map { Int64(bitPattern: $0) } == [100, 70, 80])
    }

    @Test
    func rle64() throws {
        let metadata = meta(
            numValues: 4,
            byteLength: 4,
            logical1: .rle,
            physical: .varint,
            runs: 2,
            numRleValues: 4)
        let payload = varints64([2, 2, 7, 9])
        let values = try decode64(payload, metadata, signed: false)
        #expect(values == [7, 7, 9, 9])
    }

    // MARK: - Morton

    @Test
    func mortonCodes() throws {
        let metadata = meta(
            numValues: 4,
            byteLength: 4,
            logical1: .morton,
            physical: .varint,
            numBits: 1,
            coordinateShift: 0)
        let payload = varints32([0, 1, 1, 1])
        let values = try decodeMorton(payload, metadata)
        #expect(values == [0, 0, 1, 0, 0, 1, 1, 1])
    }

    @Test
    func mortonShift() throws {
        let metadata = meta(
            numValues: 1,
            byteLength: 1,
            logical1: .morton,
            physical: .varint,
            numBits: 2,
            coordinateShift: 5)
        let payload = varints32([0])
        let values = try decodeMorton(payload, metadata)
        #expect(values == [-5, -5])
    }

    // MARK: - Errors

    @Test
    func unsupportedPDE() {
        let metadata = meta(
            numValues: 1,
            byteLength: 1,
            logical1: .pde,
            physical: .varint)
        #expect(throws: (any Error).self) {
            _ = try decode32(varints32([0]), metadata, signed: false)
        }
    }

    @Test
    func componentwiseOddCountThrows() {
        let metadata = meta(
            numValues: 3,
            byteLength: 3,
            logical1: .componentwiseDelta,
            physical: .varint)
        #expect(throws: (any Error).self) {
            _ = try decode32(varints32([0, 0, 0]), metadata, signed: false)
        }
    }

    @Test
    func componentwise64Throws() {
        let metadata = meta(
            numValues: 2,
            byteLength: 2,
            logical1: .componentwiseDelta,
            physical: .varint)
        #expect(throws: (any Error).self) {
            _ = try decode64(varints64([0, 0]), metadata, signed: false)
        }
    }

    @Test
    func rleWithoutMetadataThrows() {
        let metadata = meta(
            numValues: 2,
            byteLength: 2,
            logical1: .rle,
            physical: .varint)
        #expect(throws: (any Error).self) {
            _ = try decode32(varints32([1, 2]), metadata, signed: false)
        }
    }

    @Test
    func rleRunMismatchThrows() {
        let metadata = meta(
            numValues: 4,
            byteLength: 4,
            logical1: .rle,
            physical: .varint,
            runs: 2,
            numRleValues: 3)
        #expect(throws: (any Error).self) {
            _ = try decode32(varints32([2, 2, 1, 2]), metadata, signed: false)
        }
    }

    @Test
    func fixedWidthLengthMismatchThrows() {
        let metadata = meta(
            numValues: 2,
            byteLength: 4,
            logical1: .none,
            physical: .none)
        #expect(throws: (any Error).self) {
            _ = try decode32([0, 0, 0, 0], metadata, signed: false)
        }
    }


    @Test
    func deltaRLE64() throws {
        let metadata = meta(
            numValues: 4,
            byteLength: 4,
            logical1: .delta,
            logical2: .rle,
            physical: .varint,
            runs: 2,
            numRleValues: 5)
        let payload = varints64([
            3, 2,
            MLTZigZag.encode(Int64(10)),
            MLTZigZag.encode(Int64(-1)),
        ])
        let values = try decode64(payload, metadata, signed: false)
        #expect(values.map { Int64(bitPattern: $0) } == [10, 20, 30, 29, 28])
    }

    @Test
    func rleRunExceedsDecodedCountThrows() {
        let metadata = meta(
            numValues: 4,
            byteLength: 4,
            logical1: .rle,
            physical: .varint,
            runs: 2,
            numRleValues: 3)
        #expect(throws: (any Error).self) {
            _ = try decode32(varints32([2, 2, 1, 2]), metadata, signed: false)
        }
    }

    @Test
    func rleMissingRunValuesThrows() {
        let metadata = meta(
            numValues: 2,
            byteLength: 2,
            logical1: .rle,
            physical: .varint,
            runs: 2,
            numRleValues: 4)
        #expect(throws: (any Error).self) {
            _ = try decode32(varints32([2, 2]), metadata, signed: false)
        }
    }

    @Test
    func deltaRLEMissingRunValuesThrows() {
        let metadata = meta(
            numValues: 2,
            byteLength: 2,
            logical1: .delta,
            logical2: .rle,
            physical: .varint,
            runs: 2,
            numRleValues: 4)
        #expect(throws: (any Error).self) {
            _ = try decode32(varints32([2, 2]), metadata, signed: false)
        }
    }

    @Test
    func deltaRLERunExceedsDecodedCountThrows() {
        let metadata = meta(
            numValues: 4,
            byteLength: 4,
            logical1: .delta,
            logical2: .rle,
            physical: .varint,
            runs: 2,
            numRleValues: 3)
        #expect(throws: (any Error).self) {
            _ = try decode32(varints32([2, 2, 0, 0]), metadata, signed: false)
        }
    }

    @Test
    func mortonInIntegerDecoderThrows() {
        let metadata = meta(
            numValues: 1,
            byteLength: 1,
            logical1: .morton,
            physical: .varint,
            numBits: 1,
            coordinateShift: 0)
        #expect(throws: (any Error).self) {
            _ = try decode32(varints32([0]), metadata, signed: false)
        }
    }

    @Test
    func pde64Throws() {
        let metadata = meta(
            numValues: 1,
            byteLength: 1,
            logical1: .pde,
            physical: .varint)
        #expect(throws: (any Error).self) {
            _ = try decode64(varints64([0]), metadata, signed: false)
        }
    }

    @Test
    func plain64LengthMismatchThrows() {
        let metadata = meta(
            numValues: 1,
            byteLength: 4,
            logical1: .none,
            physical: .none)
        #expect(throws: (any Error).self) {
            _ = try decode64([0, 0, 0, 0], metadata, signed: false)
        }
    }

    @Test
    func varintCountExceedsRemainingThrows() {
        let metadata = meta(
            numValues: 10,
            byteLength: 1,
            logical1: .none,
            physical: .varint)
        #expect(throws: (any Error).self) {
            _ = try decode32([0], metadata, signed: false)
        }
    }

    @Test
    func excessiveValueCountThrows() {
        let metadata = meta(
            numValues: MLTIntegerDecoder.maximumValues + 1,
            byteLength: 0,
            logical1: .none,
            physical: .varint)
        #expect(throws: (any Error).self) {
            _ = try decode32([], metadata, signed: false)
        }
    }

    @Test
    func mortonTooLargeThrows() {
        let metadata = meta(
            numValues: MLTIntegerDecoder.maximumValues / 2 + 1,
            byteLength: 0,
            logical1: .morton,
            physical: .varint,
            numBits: 1,
            coordinateShift: 0)
        #expect(throws: (any Error).self) {
            _ = try decodeMorton([], metadata)
        }
    }

    // MARK: - Helpers

    private func meta(
        numValues: Int,
        byteLength: Int,
        logical1: MLTLogicalTechnique,
        logical2: MLTLogicalTechnique = .none,
        physical: MLTPhysicalTechnique = .varint,
        runs: Int? = nil,
        numRleValues: Int? = nil,
        numBits: Int? = nil,
        coordinateShift: Int? = nil
    ) -> MLTStreamMetadata {
        MLTStreamMetadata(
            physicalStreamType: .data,
            logicalStreamType: .dictionary(.none),
            logicalTechnique1: logical1,
            logicalTechnique2: logical2,
            physicalTechnique: physical,
            numValues: numValues,
            byteLength: byteLength,
            runs: runs,
            numRleValues: numRleValues,
            mortonNumBits: numBits,
            mortonCoordinateShift: coordinateShift)
    }

    private func decode32(
        _ payload: [UInt8],
        _ metadata: MLTStreamMetadata,
        signed: Bool
    ) throws -> [UInt32] {
        var reader = MLTByteReader(payload)
        return try MLTIntegerDecoder.decodeUInt32(
            from: &reader, metadata: metadata, signed: signed)
    }

    private func decode64(
        _ payload: [UInt8],
        _ metadata: MLTStreamMetadata,
        signed: Bool
    ) throws -> [UInt64] {
        var reader = MLTByteReader(payload)
        return try MLTIntegerDecoder.decodeUInt64(
            from: &reader, metadata: metadata, signed: signed)
    }

    private func decodeMorton(
        _ payload: [UInt8],
        _ metadata: MLTStreamMetadata
    ) throws -> [Int32] {
        var reader = MLTByteReader(payload)
        return try MLTIntegerDecoder.decodeMorton(
            from: &reader, metadata: metadata)
    }

    private func varints32(_ values: [UInt32]) -> [UInt8] {
        var writer = MLTByteWriter()
        for value in values {
            writer.writeVarint32(value)
        }
        return writer.bytes
    }

    private func varints64(_ values: [UInt64]) -> [UInt8] {
        var writer = MLTByteWriter()
        for value in values {
            writer.writeVarint64(value)
        }
        return writer.bytes
    }

}

#endif
