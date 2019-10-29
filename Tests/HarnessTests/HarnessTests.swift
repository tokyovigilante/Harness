import XCTest
@testable import Harness

final class HarnessTests: XCTestCase {

    func testStuff () {
        XCTAssertEqual(1, 1)
    }

    static var allTests = [
        ("testStuff", testStuff),
    ]
}
