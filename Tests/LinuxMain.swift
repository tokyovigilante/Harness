import XCTest

import HarnessTests

var tests = [XCTestCaseEntry]()
tests += HarnessTests.allTests()
XCTMain(tests)
