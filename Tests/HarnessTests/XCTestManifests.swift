import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(HarnessTests.allTests),
        testCase(StringTests.allTests)
    ]
}
#endif
