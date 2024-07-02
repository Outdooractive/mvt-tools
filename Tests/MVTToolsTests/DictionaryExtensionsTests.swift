import XCTest

@testable import MVTTools

final class DictionaryExtensionsTests: XCTestCase {

    func testHasKey() async throws {
        let dict: [String: Any] = [
            "a": "value",
        ]

        XCTAssertTrue(dict.hasKey("a"))
        XCTAssertFalse(dict.hasKey("b"))
    }

}
