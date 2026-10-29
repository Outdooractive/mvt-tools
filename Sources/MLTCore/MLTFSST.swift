import Foundation

// FSST decoding follows the upstream `maplibre-tile-spec` / FSST
// implementation (MIT OR Apache-2.0).
/// Pure Swift FSST dictionary decoder.
///
/// MLT stores an FSST symbol table plus a compressed corpus. The algorithm is
/// intentionally simple: each compressed byte is either an escape (255)
/// followed by a literal byte, or an index into the symbol table.
enum MLTFSST {

    static func decode(
        symbols: [UInt8],
        symbolLengths: [UInt32],
        compressedData: [UInt8],
        decompressedLength: Int
    ) throws -> [UInt8] {
        guard decompressedLength >= 0 else {
            throw MLTError.invalidData("Negative FSST decompressed length")
        }
        guard symbolLengths.count <= MLTIntegerDecoder.maximumValues else {
            throw MLTError.invalidData("FSST symbol table is too large")
        }

        var symbolOffsets = [Int](repeating: 0, count: symbolLengths.count)
        if symbolLengths.count > 1 {
            for index in 1 ..< symbolLengths.count {
                symbolOffsets[index] = symbolOffsets[index - 1] + Int(symbolLengths[index - 1])
            }
        }

        var output: [UInt8] = []
        output.reserveCapacity(max(decompressedLength, compressedData.count))

        var index = 0
        while index < compressedData.count {
            let symbolIndex = compressedData[index]
            index += 1

            if symbolIndex == 255 {
                guard index < compressedData.count else {
                    throw MLTError.invalidData("FSST escape byte at the end of the corpus")
                }
                output.append(compressedData[index])
                index += 1
                continue
            }

            let dictionaryIndex = Int(symbolIndex)
            guard dictionaryIndex < symbolLengths.count else {
                throw MLTError.invalidData("FSST symbol index \(dictionaryIndex) is out of bounds")
            }
            let offset = symbolOffsets[dictionaryIndex]
            let length = Int(symbolLengths[dictionaryIndex])
            guard offset >= 0, length >= 0, offset + length <= symbols.count else {
                throw MLTError.invalidData("FSST symbol is out of bounds")
            }
            output.append(contentsOf: symbols[offset ..< (offset + length)])
        }

        return output
    }

}
