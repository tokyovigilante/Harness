import XCTest
@testable import Harness


final class StringTests: XCTestCase {

    func testStringParagraphsEmptyLine () {
        XCTAssertEqual("".paragraphs, [])
    }

    func testStringParagraphsUnixBreak () {
        XCTAssertEqual("Hello\nWorld".paragraphs, ["Hello", "World"])
    }

    func testStringParagraphsWindowsBreak () {
        XCTAssertEqual("Hello\r\nWorld".paragraphs, ["Hello", "World"])
    }

    func testStringParagraphsBlankLine () {
        XCTAssertEqual("Hello\n\nWorld".paragraphs, ["Hello", "", "World"])
    }

    func testStringParagraphsWTFBreak () {
        XCTAssertEqual("Hello\rWorld".paragraphs, ["Hello", "World"])
    }

    func testStringParagraphsBreakAtEnd () {
        XCTAssertEqual("Hello World\n".paragraphs, ["Hello World"])
    }

    func testStringFirstParagraph () {
        XCTAssertEqual("".firstParagraph, "")
        XCTAssertEqual("Hello\nWorld".firstParagraph, "Hello")
        XCTAssertEqual("Hello\r\nWorld".firstParagraph, "Hello")
        XCTAssertEqual("Hello\rWorld".firstParagraph, "Hello")
        XCTAssertEqual("Hello World\n".firstParagraph, "Hello World")
    }

    func testLineBreakingAlgorithm () {
        XCTAssertEqual("Hello World".lines(width: 12), ["Hello World"])
        XCTAssertEqual("Hello World".lines(width: 6), ["Hello", "World"])
        XCTAssertEqual("Hello\nWorld".lines(width: 12), ["Hello", "World"])
    }

    static var allTests = [
        ("testStringParagraphsEmptyLine", testStringParagraphsEmptyLine),
        ("testStringParagraphsUnixBreak", testStringParagraphsUnixBreak),
        ("testStringParagraphsWindowsBreak", testStringParagraphsWindowsBreak),
        ("testStringParagraphsBlankLine", testStringParagraphsBlankLine),
        ("testStringParagraphsWTFBreak", testStringParagraphsWTFBreak),
        ("testStringParagraphsBreakAtEnd", testStringParagraphsBreakAtEnd),
        ("testStringFirstParagraph", testStringFirstParagraph),
        ("testLineBreakingAlgorithm", testLineBreakingAlgorithm),
    ]
}
