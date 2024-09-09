import XCTest

@testable import MVTTools

final class QueryParserTests: XCTestCase {

    private static let properties: [String: Sendable] = [
        "foo": [
            "bar": 1,
            "baz": UInt8(10)
        ],
        "some": [
            "a",
            "b",
        ],
        "value": 1,
        "string": "Some name"
    ]

    private func result(for pipeline: [QueryParser.Expression]) -> Bool {
        QueryParser(pipeline: pipeline).evaluate(on: QueryParserTests.properties as! [String: AnyHashable])
    }

    private func pipeline(for query: String) -> [QueryParser.Expression] {
        QueryParser(string: query)?.pipeline ?? []
    }

    func testValues() throws {
        XCTAssertTrue(result(for: [.value([.key("foo")])]))
        XCTAssertTrue(result(for: [.value([.key("foo"), .key("bar")])]))
        XCTAssertFalse(result(for: [.value([.key("foo"), .key("x")])]))
        XCTAssertFalse(result(for: [.value([.key("foo.bar")])]))
        XCTAssertFalse(result(for: [.value([.key("foo"), .index(0)])]))
        XCTAssertTrue(result(for: [.value([.key("some"), .index(0)])]))
    }

    func testComparisons() throws {
        XCTAssertFalse(result(for: [.value([.key("value")]), .literal("bar"), .comparison(.equals)]))
        XCTAssertTrue(result(for: [.value([.key("value")]), .literal(1), .comparison(.equals)]))
        XCTAssertTrue(result(for: [.value([.key("value")]), .literal(1.0), .comparison(.equals)]))
        XCTAssertFalse(result(for: [.value([.key("value")]), .literal(1), .comparison(.notEquals)]))
        XCTAssertFalse(result(for: [.value([.key("value")]), .literal(1), .comparison(.greaterThan)]))
        XCTAssertTrue(result(for: [.value([.key("value")]), .literal(1), .comparison(.greaterThanOrEqual)]))
        XCTAssertTrue(result(for: [.value([.key("value")]), .literal(0.5), .comparison(.greaterThanOrEqual)]))
        XCTAssertFalse(result(for: [.value([.key("value")]), .literal(1), .comparison(.lessThan)]))
        XCTAssertTrue(result(for: [.value([.key("value")]), .literal(1), .comparison(.lessThanOrEqual)]))
        XCTAssertTrue(result(for: [.value([.key("value")]), .literal(1.5), .comparison(.lessThanOrEqual)]))
        XCTAssertTrue(result(for: [.value([.key("foo"), .key("baz")]), .literal(10), .comparison(.equals)]))
        XCTAssertFalse(result(for: [.value([.key("x")]), .literal(1), .comparison(.equals)]))
        XCTAssertTrue(result(for: [.value([.key("string")]), .literal("name$"), .comparison(.regex)]))
        XCTAssertTrue(result(for: [.value([.key("string")]), .literal("/[Ss]ome/"), .comparison(.regex)]))
        XCTAssertFalse(result(for: [.value([.key("string")]), .literal("^some"), .comparison(.regex)]))
        XCTAssertTrue(result(for: [.value([.key("string")]), .literal("/^some/i"), .comparison(.regex)]))
    }

    func testConditions() throws {
        XCTAssertTrue(result(for: [
            .value([.key("foo"), .key("bar")]),
            .literal(1),
            .comparison(.equals),
            .value([.key("value")]),
            .literal(1),
            .comparison(.equals),
            .condition(.and),
        ]))
        XCTAssertFalse(result(for: [
            .value([.key("foo")]),
            .literal(1),
            .comparison(.equals),
            .value([.key("bar")]),
            .literal(2),
            .comparison(.equals),
            .condition(.or),
        ]))
        XCTAssertTrue(result(for: [
            .value([.key("foo")]),
            .literal(1),
            .comparison(.equals),
            .value([.key("value")]),
            .literal(1),
            .comparison(.equals),
            .condition(.or),
        ]))
        XCTAssertFalse(result(for: [
            .value([.key("foo")]),
            .condition(.not),
        ]))
        XCTAssertTrue(result(for: [
            .value([.key("foo")]),
            .value([.key("bar")]),
            .condition(.and),
            .condition(.not),
        ]))
        XCTAssertFalse(result(for: [
            .value([.key("foo")]),
            .value([.key("some")]),
            .condition(.and),
            .condition(.not),
        ]))
        XCTAssertFalse(result(for: [
            .value([.key("foo")]),
            .value([.key("bar")]),
            .condition(.or),
            .condition(.not),
        ]))
        XCTAssertTrue(result(for: [
            .value([.key("x")]),
            .value([.key("y")]),
            .condition(.or),
            .condition(.not),
        ]))
        XCTAssertFalse(result(for: [
            .value([.key("foo"), .key("bar")]),
            .condition(.not),
        ]))
        XCTAssertTrue(result(for: [
            .value([.key("foo"), .key("x")]),
            .condition(.not),
        ]))
    }

    func testValueQueries() throws {
        XCTAssertEqual(pipeline(for: ".foo"), [.value([.key("foo")])])
        XCTAssertEqual(pipeline(for: ".foo.bar"), [.value([.key("foo"), .key("bar")])])
        XCTAssertEqual(pipeline(for: ".foo.x"), [.value([.key("foo"), .key("x")])])
        XCTAssertEqual(pipeline(for: ".\"foo\".\"bar\""), [.value([.key("foo"), .key("bar")])])
        XCTAssertEqual(pipeline(for: ".\"foo.bar\""), [.value([.key("foo.bar")])])
        XCTAssertEqual(pipeline(for: ".foo.[0]"), [.value([.key("foo"), .index(0)])])
        XCTAssertEqual(pipeline(for: ".some.0"), [.value([.key("some"), .index(0)])])
    }

    func testComparisonQueries() throws {
        XCTAssertEqual(pipeline(for: ".value == \"bar\""), [.value([.key("value")]), .literal("bar"), .comparison(.equals)])
        XCTAssertEqual(pipeline(for: ".value == 'bar'"), [.value([.key("value")]), .literal("bar"), .comparison(.equals)])
        XCTAssertEqual(pipeline(for: ".value == 'bar\"baz'"), [.value([.key("value")]), .literal("bar\"baz"), .comparison(.equals)])

        XCTAssertEqual(pipeline(for: ".value == 1"), [.value([.key("value")]), .literal(1), .comparison(.equals)])
        XCTAssertEqual(pipeline(for: ".value != 1"), [.value([.key("value")]), .literal(1), .comparison(.notEquals)])
        XCTAssertEqual(pipeline(for: ".value > 1"), [.value([.key("value")]), .literal(1), .comparison(.greaterThan)])
        XCTAssertEqual(pipeline(for: ".value >= 1"), [.value([.key("value")]), .literal(1), .comparison(.greaterThanOrEqual)])
        XCTAssertEqual(pipeline(for: ".value < 1"), [.value([.key("value")]), .literal(1), .comparison(.lessThan)])
        XCTAssertEqual(pipeline(for: ".value <= 1"), [.value([.key("value")]), .literal(1), .comparison(.lessThanOrEqual)])

        XCTAssertEqual(pipeline(for: ".string =~ /[Ss]ome/"), [.value([.key("string")]), .literal("/[Ss]ome/"), .comparison(.regex)])
        XCTAssertEqual(pipeline(for: ".string =~ /some/"), [.value([.key("string")]), .literal("/some/"), .comparison(.regex)])
        XCTAssertEqual(pipeline(for: ".string =~ /some/i"), [.value([.key("string")]), .literal("/some/i"), .comparison(.regex)])
        XCTAssertEqual(pipeline(for: ".string =~ \"^Some\""), [.value([.key("string")]), .literal("^Some"), .comparison(.regex)])
    }

    func testConditionQueries() throws {
        XCTAssertEqual(pipeline(for: ".foo.bar == 1 and .value == 1"), [
                .value([.key("foo"), .key("bar")]),
                .literal(1),
                .comparison(.equals),
                .value([.key("value")]),
                .literal(1),
                .comparison(.equals),
                .condition(.and),
            ])
        XCTAssertEqual(pipeline(for: ".foo == 1 or .bar == 2"), [
                .value([.key("foo")]),
                .literal(1),
                .comparison(.equals),
                .value([.key("bar")]),
                .literal(2),
                .comparison(.equals),
                .condition(.or),
            ])
        XCTAssertEqual(pipeline(for: ".foo == 1 or .value == 1"), [
                .value([.key("foo")]),
                .literal(1),
                .comparison(.equals),
                .value([.key("value")]),
                .literal(1),
                .comparison(.equals),
                .condition(.or),
            ])
        XCTAssertEqual(pipeline(for: ".foo not"), [
                .value([.key("foo")]),
                .condition(.not),
            ])
        XCTAssertEqual(pipeline(for: ".foo and .bar not"), [
                .value([.key("foo")]),
                .value([.key("bar")]),
                .condition(.and),
                .condition(.not),
            ])
        XCTAssertEqual(pipeline(for: ".foo or .bar not"), [
            .value([.key("foo")]),
            .value([.key("bar")]),
            .condition(.or),
            .condition(.not),
        ])
        XCTAssertEqual(pipeline(for: ".foo.bar not"), [
            .value([.key("foo"), .key("bar")]),
            .condition(.not),
        ])
    }

}
