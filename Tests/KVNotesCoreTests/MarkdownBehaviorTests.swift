import XCTest
@testable import KVNotesCore

final class MarkdownBehaviorTests: XCTestCase {
    func testParserRecognizesSupportedBlocksAndPreservesUnknownSyntax() {
        XCTAssertEqual(NoteMarkdownBlock.blocks(of: """
        # Wallet

        - Recovery phrase
        `8492`
        ---
        > keep this text
        """), [
            .heading(level: 1, text: "Wallet"),
            .bullet("Recovery phrase"),
            .code("8492"),
            .divider,
            .paragraph("> keep this text")
        ])
    }

    func testParserKeepsUnclosedFenceInsteadOfDroppingSecretText() {
        XCTAssertEqual(
            NoteMarkdownBlock.blocks(of: "```\nseed words"),
            [.code("seed words")]
        )
    }

    func testInsertionWrapsUnicodeSelectionAndTogglesMarkers() {
        let once = MarkdownInsertion.apply(.bold, to: "🔑 seed 🔑", selection: 2..<6)
        XCTAssertEqual(once.text, "🔑 **seed** 🔑")

        let twice = MarkdownInsertion.apply(.bold, to: "seed", selection: 0..<4)
        XCTAssertEqual(
            MarkdownInsertion.apply(.bold, to: twice.text, selection: 0..<twice.text.count).text,
            "seed"
        )
    }

    func testInsertionHandlesEveryTokenAndClampsOffsets() {
        for token in MarkdownToken.allCases {
            let result = MarkdownInsertion.apply(token, to: "seed words", selection: 99..<120)
            XCTAssertTrue(result.text.contains("seed"), "\(token) lost the input")
            XCTAssertGreaterThanOrEqual(result.caretOffset, 0)
        }
    }

    func testDerivationBoundsTitleAndSnippet() {
        let markdown = "# " + String(repeating: "A", count: 90) + "\n\n" + String(repeating: "B", count: 180)
        XCTAssertLessThanOrEqual(NoteTextDerivation.derivedTitle(from: markdown).count, NoteTextDerivation.titleLimit)
        XCTAssertLessThanOrEqual(NoteTextDerivation.snippet(from: markdown).count, NoteTextDerivation.snippetLimit)
    }
}
