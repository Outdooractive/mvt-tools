import Foundation

/// Decodes MLT integer streams (physical + logical layers).
enum MLTIntegerDecoder {

    static let maximumValues = 100_000_000

    // MARK: - Public API

    /// Decodes an integer stream into 32-bit values.
    static func decodeUInt32(
        from reader: inout MLTByteReader,
        metadata: MLTStreamMetadata,
        signed: Bool
    ) throws -> [UInt32] {
        let raw = try decodeRaw32(from: &reader, metadata: metadata)
        return try applyLogical32(raw, metadata: metadata, signed: signed)
    }

    /// Decodes an integer stream into 64-bit values.
    static func decodeUInt64(
        from reader: inout MLTByteReader,
        metadata: MLTStreamMetadata,
        signed: Bool
    ) throws -> [UInt64] {
        let raw = try decodeRaw64(from: &reader, metadata: metadata)
        return try applyLogical64(raw, metadata: metadata, signed: signed)
    }

    /// Decodes a Morton-encoded stream into interleaved (x, y) coordinates.
    static func decodeMorton(
        from reader: inout MLTByteReader,
        metadata: MLTStreamMetadata
    ) throws -> [Int32] {
        let codes = try decodeMortonCodes(from: &reader, metadata: metadata)
        guard let numBits = metadata.mortonNumBits,
              let coordinateShift = metadata.mortonCoordinateShift
        else {
            throw MLTError.invalidData("Morton stream is missing its metadata")
        }
        let shift = Int32(truncatingIfNeeded: coordinateShift)
        var result: [Int32] = []
        result.reserveCapacity(codes.count * 2)
        for code in codes {
            result.append(MLTMorton.decode(code, numBits: numBits) &- shift)
            result.append(MLTMorton.decode(code >> 1, numBits: numBits) &- shift)
        }
        return result
    }

    /// Decodes the raw, delta-accumulated Morton codes without expanding them
    /// into coordinates. Geometry dictionary encoding indexes into these codes.
    static func decodeMortonCodes(
        from reader: inout MLTByteReader,
        metadata: MLTStreamMetadata
    ) throws -> [UInt32] {
        let raw = try decodeRaw32(from: &reader, metadata: metadata)
        guard raw.count <= maximumValues / 2 else {
            throw MLTError.invalidData("Morton stream is too large")
        }
        var result: [UInt32] = []
        result.reserveCapacity(raw.count)
        var previous: UInt32 = 0
        for value in raw {
            previous = previous &+ value
            result.append(previous)
        }
        return result
    }

    // MARK: - Physical layer

    private static func decodeRaw32(
        from reader: inout MLTByteReader,
        metadata: MLTStreamMetadata
    ) throws -> [UInt32] {
        let count = metadata.numValues
        guard count >= 0, count <= maximumValues else {
            throw MLTError.invalidData("Invalid integer stream value count \(count)")
        }

        switch metadata.physicalTechnique {
        case .varint:
            guard count <= reader.remaining else {
                throw MLTError.unexpectedEnd(
                    offset: reader.offset,
                    needed: count,
                    available: reader.remaining)
            }
            return try MLTIntegerArray.readVarints(
                &reader, count: count, width: 32
            ).map(UInt32.init(truncatingIfNeeded:))

        case .none:
            guard metadata.byteLength == count * 4 else {
                throw MLTError.invalidData(
                    "Plain 32-bit stream has byte length \(metadata.byteLength) for \(count) values")
            }
            return try MLTIntegerArray.readUInt32(&reader, count: count)

        case .fastPFOR:
            return try MLTFastPFOR.decode(
                from: &reader,
                byteLength: metadata.byteLength,
                numValues: count)
        }
    }

    private static func decodeRaw64(
        from reader: inout MLTByteReader,
        metadata: MLTStreamMetadata
    ) throws -> [UInt64] {
        let count = metadata.numValues
        guard count >= 0, count <= maximumValues else {
            throw MLTError.invalidData("Invalid integer stream value count \(count)")
        }

        switch metadata.physicalTechnique {
        case .varint:
            guard count <= reader.remaining else {
                throw MLTError.unexpectedEnd(
                    offset: reader.offset,
                    needed: count,
                    available: reader.remaining)
            }
            return try MLTIntegerArray.readVarints(&reader, count: count, width: 64)

        case .none:
            guard metadata.byteLength == count * 8 else {
                throw MLTError.invalidData(
                    "Plain 64-bit stream has byte length \(metadata.byteLength) for \(count) values")
            }
            return try MLTIntegerArray.readUInt64(&reader, count: count)

        case .fastPFOR:
            let values = try MLTFastPFOR.decode(
                from: &reader,
                byteLength: metadata.byteLength,
                numValues: count)
            return values.map(UInt64.init)
        }
    }

    // MARK: - Logical layer, 32-bit

    private static func applyLogical32(
        _ raw: [UInt32],
        metadata: MLTStreamMetadata,
        signed: Bool
    ) throws -> [UInt32] {
        switch metadata.logicalTechnique1 {
        case .none:
            return signed
                ? raw.map { UInt32(bitPattern: MLTZigZag.decode($0)) }
                : raw

        case .delta:
            if metadata.logicalTechnique2 == .rle {
                return try decodeDeltaRLE32(raw, metadata: metadata)
            }
            return decodeDelta32(raw)

        case .componentwiseDelta:
            guard raw.count % 2 == 0 else {
                throw MLTError.invalidData("Componentwise delta stream has an odd value count")
            }
            var result = raw
            if !result.isEmpty {
                result[0] = UInt32(bitPattern: MLTZigZag.decode(result[0]))
                result[1] = UInt32(bitPattern: MLTZigZag.decode(result[1]))
                var index = 2
                while index + 1 < result.count {
                    result[index] = UInt32(bitPattern: MLTZigZag.decode(result[index])) &+ result[index - 2]
                    result[index + 1] = UInt32(bitPattern: MLTZigZag.decode(result[index + 1])) &+ result[index - 1]
                    index += 2
                }
            }
            return result

        case .rle:
            return try decodeRLE32(raw, metadata: metadata, signed: signed)

        case .morton:
            throw MLTError.invalidData("Morton streams must be decoded with decodeMorton")

        case .pde:
            throw MLTError.unsupported("PDE integer encoding")
        }
    }

    private static func decodeDelta32(_ raw: [UInt32]) -> [UInt32] {
        var result: [UInt32] = []
        result.reserveCapacity(raw.count)
        var running: UInt32 = 0
        for value in raw {
            running = running &+ UInt32(bitPattern: MLTZigZag.decode(value))
            result.append(running)
        }
        return result
    }

    private static func decodeRLE32(
        _ raw: [UInt32],
        metadata: MLTStreamMetadata,
        signed: Bool
    ) throws -> [UInt32] {
        guard let runs = metadata.runs, let decodedCount = metadata.numRleValues else {
            throw MLTError.invalidData("RLE stream is missing its run metadata")
        }
        guard runs >= 0, decodedCount >= 0, decodedCount <= maximumValues else {
            throw MLTError.invalidData("Invalid RLE run metadata")
        }
        guard raw.count >= runs * 2 else {
            throw MLTError.invalidData("RLE stream is missing run values")
        }

        var result: [UInt32] = []
        result.reserveCapacity(decodedCount)
        for index in 0 ..< runs {
            let runLength = Int(raw[index])
            let value = raw[runs + index]
            guard runLength >= 0, result.count + runLength <= decodedCount else {
                throw MLTError.invalidData("RLE run exceeds the decoded value count")
            }
            let decoded = signed ? UInt32(bitPattern: MLTZigZag.decode(value)) : value
            result.append(contentsOf: repeatElement(decoded, count: runLength))
        }
        guard result.count == decodedCount else {
            throw MLTError.invalidData("RLE stream produced \(result.count) values, expected \(decodedCount)")
        }
        return result
    }

    private static func decodeDeltaRLE32(
        _ raw: [UInt32],
        metadata: MLTStreamMetadata
    ) throws -> [UInt32] {
        guard let runs = metadata.runs, let decodedCount = metadata.numRleValues else {
            throw MLTError.invalidData("Delta-RLE stream is missing its run metadata")
        }
        guard runs >= 0, decodedCount >= 0, decodedCount <= maximumValues else {
            throw MLTError.invalidData("Invalid delta-RLE run metadata")
        }
        guard raw.count >= runs * 2 else {
            throw MLTError.invalidData("Delta-RLE stream is missing run values")
        }

        var result: [UInt32] = []
        result.reserveCapacity(decodedCount)
        var running: UInt32 = 0
        for index in 0 ..< runs {
            let runLength = Int(raw[index])
            let delta = UInt32(bitPattern: MLTZigZag.decode(raw[runs + index]))
            guard runLength >= 0, result.count + runLength <= decodedCount else {
                throw MLTError.invalidData("Delta-RLE run exceeds the decoded value count")
            }
            for _ in 0 ..< runLength {
                running = running &+ delta
                result.append(running)
            }
        }
        guard result.count == decodedCount else {
            throw MLTError.invalidData(
                "Delta-RLE stream produced \(result.count) values, expected \(decodedCount)")
        }
        return result
    }

    // MARK: - Logical layer, 64-bit

    private static func applyLogical64(
        _ raw: [UInt64],
        metadata: MLTStreamMetadata,
        signed: Bool
    ) throws -> [UInt64] {
        switch metadata.logicalTechnique1 {
        case .none:
            return signed
                ? raw.map { UInt64(bitPattern: MLTZigZag.decode($0)) }
                : raw

        case .delta:
            if metadata.logicalTechnique2 == .rle {
                return try decodeDeltaRLE64(raw, metadata: metadata)
            }
            return decodeDelta64(raw)

        case .componentwiseDelta:
            throw MLTError.unsupported("Componentwise delta for 64-bit integers")

        case .rle:
            return try decodeRLE64(raw, metadata: metadata, signed: signed)

        case .morton:
            throw MLTError.unsupported("Morton encoding for 64-bit integers")

        case .pde:
            throw MLTError.unsupported("PDE integer encoding")
        }
    }

    private static func decodeDelta64(_ raw: [UInt64]) -> [UInt64] {
        var result: [UInt64] = []
        result.reserveCapacity(raw.count)
        var running: UInt64 = 0
        for value in raw {
            running = running &+ UInt64(bitPattern: MLTZigZag.decode(value))
            result.append(running)
        }
        return result
    }

    private static func decodeRLE64(
        _ raw: [UInt64],
        metadata: MLTStreamMetadata,
        signed: Bool
    ) throws -> [UInt64] {
        guard let runs = metadata.runs, let decodedCount = metadata.numRleValues else {
            throw MLTError.invalidData("RLE stream is missing its run metadata")
        }
        guard runs >= 0, decodedCount >= 0, decodedCount <= maximumValues else {
            throw MLTError.invalidData("Invalid RLE run metadata")
        }
        guard raw.count >= runs * 2 else {
            throw MLTError.invalidData("RLE stream is missing run values")
        }

        var result: [UInt64] = []
        result.reserveCapacity(decodedCount)
        for index in 0 ..< runs {
            let runLength = Int(raw[index])
            let value = raw[runs + index]
            guard runLength >= 0, result.count + runLength <= decodedCount else {
                throw MLTError.invalidData("RLE run exceeds the decoded value count")
            }
            let decoded = signed ? UInt64(bitPattern: MLTZigZag.decode(value)) : value
            result.append(contentsOf: repeatElement(decoded, count: runLength))
        }
        guard result.count == decodedCount else {
            throw MLTError.invalidData(
                "RLE stream produced \(result.count) values, expected \(decodedCount)")
        }
        return result
    }

    private static func decodeDeltaRLE64(
        _ raw: [UInt64],
        metadata: MLTStreamMetadata
    ) throws -> [UInt64] {
        guard let runs = metadata.runs, let decodedCount = metadata.numRleValues else {
            throw MLTError.invalidData("Delta-RLE stream is missing its run metadata")
        }
        guard runs >= 0, decodedCount >= 0, decodedCount <= maximumValues else {
            throw MLTError.invalidData("Invalid delta-RLE run metadata")
        }
        guard raw.count >= runs * 2 else {
            throw MLTError.invalidData("Delta-RLE stream is missing run values")
        }

        var result: [UInt64] = []
        result.reserveCapacity(decodedCount)
        var running: UInt64 = 0
        for index in 0 ..< runs {
            let runLength = Int(raw[index])
            let delta = UInt64(bitPattern: MLTZigZag.decode(raw[runs + index]))
            guard runLength >= 0, result.count + runLength <= decodedCount else {
                throw MLTError.invalidData("Delta-RLE run exceeds the decoded value count")
            }
            for _ in 0 ..< runLength {
                running = running &+ delta
                result.append(running)
            }
        }
        guard result.count == decodedCount else {
            throw MLTError.invalidData(
                "Delta-RLE stream produced \(result.count) values, expected \(decodedCount)")
        }
        return result
    }

}

// MARK: - Morton

enum MLTMorton {

    /// Decodes one dimension from a Morton code.
    ///
    /// Even bits (0, 2, 4, ...) of the code belong to the x coordinate, so
    /// bit `2 * i` is moved down to bit `i`.
    static func decode(_ code: UInt32, numBits: Int) -> Int32 {
        guard numBits > 0, numBits <= 16 else {
            return Int32(bitPattern: code)
        }
        var result: UInt32 = 0
        for index in 0 ..< numBits {
            result |= (code & (UInt32(1) << UInt32(2 * index))) >> UInt32(index)
        }
        return Int32(bitPattern: result)
    }

}
