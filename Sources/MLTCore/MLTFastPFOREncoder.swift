import Foundation

/// Minimal SIMD-FastPFOR encoder for 32-bit integer streams.
///
/// The encoder uses fixed pages of 256-value blocks and writes bit-packed
/// blocks without exception streams. This is a valid FastPFOR stream; it is
/// selected only when it is smaller than the other integer encodings.
enum MLTFastPFOREncoder {

    private static let blockSize = 256
    private static let pageSize = 65_536

    static func encode(_ values: [UInt32]) -> [UInt8]? {
        guard values.count >= blockSize, values.count % blockSize == 0 else {
            return nil
        }

        var words: [UInt32] = [UInt32(values.count)]
        var offset = 0

        while offset < values.count {
            let pageValueCount = min(pageSize, values.count - offset)
            let blockCount = pageValueCount / blockSize
            var packedWords: [UInt32] = []
            var byteContainer: [UInt8] = []
            packedWords.reserveCapacity(blockCount * 8)
            byteContainer.reserveCapacity(blockCount * 2)

            for block in 0 ..< blockCount {
                let start = offset + block * blockSize
                let slice = Array(values[start ..< (start + blockSize)])
                let bitWidth = slice.reduce(0) { result, value in
                    max(result, 32 - value.leadingZeroBitCount)
                }
                byteContainer.append(UInt8(bitWidth))
                byteContainer.append(0)
                packedWords.append(contentsOf: pack(slice, bitWidth: bitWidth))
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
