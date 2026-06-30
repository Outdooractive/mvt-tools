@testable import MVTTools
import Testing

struct ArrayExtensionsTests {

    /// Tests that `pairs()` correctly groups even-length arrays into adjacent pairs.
    @Test
    func pairs() {
        let even: [Int] = [1, 2, 3, 4, 5, 6]
        let uneven: [Int] = [1, 2, 3, 4, 5]

        let evenPairs = even.pairs()
        let unevenPairs = uneven.pairs()

        #expect(evenPairs.count == 3)
        #expect(unevenPairs.count == 2)

        #expect(evenPairs[0].first == 1)
        #expect(evenPairs[0].second == 2)
        #expect(evenPairs[1].first == 3)
        #expect(evenPairs[1].second == 4)
        #expect(evenPairs[2].first == 5)
        #expect(evenPairs[2].second == 6)

        #expect(unevenPairs[0].first == 1)
        #expect(unevenPairs[0].second == 2)
        #expect(unevenPairs[1].first == 3)
        #expect(unevenPairs[1].second == 4)
    }

    /// Tests that `pairs()` returns empty for empty or single-element arrays.
    @Test
    func smallPairs() {
        let empty: [Int] = []
        let small = [1]

        let emptyPairs = empty.pairs()
        let smallPairs = small.pairs()

        #expect(emptyPairs.count == 0)
        #expect(smallPairs.count == 0)
    }

    /// Tests that `get(at:)` handles positive, negative, and out-of-bounds indices.
    @Test
    func get() {
        let array = [0, 1, 2, 3, 4, 5, 6]

        #expect(array.get(at: 0) == 0)
        #expect(array.get(at: 4) == 4)
        #expect(array.get(at: -1) == 6)
        #expect(array.get(at: -5) == 2)

        #expect(array.get(at: 7) == nil)
        #expect(array.get(at: -8) == nil)
    }

    /// Tests that `isNotEmpty` correctly reflects non-empty state.
    @Test
    func isNotEmptyArray() {
        let empty: [Int] = []
        let filled = [1, 2, 3]

        #expect(empty.isNotEmpty == false)
        #expect(filled.isNotEmpty)
    }

    /// Tests that `append(ifNotNil:)` only appends non-nil elements.
    @Test
    func appendIfNotNil() {
        var array: [Int] = [1, 2, 3]
        let valid: Int? = 4
        let nilValue: Int? = nil

        array.append(ifNotNil: valid)
        #expect(array == [1, 2, 3, 4])

        array.append(ifNotNil: nilValue)
        #expect(array == [1, 2, 3, 4])
    }

    /// Tests that `divided(byKey:onKey:)` correctly partitions elements by a key function.
    @Test
    func dividedByKey() {
        let items = [
            ("group_a", "item1"),
            ("group_b", "item2"),
            ("group_a", "item3"),
            ("group_c", "item4"),
        ]

        var result: [String: [String]] = [:]
        items.divided(
            byKey: { $0.0 },
            onKey: { key, values in
                result[key] = values.map { $0.1 }
            })

        #expect(result.keys.count == 3)
        #expect(result["group_a"] == ["item1", "item3"])
        #expect(result["group_b"] == ["item2"])
        #expect(result["group_c"] == ["item4"])
    }

    /// Tests that `divided(byKey:onKey:)` skips elements with a nil key.
    @Test
    func dividedByKeySkipsNilKeys() {
        let items: [(String?, String)] = [
            ("a", "item1"),
            (nil, "should_be_skipped"),
            ("b", "item2"),
        ]

        var result: [String: [String]] = [:]
        items.divided(
            byKey: { $0.0 },
            onKey: { key, values in
                result[key] = values.map { $0.1 }
            })

        #expect(result.keys.count == 2)
        #expect(result["a"] == ["item1"])
        #expect(result["b"] == ["item2"])
    }

}
