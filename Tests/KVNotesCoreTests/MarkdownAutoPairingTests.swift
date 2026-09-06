import XCTest
@testable import KVNotesCore

final class MarkdownAutoPairingTests: XCTestCase {

    // MARK: - Caret Auto-Pairing

    func testAutoPairsBracketsAtCaret() {
        let text = "Hello "
        let resParen = MarkdownAutoPairing.handleTyping("(", in: text, selection: 6..<6)
        XCTAssertEqual(resParen?.text, "Hello ()")
        XCTAssertEqual(resParen?.caretOffset, 7) // Inside '(' and ')'

        let resBracket = MarkdownAutoPairing.handleTyping("[", in: text, selection: 6..<6)
        XCTAssertEqual(resBracket?.text, "Hello []")
        XCTAssertEqual(resBracket?.caretOffset, 7)

        let resBrace = MarkdownAutoPairing.handleTyping("{", in: text, selection: 6..<6)
        XCTAssertEqual(resBrace?.text, "Hello {}")
        XCTAssertEqual(resBrace?.caretOffset, 7)
    }

    func testAutoPairsQuotesAndBackticksAtEndOfLineOrBeforeWhitespace() {
        let text = "Hello "
        let resQuote = MarkdownAutoPairing.handleTyping("\"", in: text, selection: 6..<6)
        XCTAssertEqual(resQuote?.text, "Hello \"\"")
        XCTAssertEqual(resQuote?.caretOffset, 7)

        let resTick = MarkdownAutoPairing.handleTyping("`", in: text, selection: 6..<6)
        XCTAssertEqual(resTick?.text, "Hello ``")
        XCTAssertEqual(resTick?.caretOffset, 7)
    }

    func testDoesNotAutoPairQuoteDirectlyBeforeWord() {
        let text = "Hello world"
        // Caret before 'w'
        let res = MarkdownAutoPairing.handleTyping("\"", in: text, selection: 6..<6)
        XCTAssertNil(res, "Should not auto-pair quote before alphanumeric word")
    }

    // MARK: - Skip-Over Closing Character

    func testSkipsOverClosingBracketWhenAlreadyPresent() {
        let text = "Hello ()"
        // Caret between '(' and ')' (offset 7)
        let resParen = MarkdownAutoPairing.handleTyping(")", in: text, selection: 7..<7)
        XCTAssertEqual(resParen?.text, "Hello ()") // Unchanged text
        XCTAssertEqual(resParen?.caretOffset, 8)   // Stepped over ')'

        let textSquare = "Hello []"
        let resSquare = MarkdownAutoPairing.handleTyping("]", in: textSquare, selection: 7..<7)
        XCTAssertEqual(resSquare?.text, "Hello []")
        XCTAssertEqual(resSquare?.caretOffset, 8)

        let textQuote = "Hello \"\""
        let resQuote = MarkdownAutoPairing.handleTyping("\"", in: textQuote, selection: 7..<7)
        XCTAssertEqual(resQuote?.text, "Hello \"\"")
        XCTAssertEqual(resQuote?.caretOffset, 8)
    }

    // MARK: - Smart Wrapping with Selection

    func testSmartWrapsSelection() {
        let text = "format this word now"
        // Select "this" (7..<11)
        let resBold = MarkdownAutoPairing.handleTyping("*", in: text, selection: 7..<11)
        XCTAssertEqual(resBold?.text, "format *this* word now")
        XCTAssertEqual(resBold?.caretOffset, 13) // After closing '*'

        let resLink = MarkdownAutoPairing.handleTyping("[", in: text, selection: 7..<11)
        XCTAssertEqual(resLink?.text, "format [this] word now")
        XCTAssertEqual(resLink?.caretOffset, 13)

        let resQuote = MarkdownAutoPairing.handleTyping("\"", in: text, selection: 7..<11)
        XCTAssertEqual(resQuote?.text, "format \"this\" word now")

        let resCode = MarkdownAutoPairing.handleTyping("`", in: text, selection: 7..<11)
        XCTAssertEqual(resCode?.text, "format `this` word now")

        let resStrike = MarkdownAutoPairing.handleTyping("~", in: text, selection: 7..<11)
        XCTAssertEqual(resStrike?.text, "format ~this~ word now")
    }

    // MARK: - Backspace Pair Deletion

    func testBackspaceDeletesEmptyPair() {
        let textParen = "Hello ()"
        // Caret at offset 7 between '(' and ')'
        let resParen = MarkdownAutoPairing.handleBackspace(in: textParen, selection: 7..<7)
        XCTAssertEqual(resParen?.text, "Hello ")
        XCTAssertEqual(resParen?.caretOffset, 6)

        let textBracket = "Hello []"
        let resBracket = MarkdownAutoPairing.handleBackspace(in: textBracket, selection: 7..<7)
        XCTAssertEqual(resBracket?.text, "Hello ")
        XCTAssertEqual(resBracket?.caretOffset, 6)

        let textQuote = "Hello \"\""
        let resQuote = MarkdownAutoPairing.handleBackspace(in: textQuote, selection: 7..<7)
        XCTAssertEqual(resQuote?.text, "Hello ")
        XCTAssertEqual(resQuote?.caretOffset, 6)
    }

    func testBackspaceOnNonPairReturnsNil() {
        let text = "Hello (world)"
        // Caret at offset 7 after '(' before 'w'
        let res = MarkdownAutoPairing.handleBackspace(in: text, selection: 7..<7)
        XCTAssertNil(res)
    }
}
