import XCTest
@testable import Harness

final class HarnessTests: XCTestCase {

    func testStringFirstParagraph () {
        XCTAssertEqual("".firstParagraph, "")
        XCTAssertEqual("Hello\nWorld".firstParagraph, "Hello")
        XCTAssertEqual("Hello\r\nWorld".firstParagraph, "Hello")
        XCTAssertEqual("Hello\r\nWorld".firstParagraph, "Hello")
        XCTAssertEqual("Hello World\n".firstParagraph, "Hello World")
    }

    static var allTests = [
        ("testStringFirstParagraph", testStringFirstParagraph),
    ]
}
