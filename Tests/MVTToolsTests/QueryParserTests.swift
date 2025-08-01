import GISTools
@testable import MVTTools
import Testing

struct QueryParserTests {

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
        QueryParser(pipeline: pipeline).evaluate(
            on: QueryParserTests.properties as! [String: AnyHashable],
            coordinate: nil)
    }

    private func pipeline(for query: String) -> [QueryParser.Expression] {
        QueryParser(string: query)?.pipeline ?? []
    }

    @Test
    func values() async throws {
        #expect(result(for: [.value([.key("foo")])]))
        #expect(result(for: [.value([.key("foo"), .key("bar")])]))
        #expect(result(for: [.value([.key("foo"), .key("x")])]) == false)
        #expect(result(for: [.value([.key("foo.bar")])]) == false)
        #expect(result(for: [.value([.key("foo"), .index(0)])]) == false)
        #expect(result(for: [.value([.key("some"), .index(0)])]))
    }

    @Test
    func near() async throws {
        #expect(pipeline(for: "near(10.0, 20.0, 1000)") == [
            .near(Coordinate3D(latitude: 10.0, longitude: 20.0), 1000.0),
        ])
    }

    @Test
    func comparisons() async throws {
        #expect(result(for: [.value([.key("value")]), .literal("bar"), .comparison(.equals)]) == false)
        #expect(result(for: [.value([.key("value")]), .literal(1), .comparison(.equals)]))
        #expect(result(for: [.value([.key("value")]), .literal(1.0), .comparison(.equals)]))
        #expect(result(for: [.value([.key("value")]), .literal(1), .comparison(.notEquals)]) == false)
        #expect(result(for: [.value([.key("value")]), .literal(1), .comparison(.greaterThan)]) == false)
        #expect(result(for: [.value([.key("value")]), .literal(1), .comparison(.greaterThanOrEqual)]))
        #expect(result(for: [.value([.key("value")]), .literal(0.5), .comparison(.greaterThanOrEqual)]))
        #expect(result(for: [.value([.key("value")]), .literal(1), .comparison(.lessThan)]) == false)
        #expect(result(for: [.value([.key("value")]), .literal(1), .comparison(.lessThanOrEqual)]))
        #expect(result(for: [.value([.key("value")]), .literal(1.5), .comparison(.lessThanOrEqual)]))
        #expect(result(for: [.value([.key("foo"), .key("baz")]), .literal(10), .comparison(.equals)]))
        #expect(result(for: [.value([.key("x")]), .literal(1), .comparison(.equals)]) == false)
        #expect(result(for: [.value([.key("string")]), .literal("name$"), .comparison(.regex)]))
        #expect(result(for: [.value([.key("string")]), .literal("/[Ss]ome/"), .comparison(.regex)]))
        #expect(result(for: [.value([.key("string")]), .literal("^some"), .comparison(.regex)]) == false)
        #expect(result(for: [.value([.key("string")]), .literal("/^some/i"), .comparison(.regex)]))
    }

    @Test
    func conditions() async throws {
        #expect(result(for: [
            .value([.key("foo"), .key("bar")]),
            .literal(1),
            .comparison(.equals),
            .value([.key("value")]),
            .literal(1),
            .comparison(.equals),
            .condition(.and),
        ]))
        #expect(result(for: [
            .value([.key("foo")]),
            .literal(1),
            .comparison(.equals),
            .value([.key("bar")]),
            .literal(2),
            .comparison(.equals),
            .condition(.or),
        ]) == false)
        #expect(result(for: [
            .value([.key("foo")]),
            .literal(1),
            .comparison(.equals),
            .value([.key("value")]),
            .literal(1),
            .comparison(.equals),
            .condition(.or),
        ]))
        #expect(result(for: [
            .value([.key("foo")]),
            .condition(.not),
        ]) == false)
        #expect(result(for: [
            .value([.key("foo")]),
            .value([.key("bar")]),
            .condition(.and),
            .condition(.not),
        ]))
        #expect(result(for: [
            .value([.key("foo")]),
            .value([.key("some")]),
            .condition(.and),
            .condition(.not),
        ]) == false)
        #expect(result(for: [
            .value([.key("foo")]),
            .value([.key("bar")]),
            .condition(.or),
            .condition(.not),
        ]) == false)
        #expect(result(for: [
            .value([.key("x")]),
            .value([.key("y")]),
            .condition(.or),
            .condition(.not),
        ]))
        #expect(result(for: [
            .value([.key("foo"), .key("bar")]),
            .condition(.not),
        ]) == false)
        #expect(result(for: [
            .value([.key("foo"), .key("x")]),
            .condition(.not),
        ]))
    }

    @Test
    func valueQueries() async throws {
        #expect(pipeline(for: ".foo") == [.value([.key("foo")])])
        #expect(pipeline(for: ".foo.bar") == [.value([.key("foo"), .key("bar")])])
        #expect(pipeline(for: ".foo.x") == [.value([.key("foo"), .key("x")])])
        #expect(pipeline(for: ".\"foo\".\"bar\"") == [.value([.key("foo"), .key("bar")])])
        #expect(pipeline(for: ".\"foo.bar\"") == [.value([.key("foo.bar")])])
        #expect(pipeline(for: ".foo.[0]") == [.value([.key("foo"), .index(0)])])
        #expect(pipeline(for: ".some.0") == [.value([.key("some"), .index(0)])])
    }

    @Test
    func comparisonQueries() async throws {
        #expect(pipeline(for: ".value == \"bar\"") == [.value([.key("value")]), .literal("bar"), .comparison(.equals)])
        #expect(pipeline(for: ".value == 'bar'") == [.value([.key("value")]), .literal("bar"), .comparison(.equals)])
        #expect(pipeline(for: ".value == 'bar\"baz'") == [.value([.key("value")]), .literal("bar\"baz"), .comparison(.equals)])

        #expect(pipeline(for: ".value == 1") == [.value([.key("value")]), .literal(1), .comparison(.equals)])
        #expect(pipeline(for: ".value != 1") == [.value([.key("value")]), .literal(1), .comparison(.notEquals)])
        #expect(pipeline(for: ".value > 1") == [.value([.key("value")]), .literal(1), .comparison(.greaterThan)])
        #expect(pipeline(for: ".value >= 1") == [.value([.key("value")]), .literal(1), .comparison(.greaterThanOrEqual)])
        #expect(pipeline(for: ".value < 1") == [.value([.key("value")]), .literal(1), .comparison(.lessThan)])
        #expect(pipeline(for: ".value <= 1") == [.value([.key("value")]), .literal(1), .comparison(.lessThanOrEqual)])

        #expect(pipeline(for: ".string =~ /[Ss]ome/") == [.value([.key("string")]), .literal("/[Ss]ome/"), .comparison(.regex)])
        #expect(pipeline(for: ".string =~ /some/") == [.value([.key("string")]), .literal("/some/"), .comparison(.regex)])
        #expect(pipeline(for: ".string =~ /some/i") == [.value([.key("string")]), .literal("/some/i"), .comparison(.regex)])
        #expect(pipeline(for: ".string =~ \"^Some\"") == [.value([.key("string")]), .literal("^Some"), .comparison(.regex)])
    }

    @Test
    func conditionQueries() async throws {
        #expect(pipeline(for: ".foo.bar == 1 and .value == 1") == [
                .value([.key("foo"), .key("bar")]),
                .literal(1),
                .comparison(.equals),
                .value([.key("value")]),
                .literal(1),
                .comparison(.equals),
                .condition(.and),
            ])
        #expect(pipeline(for: ".foo == 1 or .bar == 2") == [
                .value([.key("foo")]),
                .literal(1),
                .comparison(.equals),
                .value([.key("bar")]),
                .literal(2),
                .comparison(.equals),
                .condition(.or),
            ])
        #expect(pipeline(for: ".foo == 1 or .value == 1") == [
                .value([.key("foo")]),
                .literal(1),
                .comparison(.equals),
                .value([.key("value")]),
                .literal(1),
                .comparison(.equals),
                .condition(.or),
            ])
        #expect(pipeline(for: ".foo not") == [
                .value([.key("foo")]),
                .condition(.not),
            ])
        #expect(pipeline(for: ".foo and .bar not") == [
                .value([.key("foo")]),
                .value([.key("bar")]),
                .condition(.and),
                .condition(.not),
            ])
        #expect(pipeline(for: ".foo or .bar not") == [
            .value([.key("foo")]),
            .value([.key("bar")]),
            .condition(.or),
            .condition(.not),
        ])
        #expect(pipeline(for: ".foo.bar not") == [
            .value([.key("foo"), .key("bar")]),
            .condition(.not),
        ])
        #expect(pipeline(for: ".foo == 'not'") == [
            .value([.key("foo")]),
            .literal("not"),
            .comparison(.equals),
        ])
    }

}
