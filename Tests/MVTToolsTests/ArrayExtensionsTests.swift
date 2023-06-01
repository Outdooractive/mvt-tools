import XCTest

@testable import MVTTools

final class ArrayExtensionsTests: XCTestCase {

    func testPairs() {
        let even: [Int] = [1, 2, 3, 4, 5, 6]
        let uneven: [Int] = [1, 2, 3, 4, 5]

        let evenPairs = even.pairs()
        let unevenPairs = uneven.pairs()

        XCTAssertEqual(evenPairs.count, 3)
        XCTAssertEqual(unevenPairs.count, 2)

        XCTAssertEqual(evenPairs[0].first, 1)
        XCTAssertEqual(evenPairs[0].second, 2)
        XCTAssertEqual(evenPairs[1].first, 3)
        XCTAssertEqual(evenPairs[1].second, 4)
        XCTAssertEqual(evenPairs[2].first, 5)
        XCTAssertEqual(evenPairs[2].second, 6)

        XCTAssertEqual(unevenPairs[0].first, 1)
        XCTAssertEqual(unevenPairs[0].second, 2)
        XCTAssertEqual(unevenPairs[1].first, 3)
        XCTAssertEqual(unevenPairs[1].second, 4)
    }

    func testSmallPairs() {
        let empty: [Int] = []
        let small: [Int] = [1]

        let emptyPairs = empty.pairs()
        let smallPairs = small.pairs()

        XCTAssertEqual(emptyPairs.count, 0)
        XCTAssertEqual(smallPairs.count, 0)
    }

    func testGet() {
        let array = [0, 1, 2, 3, 4, 5, 6]

        XCTAssertEqual(array.get(at: 0), 0)
        XCTAssertEqual(array.get(at: 4), 4)
        XCTAssertEqual(array.get(at: -1), 6)
        XCTAssertEqual(array.get(at: -5), 2)

        XCTAssertNil(array.get(at: 7))
        XCTAssertNil(array.get(at: -8))
    }

}
