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

    /// A trained candidate symbol and its selection score.
    private struct Candidate {
        var bytes: UInt64
        var length: UInt8
        var score: Int

        var byteArray: [UInt8] {
            var result: [UInt8] = []
            result.reserveCapacity(Int(length))
            for shift in stride(from: 0, to: Int(length) * 8, by: 8) {
                result.append(UInt8(truncatingIfNeeded: bytes >> UInt64(shift)))
            }
            return result
        }
    }

    /// Keeps the best elements under a caller-supplied ordering.
    ///
    /// The heap root is the worst kept element, so a new element only needs a
    /// single comparison to be rejected once the capacity is reached.
    private struct BoundedSelection<Element> {

        private var heap: [Element] = []
        private let capacity: Int
        private let isWorse: (Element, Element) -> Bool

        init(capacity: Int, isWorse: @escaping (Element, Element) -> Bool) {
            self.capacity = capacity
            self.isWorse = isWorse
            heap.reserveCapacity(capacity)
        }

        var elements: [Element] { heap }

        mutating func insert(_ element: Element) {
            if heap.count < capacity {
                heap.append(element)
                siftUp(from: heap.count - 1)
            }
            else if isWorse(heap[0], element) {
                heap[0] = element
                siftDown(from: 0)
            }
        }

        private mutating func siftUp(from start: Int) {
            var index = start
            while index > 0 {
                let parent = (index - 1) / 2
                guard isWorse(heap[index], heap[parent]) else { return }
                heap.swapAt(index, parent)
                index = parent
            }
        }

        private mutating func siftDown(from start: Int) {
            var index = start
            while true {
                let left = index * 2 + 1
                let right = left + 1
                var worst = index
                if left < heap.count, isWorse(heap[left], heap[worst]) {
                    worst = left
                }
                if right < heap.count, isWorse(heap[right], heap[worst]) {
                    worst = right
                }
                guard worst != index else { return }
                heap.swapAt(index, worst)
                index = worst
            }
        }

    }

    /// Open-addressing counter for up to eight-byte symbols.
    ///
    /// The substrings are packed into a `UInt64`, which avoids one heap
    /// allocation per candidate and keeps hashing cheap while training.
    private struct SymbolCounts {

        private var keys: [UInt64]
        private var lengths: [UInt8]
        private var values: [Int32]
        private let mask: Int

        private(set) var distinctCount = 0

        /// Creates a counter sized for the given number of distinct symbols.
        ///
        /// - Parameter expectedMaximum: An upper bound for the number of
        ///   distinct symbols. The table targets a load factor of at most 0.5.
        init(expectedMaximum: Int) {
            var capacity = 16
            while capacity < max(1, expectedMaximum) * 2 {
                capacity <<= 1
            }
            keys = [UInt64](repeating: 0, count: capacity)
            lengths = [UInt8](repeating: 0, count: capacity)
            values = [Int32](repeating: 0, count: capacity)
            mask = capacity - 1
        }

        /// Adds one occurrence of the given symbol.
        ///
        /// - Parameters:
        ///   - bytes: The packed symbol bytes, first byte in the least
        ///     significant byte.
        ///   - length: The number of bytes in the symbol.
        ///   - limit: The maximum number of distinct symbols to keep.
        mutating func add(bytes: UInt64, length: UInt8, limit: Int) {
            var index = Self.startIndex(bytes: bytes, length: length, mask: mask)
            while true {
                let value = values[index]
                if value == 0 {
                    guard distinctCount < limit else { return }
                    keys[index] = bytes
                    lengths[index] = length
                    values[index] = 1
                    distinctCount += 1
                    return
                }
                if keys[index] == bytes, lengths[index] == length {
                    values[index] = value + 1
                    return
                }
                index = (index + 1) & mask
            }
        }

        /// Calls `body` for every distinct symbol and its occurrence count.
        func forEach(_ body: (UInt64, UInt8, Int32) -> Void) {
            for index in values.indices where values[index] != 0 {
                body(keys[index], lengths[index], values[index])
            }
        }

        private static func startIndex(bytes: UInt64, length: UInt8, mask: Int) -> Int {
            var hash = bytes &+ (UInt64(length) &* 0x9E37_79B9_7F4A_7C15)
            hash ^= hash >> 30
            hash &*= 0xBF58_476D_1CE4_E5B9
            hash ^= hash >> 27
            hash &*= 0x94D0_49BB_1331_11EB
            hash ^= hash >> 31
            return Int(hash & UInt64(mask))
        }

    }

    private enum Packing {

        /// Packs up to eight bytes into an integer, first byte least significant.
        @inline(__always)
        static func packed(_ value: [UInt8], start: Int, length: Int) -> UInt64 {
            var packed: UInt64 = 0
            var shift = 0
            for index in start ..< (start + length) {
                packed |= UInt64(value[index]) << shift
                shift += 8
            }
            return packed
        }

    }

    static func encode(_ strings: [String]) -> Result? {
        let values = strings.map { Array($0.utf8) }
        let byteCount = values.reduce(0) { $0 + $1.count }
        guard byteCount > 0 else { return nil }

        // The number of distinct symbols cannot exceed the number of
        // substrings, which is bounded by eight per input byte.
        var counts = SymbolCounts(
            expectedMaximum: min(maximumCandidateCount, byteCount * maximumSymbolLength))

        for value in values {
            let limit = min(maximumSymbolLength, value.count)
            guard limit > 0 else { continue }
            for length in 1 ... limit {
                for start in 0 ... (value.count - length) {
                    counts.add(
                        bytes: Packing.packed(value, start: start, length: length),
                        length: UInt8(length),
                        limit: maximumCandidateCount)
                }
            }
        }

        var selection = BoundedSelection<Candidate>(capacity: maximumSymbols) { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.length != rhs.length { return lhs.length < rhs.length }
            return lhs.bytes > rhs.bytes
        }

        counts.forEach { bytes, length, count in
            let score = length == 1
                ? Int(count) / 8
                : Int(count) * (Int(length) - 1)
            guard score > 0 else { return }
            selection.insert(Candidate(bytes: bytes, length: length, score: score))
        }

        var selected = selection.elements
        guard !selected.isEmpty else { return nil }

        selected.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.length != rhs.length { return lhs.length > rhs.length }
            return lhs.bytes < rhs.bytes
        }

        var symbols: [UInt8] = []
        var symbolLengths: [UInt32] = []
        var matches: [[(bytes: [UInt8], code: UInt8)]] = Array(repeating: [], count: 256)
        for (index, entry) in selected.enumerated() {
            let code = UInt8(index)
            let bytes = entry.byteArray
            symbols.append(contentsOf: bytes)
            symbolLengths.append(UInt32(bytes.count))
            matches[Int(bytes[0])].append((bytes, code))
        }
        for index in matches.indices where matches[index].count > 1 {
            matches[index].sort { $0.bytes.count > $1.bytes.count }
        }

        var compressedData: [UInt8] = []
        compressedData.reserveCapacity(byteCount)

        for value in values {
            var index = 0
            while index < value.count {
                var matched = false
                for candidate in matches[Int(value[index])] {
                    let length = candidate.bytes.count
                    guard index + length <= value.count else { continue }
                    if value[index ..< (index + length)].elementsEqual(candidate.bytes) {
                        compressedData.append(candidate.code)
                        index += length
                        matched = true
                        break
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
