@testable import MVTTools
import Testing

struct DictionaryExtensionsTests {

    /// Tests that `hasKey(_:)` correctly identifies present and absent keys.
    @Test
    func hasKey() {
        let dict: [String: Any] = [
            "a": "value",
        ]

        #expect(dict.hasKey("a"))
        #expect(dict.hasKey("b") == false)
    }

}
