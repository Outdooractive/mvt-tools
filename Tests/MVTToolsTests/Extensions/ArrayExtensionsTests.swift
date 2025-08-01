@testable import MVTTools
import Testing

struct ArrayExtensionsTests {

    @Test
    func pairs() async throws {
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

    @Test
    func smallPairs() async throws {
        let empty: [Int] = []
        let small = [1]

        let emptyPairs = empty.pairs()
        let smallPairs = small.pairs()

        #expect(emptyPairs.count == 0)
        #expect(smallPairs.count == 0)
    }

    @Test
    func get() async throws {
        let array = [0, 1, 2, 3, 4, 5, 6]

        #expect(array.get(at: 0) == 0)
        #expect(array.get(at: 4) == 4)
        #expect(array.get(at: -1) == 6)
        #expect(array.get(at: -5) == 2)

        #expect(array.get(at: 7) == nil)
        #expect(array.get(at: -8) == nil)
    }

}
