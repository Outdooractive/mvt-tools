import Foundation
@testable import MVTTools
import Testing

struct IntExtensionsTests {

    @Test
    func asInt() {
        let value8: Int8 = 42
        let value16: Int16 = -128
        let value32: Int32 = 1_000_000
        let value64: Int64 = 9_223_372_036_854_775_807

        #expect(value8.asInt == 42)
        #expect(value16.asInt == -128)
        #expect(value32.asInt == 1_000_000)
        #expect(value64.asInt == Int(9_223_372_036_854_775_807))
    }

    @Test
    func asUInt() {
        let value8: UInt8 = 42
        let value16: UInt16 = 255
        let value32: UInt32 = 4_000_000_000
        let value64: UInt64 = 18_446_744_073_709_551_615

        #expect(value8.asUInt == 42)
        #expect(value16.asUInt == 255)
        #expect(value32.asUInt == 4_000_000_000)
        #expect(value64.asUInt == UInt(18_446_744_073_709_551_615))
    }

}

struct DoubleExtensionsTests {

    @Test
    func asDouble() {
        let value: Float = 3.14
        #expect(abs(value.asDouble - 3.14) < 0.001)
    }

}

struct StringExtensionsTests {

    @Test
    func isNotEmptyString() {
        #expect("".isNotEmpty == false)
        #expect("hello".isNotEmpty)
        #expect(" ".isNotEmpty)
    }

    @Test
    func trimAndTrimmed() {
        var string = "  hello world  "
        #expect(string.trimmed() == "hello world")
        string.trim()
        #expect(string == "hello world")

        let noPadding = "hello"
        #expect(noPadding.trimmed() == "hello")
    }

}
