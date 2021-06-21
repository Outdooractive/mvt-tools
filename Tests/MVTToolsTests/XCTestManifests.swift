import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(ArrayExtensionsTests.allTests),
        testCase(DecoderTests.allTests),
        testCases(EncoderTests.allTests),
        testCase(ProjectionTests.allTests),
        testCase(VectorTileTests.allTests),
    ]
}
#endif
