import Foundation

/// A small FSST encoder used for dictionary corpora.
///
/// It trains a symbol table from frequent byte substrings and greedily emits
/// the longest matching symbol. The resulting stream is always validated by
/// the FSST decoder and only selected when it reduces the encoded size.
enum MLTFSSTEncoder {

    struct Result {
        var symbols: [UInt8]
        var symbolLengths: [UInt32]
        var compressedData: [UInt8]
        var decompressedLength: Int
    }

    private static let maximumSymbols = 255
    private static let maximumCandidateCount = 50_000
    private static let maximumSymbolLength = 8

    /// A fixed-size, allocation-free key for a byte substring of up to eight bytes.
    ///
    /// Keeping the symbols inline avoids one heap allocation per substring while
    /// training, which dominates the cost for large string dictionaries.
    private struct SymbolKey: Hashable {
        var bytes: UInt64
        var length: UInt8

        init(_ value: [UInt8], start: Int, length: Int) {
            var packed: UInt64 = 0
            var shift = 0
            for index in start ..< (start + length) {
                packed |= UInt64(value[index]) << shift
                shift += 8
            }
            self.bytes = packed
            self.length = UInt8(length)
        }

        var byteCount: Int {
            Int(length)
        }

        var byteArray: [UInt8] {
            var result: [UInt8] = []
            result.reserveCapacity(byteCount)
            for shift in stride(from: 0, to: byteCount * 8, by: 8) {
                result.append(UInt8(truncatingIfNeeded: bytes >> UInt64(shift)))
            }
            return result
        }

        /// Byte-wise lexicographic order, matching the order of the byte arrays.
        ///
        /// Equal-length keys can be compared by their packed integer value,
        /// because the first byte occupies the least significant byte.
        func lexicographicallyPrecedes(_ other: SymbolKey) -> Bool {
            if length != other.length {
                return length < other.length
            }
            return bytes < other.bytes
        }
    }

    static func encode(_ strings: [String]) -> Result? {
        let values = strings.map { Array($0.utf8) }
        let byteCount = values.reduce(0) { $0 + $1.count }
        guard byteCount > 0 else { return nil }

        var frequencies: [SymbolKey: Int] = [:]
        frequencies.reserveCapacity(min(byteCount, maximumCandidateCount))

        for value in values {
            let limit = min(maximumSymbolLength, value.count)
            guard limit > 0 else { continue }
            for length in 1 ... limit {
                for start in 0 ... (value.count - length) {
                    let symbol = SymbolKey(value, start: start, length: length)
                    if frequencies[symbol] != nil {
                        frequencies[symbol, default: 0] += 1
                    }
                    else if frequencies.count < maximumCandidateCount {
                        frequencies[symbol] = 1
                    }
                }
            }
        }

        let selected = frequencies
            .map { symbol, count -> (symbol: SymbolKey, score: Int) in
                let score = symbol.byteCount == 1
                    ? count / 8
                    : count * (symbol.byteCount - 1)
                return (symbol, score)
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.symbol.length != rhs.symbol.length {
                    return lhs.symbol.length > rhs.symbol.length
                }
                return lhs.symbol.lexicographicallyPrecedes(rhs.symbol)
            }
            .prefix(maximumSymbols)

        guard !selected.isEmpty else { return nil }

        var symbols: [UInt8] = []
        var symbolLengths: [UInt32] = []
        var matches: [UInt8: [(bytes: [UInt8], code: UInt8)]] = [:]
        for (index, entry) in selected.enumerated() {
            let code = UInt8(index)
            let bytes = entry.symbol.byteArray
            symbols.append(contentsOf: bytes)
            symbolLengths.append(UInt32(bytes.count))
            matches[bytes[0], default: []].append((bytes, code))
        }
        for key in matches.keys {
            matches[key]?.sort { $0.bytes.count > $1.bytes.count }
        }

        var compressedData: [UInt8] = []
        compressedData.reserveCapacity(byteCount)

        for value in values {
            var index = 0
            while index < value.count {
                var matched = false
                if let candidates = matches[value[index]] {
                    for candidate in candidates {
                        let length = candidate.bytes.count
                        guard index + length <= value.count else { continue }
                        if value[index ..< (index + length)].elementsEqual(candidate.bytes) {
                            compressedData.append(candidate.code)
                            index += length
                            matched = true
                            break
                        }
                    }
                }
                if !matched {
                    compressedData.append(255)
                    compressedData.append(value[index])
                    index += 1
                }
            }
        }

        return Result(
            symbols: symbols,
            symbolLengths: symbolLengths,
            compressedData: compressedData,
            decompressedLength: byteCount)
    }

}
