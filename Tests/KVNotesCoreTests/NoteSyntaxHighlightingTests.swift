import XCTest
@testable import KVNotesCore

final class NoteSyntaxHighlightingTests: XCTestCase {
    func testHeadingsQuotesAndBulletsStyleTheirLineAndDimTheirMarker() {
        let text = "# Wallet\n> quoted\n- item" as NSString

        let spans = NoteSyntaxHighlighting.spans(in: text, range: NSRange(location: 0, length: text.length))

        XCTAssertTrue(spans.contains(NoteStyleSpan(kind: .syntax, range: NSRange(location: 0, length: 2))))
        XCTAssertTrue(spans.contains(NoteStyleSpan(kind: .heading(level: 1), range: NSRange(location: 2, length: 6))))
        XCTAssertTrue(spans.contains(NoteStyleSpan(kind: .quote, range: NSRange(location: 11, length: 6))))
        XCTAssertTrue(spans.contains(NoteStyleSpan(kind: .syntax, range: NSRange(location: 18, length: 2))))
    }

    func testBoldWinsOverItalicAndEmphasisCarriesItsContentOnly() {
        let text = "a **b** c *d* e" as NSString

        let spans = NoteSyntaxHighlighting.spans(in: text, range: NSRange(location: 0, length: text.length))

        XCTAssertTrue(spans.contains(NoteStyleSpan(kind: .bold, range: NSRange(location: 4, length: 1))))
        XCTAssertTrue(spans.contains(NoteStyleSpan(kind: .italic, range: NSRange(location: 11, length: 1))))
        // `**` must be tried before `*`, or the bold run reads as two empty italics.
        XCTAssertFalse(spans.contains { $0.kind == .italic && $0.range.location < 8 })
    }

    func testUnclosedAndEmptyMarkersAreLeftAsTypedCharacters() {
        let unclosed = "a **b" as NSString
        XCTAssertTrue(NoteSyntaxHighlighting.spans(in: unclosed, range: NSRange(location: 0, length: unclosed.length)).isEmpty)

        let empty = "****" as NSString
        XCTAssertTrue(NoteSyntaxHighlighting.spans(in: empty, range: NSRange(location: 0, length: empty.length)).isEmpty)
    }

    func testInlineCodeAndStrikethroughAreFound() {
        let text = "`8492` and ~~gone~~" as NSString

        let spans = NoteSyntaxHighlighting.spans(in: text, range: NSRange(location: 0, length: text.length))

        XCTAssertTrue(spans.contains(NoteStyleSpan(kind: .inlineCode, range: NSRange(location: 1, length: 4))))
        XCTAssertTrue(spans.contains(NoteStyleSpan(kind: .strikethrough, range: NSRange(location: 13, length: 4))))
    }

    func testTaskMarkersReportTheirState() {
        let text = "- [ ] milk\n- [x] bread" as NSString

        let spans = NoteSyntaxHighlighting.spans(in: text, range: NSRange(location: 0, length: text.length))

        XCTAssertTrue(spans.contains { $0.kind == .taskMarker(isDone: false) })
        XCTAssertTrue(spans.contains { $0.kind == .taskMarker(isDone: true) })
    }

    /// Styling a range must not depend on what is outside it: the editor never asks for the
    /// document, so a span that needed the whole note to be correct would be wrong on screen.
    func testAskingForOneLineReturnsOnlyThatLinesSpans() {
        let text = "# one\n**two**\n# three" as NSString
        let secondLine = text.lineRange(for: NSRange(location: 7, length: 0))

        let spans = NoteSyntaxHighlighting.spans(in: text, range: secondLine)

        XCTAssertTrue(spans.allSatisfy { NSIntersectionRange($0.range, secondLine).length > 0 })
        XCTAssertTrue(spans.contains { $0.kind == .bold })
        XCTAssertFalse(spans.contains { $0.kind == .heading(level: 1) })
    }
}
