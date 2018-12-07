import XCTest

#if !os(macOS)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(RegressionTests.allTests),
        testCase(RulesTests.allTests),
    ]
}
#endif
