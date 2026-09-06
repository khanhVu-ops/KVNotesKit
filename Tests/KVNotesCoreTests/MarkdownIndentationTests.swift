import XCTest
@testable import KVNotesCore

final class MarkdownIndentationTests: XCTestCase {

    func testIndentSingleLine() {
        let text = "- Item"
        let res = MarkdownIndentation.indent(in: text, selection: 2..<2)
        XCTAssertEqual(res.text, "  - Item")
        XCTAssertEqual(res.selectedRange, 4..<4)
    }

    func testOutdentSingleLineWith2Spaces() {
        let text = "  - Item"
        let res = MarkdownIndentation.outdent(in: text, selection: 4..<4)
        XCTAssertEqual(res.text, "- Item")
        XCTAssertEqual(res.selectedRange, 2..<2)
    }

    func testOutdentSingleLineWithTab() {
        let text = "\t- Item"
        let res = MarkdownIndentation.outdent(in: text, selection: 3..<3)
        XCTAssertEqual(res.text, "- Item")
        XCTAssertEqual(res.selectedRange, 2..<2)
    }

    func testOutdentUnindentedLineDoesNothing() {
        let text = "- Item"
        let res = MarkdownIndentation.outdent(in: text, selection: 2..<2)
        XCTAssertEqual(res.text, "- Item")
        XCTAssertEqual(res.selectedRange, 2..<2)
    }

    func testIndentMultiLineSelection() {
        let text = """
        - Item 1
        - Item 2
        - Item 3
        """
        // Select from inside Item 1 to inside Item 2
        let range = 2..<15
        let res = MarkdownIndentation.indent(in: text, selection: range)
        XCTAssertEqual(res.text, """
          - Item 1
          - Item 2
        - Item 3
        """)
        XCTAssertEqual(res.selectedRange.lowerBound, 4)
        XCTAssertEqual(res.selectedRange.upperBound, 19)
    }

    func testOutdentMultiLineSelection() {
        let text = """
          - Item 1
          - Item 2
        - Item 3
        """
        let range = 4..<19
        let res = MarkdownIndentation.outdent(in: text, selection: range)
        XCTAssertEqual(res.text, """
        - Item 1
        - Item 2
        - Item 3
        """)
        XCTAssertEqual(res.selectedRange.lowerBound, 2)
        XCTAssertEqual(res.selectedRange.upperBound, 15)
    }
}
