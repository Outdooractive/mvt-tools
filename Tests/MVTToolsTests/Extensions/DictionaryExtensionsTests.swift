@testable import MVTTools
import Testing

struct DictionaryExtensionsTests {

    @Test
    func hasKey() async throws {
        let dict: [String: Any] = [
            "a": "value",
        ]

        #expect(dict.hasKey("a"))
        #expect(dict.hasKey("b") == false)
    }

}
