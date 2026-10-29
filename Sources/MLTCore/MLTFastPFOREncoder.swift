import Foundation

/// Minimal SIMD-FastPFOR encoder for 32-bit integer streams.
///
/// The encoder uses fixed pages of 256-value blocks. It writes both a plain
/// bit-packed variant and a one-bit exception variant, and returns the smaller
/// one. This is a valid FastPFOR stream; it is selected only when it is smaller
/// than the other integer encodings.
enum MLTFastPFOREncoder {

    private static let blockSize = 256
    private static let pageSize = 65_536

    static func encode(_ values: [UInt32]) -> [UInt8]? {
        guard values.count >= blockSize, values.count % blockSize == 0 else {
            return nil
        }

        let plain = encode(values, useExceptions: false)
        let withExceptions = encode(values, useExceptions: true)
        return [plain, withExceptions]
            .compactMap { $0 }
            .min { $0.count < $1.count }
    }

    private static func encode(
        _ values: [UInt32],
        useExceptions: Bool
    ) -> [UInt8]? {
        var words: [UInt32] = [UInt32(values.count)]
        var offset = 0

        while offset < values.count {
            let pageValueCount = min(pageSize, values.count - offset)
            let blockCount = pageValueCount / blockSize
            var packedWords: [UInt32] = []
            var byteContainer: [UInt8] = []
            packedWords.reserveCapacity(blockCount * 8)
            byteContainer.reserveCapacity(blockCount * 4)

            for block in 0 ..< blockCount {
                let start = offset + block * blockSize
                let slice = Array(values[start ..< (start + blockSize)])
                let maximumBits = slice.reduce(0) { result, value in
                    max(result, 32 - value.leadingZeroBitCount)
                }

                var bitWidth = maximumBits
                var exceptionPositions: [UInt8] = []
                if useExceptions, maximumBits > 0 {
                    let positions = slice.indices.compactMap { index -> UInt8? in
                        let bits = 32 - slice[index].leadingZeroBitCount
                        return bits == maximumBits ? UInt8(index) : nil
                    }
                    if positions.count <= 255 {
                        bitWidth = maximumBits - 1
                        exceptionPositions = positions
                    }
                }

                byteContainer.append(UInt8(bitWidth))
                byteContainer.append(UInt8(exceptionPositions.count))
                if !exceptionPositions.isEmpty {
                    byteContainer.append(UInt8(maximumBits))
                    byteContainer.append(contentsOf: exceptionPositions)
                }

                let mask: UInt32
                if bitWidth == 0 {
                    mask = 0
                }
                else if bitWidth == 32 {
                    mask = UInt32.max
                }
                else {
                    mask = (UInt32(1) << UInt32(bitWidth)) &- 1
                }
                packedWords.append(contentsOf: pack(
                    slice.map { $0 & mask },
                    bitWidth: bitWidth))
            }

            let whereMeta = UInt32(1 + packedWords.count)
            words.append(whereMeta)
            words.append(contentsOf: packedWords)
            words.append(UInt32(byteContainer.count))

            var byteIndex = 0
            while byteIndex < byteContainer.count {
                var word: UInt32 = 0
                for byteOffset in 0 ..< 4 {
                    let index = byteIndex + byteOffset
                    if index < byteContainer.count {
                        word |= UInt32(byteContainer[index]) << UInt32(byteOffset * 8)
                    }
                }
                words.append(word)
                byteIndex += 4
            }

            // Empty exception bitmap.
            words.append(0)
            offset += pageValueCount
        }

        var data: [UInt8] = []
        data.reserveCapacity(words.count * 4)
        for word in words {
            data.append(UInt8(truncatingIfNeeded: word >> 24))
            data.append(UInt8(truncatingIfNeeded: word >> 16))
            data.append(UInt8(truncatingIfNeeded: word >> 8))
            data.append(UInt8(truncatingIfNeeded: word))
        }
        return data
    }

    private static func pack(_ values: [UInt32], bitWidth: Int) -> [UInt32] {
        guard bitWidth > 0 else { return [] }
        if bitWidth == 32 {
            return values
        }

        var result: [UInt32] = []
        result.reserveCapacity(bitWidth * 8)
        var current: UInt64 = 0
        var bits = 0

        for value in values {
            current |= UInt64(value) << UInt64(bits)
            bits += bitWidth
            while bits >= 32 {
                result.append(UInt32(truncatingIfNeeded: current))
                current >>= 32
                bits -= 32
            }
        }
        if bits > 0 {
            result.append(UInt32(truncatingIfNeeded: current))
        }
        return result
    }

}
