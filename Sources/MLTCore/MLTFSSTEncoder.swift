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

    static func encode(_ strings: [String]) -> Result? {
        let values = strings.map { Array($0.utf8) }
        let byteCount = values.reduce(0) { $0 + $1.count }
        guard byteCount > 0 else { return nil }

        var frequencies: [[UInt8]: Int] = [:]
        frequencies.reserveCapacity(min(byteCount, maximumCandidateCount))

        for value in values {
            let limit = min(maximumSymbolLength, value.count)
            guard limit > 0 else { continue }
            for length in 1 ... limit {
                for start in 0 ... (value.count - length) {
                    let symbol = Array(value[start ..< (start + length)])
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
            .map { symbol, count -> (symbol: [UInt8], score: Int) in
                let score = symbol.count == 1
                    ? count / 8
                    : count * (symbol.count - 1)
                return (symbol, score)
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.symbol.count != rhs.symbol.count {
                    return lhs.symbol.count > rhs.symbol.count
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
            symbols.append(contentsOf: entry.symbol)
            symbolLengths.append(UInt32(entry.symbol.count))
            matches[entry.symbol[0], default: []].append((entry.symbol, code))
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
