#if EnableMLT
import Foundation

// FastPFOR wire-format decoding follows the upstream `maplibre-tile-spec`
// implementation (MIT OR Apache-2.0).
/// Pure Swift FastPFOR decoder, compatible with the SIMD-FastPFOR variant used
/// by MLT (`FastPFor<8>` + VariableByte tail).
///
/// The implementation follows the wire format decoded by the upstream
/// TypeScript and C++ implementations. It is intentionally bounds-checked:
/// malformed input must throw, never read out of bounds.
enum MLTFastPFOR {

    private static let blockSize = 256
    private static let pageSize = 65_536
    private static let maximumBitWidth = 32

    /// Decodes a FastPFOR stream from the MLT byte stream.
    static func decode(
        from reader: inout MLTByteReader,
        byteLength: Int,
        numValues: Int
    ) throws -> [UInt32] {
        guard byteLength >= 0, numValues >= 0, numValues <= MLTIntegerDecoder.maximumValues else {
            throw MLTError.invalidData("Invalid FastPFOR stream size")
        }

        let bytes = try reader.readBytesArray(byteLength)
        let wordCount = (byteLength + 3) / 4
        guard wordCount <= MLTIntegerDecoder.maximumValues else {
            throw MLTError.invalidData("FastPFOR stream is too large")
        }

        var words: [UInt32] = []
        words.reserveCapacity(wordCount)
        for index in 0 ..< wordCount {
            let base = index * 4
            let b0 = base < bytes.count ? UInt32(bytes[base]) : 0
            let b1 = base + 1 < bytes.count ? UInt32(bytes[base + 1]) : 0
            let b2 = base + 2 < bytes.count ? UInt32(bytes[base + 2]) : 0
            let b3 = base + 3 < bytes.count ? UInt32(bytes[base + 3]) : 0
            words.append((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
        }

        return try decodeWords(words, numValues: numValues)
    }

    // MARK: - Top-level decoding

    private static func decodeWords(
        _ encoded: [UInt32],
        numValues: Int
    ) throws -> [UInt32] {
        var output = [UInt32](repeating: 0, count: numValues)
        guard !encoded.isEmpty else {
            if numValues != 0 {
                throw MLTError.invalidData("Empty FastPFOR stream for \(numValues) values")
            }
            return output
        }

        var inputPosition = 0
        let alignedLength = Int(encoded[inputPosition])
        inputPosition += 1

        guard alignedLength >= 0, alignedLength % blockSize == 0 else {
            throw MLTError.invalidData("Invalid FastPFOR aligned length \(alignedLength)")
        }
        guard alignedLength <= output.count else {
            throw MLTError.invalidData("FastPFOR output buffer is too small")
        }

        inputPosition = try decodeAlignedPages(
            encoded,
            output: &output,
            inputPosition: inputPosition,
            outputPosition: 0,
            outputLength: alignedLength)

        let remainingWords = encoded.count - inputPosition
        let expectedTail = numValues - alignedLength
        _ = try decodeVByte(
            encoded,
            inputPosition: inputPosition,
            inputLength: remainingWords,
            output: &output,
            outputPosition: alignedLength,
            expectedCount: expectedTail)

        return output
    }

    private static func decodeAlignedPages(
        _ encoded: [UInt32],
        output: inout [UInt32],
        inputPosition: Int,
        outputPosition: Int,
        outputLength: Int
    ) throws -> Int {
        let alignedOutputLength = outputLength - (outputLength % blockSize)
        let finalOutput = outputPosition + alignedOutputLength
        var currentOutput = outputPosition
        var currentInput = inputPosition

        while currentOutput != finalOutput {
            let thisSize = min(pageSize, finalOutput - currentOutput)
            currentInput = try decodePage(
                encoded,
                output: &output,
                inputPosition: currentInput,
                outputPosition: currentOutput,
                thisSize: thisSize)
            currentOutput += thisSize
        }
        return currentInput
    }

    private static func decodePage(
        _ encoded: [UInt32],
        output: inout [UInt32],
        inputPosition: Int,
        outputPosition: Int,
        thisSize: Int
    ) throws -> Int {
        let pageStart = inputPosition
        guard pageStart < encoded.count else {
            throw MLTError.invalidData("FastPFOR page starts beyond the input")
        }
        let whereMeta = Int(encoded[pageStart])
        guard whereMeta > 0, pageStart + whereMeta < encoded.count else {
            throw MLTError.invalidData("Invalid FastPFOR page metadata offset \(whereMeta)")
        }

        let packedStart = pageStart + 1
        let packedEnd = pageStart + whereMeta
        let byteSize = Int(encoded[packedEnd])
        let metaWords = (byteSize + 3) / 4
        let byteContainerStart = packedEnd + 1
        let bitmapPosition = byteContainerStart + metaWords

        guard bitmapPosition < encoded.count else {
            throw MLTError.invalidData("FastPFOR page metadata is out of bounds")
        }

        let byteContainer = try materializeByteContainer(
            encoded,
            start: byteContainerStart,
            byteSize: byteSize)

        var workspace = FastPFORWorkspace()
        let afterExceptions = try unpackExceptionStreams(
            encoded,
            exceptionPosition: bitmapPosition,
            workspace: &workspace)

        let blocks = thisSize / blockSize
        try decodePageBlocks(
            encoded,
            pageStart: pageStart,
            packedStart: packedStart,
            packedEnd: packedEnd,
            output: &output,
            outputPosition: outputPosition,
            blocks: blocks,
            byteContainer: byteContainer,
            workspace: &workspace)

        return afterExceptions
    }

    // MARK: - Byte container

    private static func materializeByteContainer(
        _ encoded: [UInt32],
        start: Int,
        byteSize: Int
    ) throws -> [UInt8] {
        guard byteSize >= 0, byteSize <= MLTIntegerDecoder.maximumValues else {
            throw MLTError.invalidData("Invalid FastPFOR byte container size")
        }
        let fullWords = byteSize / 4
        guard start + fullWords <= encoded.count else {
            throw MLTError.invalidData("FastPFOR byte container is out of bounds")
        }

        var bytes = [UInt8](repeating: 0, count: byteSize)
        for index in 0 ..< fullWords {
            let word = encoded[start + index]
            let base = index * 4
            bytes[base] = UInt8(truncatingIfNeeded: word)
            bytes[base + 1] = UInt8(truncatingIfNeeded: word >> 8)
            bytes[base + 2] = UInt8(truncatingIfNeeded: word >> 16)
            bytes[base + 3] = UInt8(truncatingIfNeeded: word >> 24)
        }

        let remainder = byteSize % 4
        if remainder > 0 {
            guard start + fullWords < encoded.count else {
                throw MLTError.invalidData("FastPFOR byte container is truncated")
            }
            let word = encoded[start + fullWords]
            let base = fullWords * 4
            for index in 0 ..< remainder {
                bytes[base + index] = UInt8(truncatingIfNeeded: word >> UInt32(index * 8))
            }
        }
        return bytes
    }

    // MARK: - Exception streams

    private static func unpackExceptionStreams(
        _ encoded: [UInt32],
        exceptionPosition: Int,
        workspace: inout FastPFORWorkspace
    ) throws -> Int {
        guard exceptionPosition < encoded.count else {
            throw MLTError.invalidData("FastPFOR exception bitmap is out of bounds")
        }
        var position = exceptionPosition
        let bitmap = encoded[position]
        position += 1

        for bitWidth in 2 ... maximumBitWidth {
            guard (bitmap >> UInt32(bitWidth - 1)) & 1 != 0 else { continue }
            guard position < encoded.count else {
                throw MLTError.invalidData("FastPFOR exception stream header is truncated")
            }
            let size = Int(encoded[position])
            position += 1
            let rounded = (size + 31) / 32 * 32
            let wordsNeeded = (size * bitWidth + 31) / 32
            guard position + wordsNeeded <= encoded.count else {
                throw MLTError.invalidData("FastPFOR exception stream is truncated")
            }

            var stream = [UInt32](repeating: 0, count: rounded)
            var index = 0
            while index < size {
                // The last 32-value chunk may be padded implicitly: only the
                // first `size` values are meaningful. Pad the chunk with zero
                // words instead of reading into the next stream.
                let available = max(0, min(bitWidth, encoded.count - position))
                var chunk = [UInt32](repeating: 0, count: bitWidth)
                if available > 0 {
                    chunk.replaceSubrange(
                        0 ..< available,
                        with: encoded[position ..< (position + available)])
                }
                try unpack(
                    chunk,
                    inputPosition: 0,
                    output: &stream,
                    outputPosition: index,
                    bitWidth: bitWidth,
                    count: 32)
                position += bitWidth
                index += 32
            }
            let overflow = index - size
            position -= (overflow * bitWidth) / 32

            workspace.streams[bitWidth] = stream
            workspace.sizes[bitWidth] = size
        }

        return position
    }

    // MARK: - Blocks

    private static func decodePageBlocks(
        _ encoded: [UInt32],
        pageStart: Int,
        packedStart: Int,
        packedEnd: Int,
        output: inout [UInt32],
        outputPosition: Int,
        blocks: Int,
        byteContainer: [UInt8],
        workspace: inout FastPFORWorkspace
    ) throws {
        var inputPosition = packedStart
        var bytePosition = 0

        for block in 0 ..< blocks {
            guard bytePosition + 2 <= byteContainer.count else {
                throw MLTError.invalidData("FastPFOR block header is truncated")
            }
            let bitWidth = Int(byteContainer[bytePosition])
            let exceptionCount = Int(byteContainer[bytePosition + 1])
            bytePosition += 2

            guard bitWidth <= maximumBitWidth else {
                throw MLTError.invalidData("Invalid FastPFOR bit width \(bitWidth)")
            }

            let blockOutputPosition = outputPosition + block * blockSize
            guard blockOutputPosition + blockSize <= output.count else {
                throw MLTError.invalidData("FastPFOR output block is out of bounds")
            }

            switch bitWidth {
            case 0:
                output.replaceSubrange(
                    blockOutputPosition ..< (blockOutputPosition + blockSize),
                    with: repeatElement(0, count: blockSize))
            case 32:
                guard inputPosition + blockSize <= encoded.count else {
                    throw MLTError.invalidData("FastPFOR 32-bit block is truncated")
                }
                output.replaceSubrange(
                    blockOutputPosition ..< (blockOutputPosition + blockSize),
                    with: encoded[inputPosition ..< (inputPosition + blockSize)])
                inputPosition += blockSize
            default:
                try unpack(
                    encoded,
                    inputPosition: inputPosition,
                    output: &output,
                    outputPosition: blockOutputPosition,
                    bitWidth: bitWidth,
                    count: blockSize)
                inputPosition += bitWidth * 8
            }

            if exceptionCount > 0 {
                bytePosition = try applyBlockExceptions(
                    output: &output,
                    blockOutputPosition: blockOutputPosition,
                    bitWidth: bitWidth,
                    exceptionCount: exceptionCount,
                    byteContainer: byteContainer,
                    bytePosition: bytePosition,
                    workspace: &workspace)
            }
        }

        guard inputPosition == packedEnd else {
            throw MLTError.invalidData(
                "FastPFOR packed region mismatch: consumed \(inputPosition), expected \(packedEnd)")
        }
    }

    private static func applyBlockExceptions(
        output: inout [UInt32],
        blockOutputPosition: Int,
        bitWidth: Int,
        exceptionCount: Int,
        byteContainer: [UInt8],
        bytePosition: Int,
        workspace: inout FastPFORWorkspace
    ) throws -> Int {
        var position = bytePosition
        guard position < byteContainer.count else {
            throw MLTError.invalidData("FastPFOR exception header is truncated")
        }
        let maxBits = Int(byteContainer[position])
        position += 1
        guard maxBits >= bitWidth, maxBits <= maximumBitWidth else {
            throw MLTError.invalidData("Invalid FastPFOR exception bit width")
        }
        let exceptionBitWidth = maxBits - bitWidth
        guard exceptionBitWidth >= 1, exceptionBitWidth <= maximumBitWidth else {
            throw MLTError.invalidData("Invalid FastPFOR exception width \(exceptionBitWidth)")
        }
        guard position + exceptionCount <= byteContainer.count else {
            throw MLTError.invalidData("FastPFOR exception positions are truncated")
        }

        if exceptionBitWidth == 1 {
            let shift = UInt32(1) << UInt32(bitWidth)
            for _ in 0 ..< exceptionCount {
                let offset = Int(byteContainer[position])
                position += 1
                guard blockOutputPosition + offset < output.count else {
                    throw MLTError.invalidData("FastPFOR exception position is out of bounds")
                }
                output[blockOutputPosition + offset] |= shift
            }
            return position
        }

        guard let exceptionValues = workspace.streams[exceptionBitWidth] else {
            throw MLTError.invalidData("FastPFOR exception stream is missing")
        }
        var pointer = workspace.pointers[exceptionBitWidth]
        let size = workspace.sizes[exceptionBitWidth]
        guard pointer + exceptionCount <= size else {
            throw MLTError.invalidData("FastPFOR exception stream is too short")
        }

        for _ in 0 ..< exceptionCount {
            let offset = Int(byteContainer[position])
            position += 1
            let value = exceptionValues[pointer]
            pointer += 1
            guard blockOutputPosition + offset < output.count else {
                throw MLTError.invalidData("FastPFOR exception position is out of bounds")
            }
            output[blockOutputPosition + offset] |= value &<< UInt32(bitWidth)
        }
        workspace.pointers[exceptionBitWidth] = pointer
        return position
    }

    // MARK: - Bit unpacking

    private static func unpack(
        _ input: [UInt32],
        inputPosition: Int,
        output: inout [UInt32],
        outputPosition: Int,
        bitWidth: Int,
        count: Int
    ) throws {
        guard bitWidth >= 1, bitWidth < 32 else {
            throw MLTError.invalidData("Invalid FastPFOR unpack width \(bitWidth)")
        }
        guard count >= 0, outputPosition + count <= output.count else {
            throw MLTError.invalidData("FastPFOR unpack output is out of bounds")
        }

        let mask = (UInt32(1) << UInt32(bitWidth)) &- 1
        var wordIndex = inputPosition
        var bitOffset = 0
        guard wordIndex < input.count else {
            throw MLTError.invalidData("FastPFOR unpack input is out of bounds")
        }
        var currentWord = input[wordIndex]

        for index in 0 ..< count {
            if bitOffset + bitWidth <= 32 {
                output[outputPosition + index] = (currentWord >> UInt32(bitOffset)) & mask
                bitOffset += bitWidth
                if bitOffset == 32 {
                    bitOffset = 0
                    wordIndex += 1
                    if index != count - 1 {
                        guard wordIndex < input.count else {
                            throw MLTError.invalidData("FastPFOR unpack input is truncated")
                        }
                        currentWord = input[wordIndex]
                    }
                }
            }
            else {
                let lowBits = 32 - bitOffset
                let low = currentWord >> UInt32(bitOffset)
                wordIndex += 1
                guard wordIndex < input.count else {
                    throw MLTError.invalidData("FastPFOR unpack input is truncated")
                }
                currentWord = input[wordIndex]
                let highMask = (UInt32(1) << UInt32(bitWidth - lowBits)) &- 1
                let high = currentWord & highMask
                output[outputPosition + index] = (low | (high << UInt32(lowBits))) & mask
                bitOffset = bitWidth - lowBits
            }
        }
    }

    // MARK: - VariableByte tail

    private static func decodeVByte(
        _ input: [UInt32],
        inputPosition: Int,
        inputLength: Int,
        output: inout [UInt32],
        outputPosition: Int,
        expectedCount: Int
    ) throws -> Int {
        guard expectedCount >= 0, expectedCount <= output.count - outputPosition else {
            throw MLTError.invalidData("FastPFOR VByte output is out of bounds")
        }
        guard expectedCount > 0 else { return inputPosition }

        var bitOffset = 0
        var wordIndex = inputPosition
        let finalWordIndex = inputPosition + inputLength
        var outputIndex = outputPosition
        let targetOutput = outputPosition + expectedCount

        var accumulator: UInt32 = 0
        var accumulatorShift: UInt32 = 0

        while wordIndex < finalWordIndex, outputIndex < targetOutput {
            guard wordIndex < input.count else {
                throw MLTError.invalidData("FastPFOR VByte input is truncated")
            }
            let word = input[wordIndex]
            let byte = (word >> UInt32(bitOffset)) & 0xFF
            bitOffset += 8
            wordIndex += bitOffset >> 5
            bitOffset &= 31

            accumulator |= UInt32(byte & 0x7F) << accumulatorShift
            if (byte & 0x80) != 0 {
                output[outputIndex] = accumulator
                outputIndex += 1
                accumulator = 0
                accumulatorShift = 0
            }
            else {
                accumulatorShift += 7
                if accumulatorShift > 28 {
                    throw MLTError.invalidData("FastPFOR VByte value is unterminated")
                }
            }
        }

        guard outputIndex == targetOutput else {
            throw MLTError.invalidData("FastPFOR VByte stream is truncated")
        }
        return wordIndex
    }

}

// MARK: - Workspace

private struct FastPFORWorkspace {

    var streams: [[UInt32]?]
    var pointers: [Int]
    var sizes: [Int]

    init() {
        self.streams = Array(repeating: nil, count: 33)
        self.pointers = Array(repeating: 0, count: 33)
        self.sizes = Array(repeating: 0, count: 33)
    }

}

#endif
