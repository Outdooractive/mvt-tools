#if EnableMLT
import Foundation
@testable import MLTCore
import Testing

struct MLTFSSTTests {

    @Test
    func expandsSymbolsAndEscapes() throws {
        // Symbol 0 = "a", symbol 1 = "bc"; 255 escapes the next literal byte.
        let symbols: [UInt8] = Array("abc".utf8)
        let symbolLengths: [UInt32] = [1, 2]
        let compressed: [UInt8] = [0, 1, 255, 0x41, 0]

        let decoded = try MLTFSST.decode(
            symbols: symbols,
            symbolLengths: symbolLengths,
            compressedData: compressed,
            decompressedLength: 8)

        #expect(String(decoding: decoded, as: UTF8.self) == "abcAa")
    }

    @Test
    func invalidSymbolIndexThrows() {
        #expect(throws: (any Error).self) {
            _ = try MLTFSST.decode(
                symbols: [0x61],
                symbolLengths: [1],
                compressedData: [3],
                decompressedLength: 1)
        }
    }

    @Test
    func truncatedEscapeThrows() {
        #expect(throws: (any Error).self) {
            _ = try MLTFSST.decode(
                symbols: [],
                symbolLengths: [],
                compressedData: [255],
                decompressedLength: 1)
        }
    }

    @Test
    func emptyCorpusReturnsEmptyOutput() throws {
        let decoded = try MLTFSST.decode(
            symbols: [],
            symbolLengths: [],
            compressedData: [],
            decompressedLength: 0)
        #expect(decoded.isEmpty)
    }

}

#endif
