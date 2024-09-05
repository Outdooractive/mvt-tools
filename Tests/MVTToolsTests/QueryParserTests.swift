import XCTest

@testable import MVTTools

final class QueryParserTests: XCTestCase {

    private static let properties: [String: Sendable] = [
        "foo": [
            "bar": 1,
        ],
        "some": [
            "a",
            "b",
        ],
        "value": 1,
        "string": "Some name"
    ]

    private func result(for pipeline: [QueryParser.Expression]) -> Bool {
        QueryParser(pipeline: pipeline).evaluate(on: QueryParserTests.properties)
    }

    func testValues() throws {
        XCTAssertTrue(result(for: [.valueFor(["foo"])]))
        XCTAssertTrue(result(for: [.valueFor(["foo", "bar"])]))
        XCTAssertFalse(result(for: [.valueFor(["foo", "x"])]))
        XCTAssertFalse(result(for: [.valueFor(["foo.bar"])]))
        XCTAssertFalse(result(for: [.valueFor(["foo"]), .valueAt(0)]))
        XCTAssertTrue(result(for: [.valueFor(["some"]), .valueAt(0)]))
    }

    func testComparisons() throws {
        XCTAssertFalse(result(for: [.valueFor(["value"]), .literal("bar"), .comparison(.equals)]))
        XCTAssertTrue(result(for: [.valueFor(["value"]), .literal(1), .comparison(.equals)]))
        XCTAssertTrue(result(for: [.valueFor(["value"]), .literal(1.0), .comparison(.equals)]))
        XCTAssertFalse(result(for: [.valueFor(["value"]), .literal(1), .comparison(.notEquals)]))
        XCTAssertFalse(result(for: [.valueFor(["value"]), .literal(1), .comparison(.greaterThan)]))
        XCTAssertTrue(result(for: [.valueFor(["value"]), .literal(1), .comparison(.greaterThanOrEqual)]))
        XCTAssertTrue(result(for: [.valueFor(["value"]), .literal(0.5), .comparison(.greaterThanOrEqual)]))
        XCTAssertFalse(result(for: [.valueFor(["value"]), .literal(1), .comparison(.lessThan)]))
        XCTAssertTrue(result(for: [.valueFor(["value"]), .literal(1), .comparison(.lessThanOrEqual)]))
        XCTAssertTrue(result(for: [.valueFor(["value"]), .literal(1.5), .comparison(.lessThanOrEqual)]))
        XCTAssertFalse(result(for: [.valueFor(["x"]), .literal(1), .comparison(.equals)]))
        XCTAssertTrue(result(for: [.valueFor(["string"]), .literal("name$"), .comparison(.regex)]))
        XCTAssertTrue(result(for: [.valueFor(["string"]), .literal("/[Ss]ome/"), .comparison(.regex)]))
        XCTAssertFalse(result(for: [.valueFor(["string"]), .literal("^some"), .comparison(.regex)]))
        XCTAssertTrue(result(for: [.valueFor(["string"]), .literal("/^some/i"), .comparison(.regex)]))
    }

    func testConditions() throws {
        XCTAssertTrue(result(for: [
            .valueFor(["foo", "bar"]),
            .literal(1),
            .comparison(.equals),
            .valueFor(["value"]),
            .literal(1),
            .comparison(.equals),
            .condition(.and),
        ]))
        XCTAssertFalse(result(for: [
            .valueFor(["foo"]),
            .literal(1),
            .comparison(.equals),
            .valueFor(["bar"]),
            .literal(2),
            .comparison(.equals),
            .condition(.or),
        ]))
        XCTAssertTrue(result(for: [
            .valueFor(["foo"]),
            .literal(1),
            .comparison(.equals),
            .valueFor(["value"]),
            .literal(1),
            .comparison(.equals),
            .condition(.or),
        ]))
        XCTAssertFalse(result(for: [
            .valueFor(["foo"]),
            .condition(.not),
        ]))
        XCTAssertTrue(result(for: [
            .valueFor(["foo"]),
            .valueFor(["bar"]),
            .condition(.and),
            .condition(.not),
        ]))
        XCTAssertFalse(result(for: [
            .valueFor(["foo"]),
            .valueFor(["some"]),
            .condition(.and),
            .condition(.not),
        ]))
        XCTAssertFalse(result(for: [
            .valueFor(["foo"]),
            .valueFor(["bar"]),
            .condition(.or),
            .condition(.not),
        ]))
        XCTAssertTrue(result(for: [
            .valueFor(["x"]),
            .valueFor(["y"]),
            .condition(.or),
            .condition(.not),
        ]))
        XCTAssertFalse(result(for: [
            .valueFor(["foo", "bar"]),
            .condition(.not),
        ]))
        XCTAssertTrue(result(for: [
            .valueFor(["foo", "x"]),
            .condition(.not),
        ]))
    }

}
