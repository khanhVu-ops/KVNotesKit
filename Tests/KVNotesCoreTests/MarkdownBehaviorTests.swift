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

    func testChecklistDetectionAcceptsEveryMarkerAndRejectsLookalikes() {
        XCTAssertTrue(NoteTextDerivation.containsChecklist("Groceries\n- [ ] milk"))
        XCTAssertTrue(NoteTextDerivation.containsChecklist("* [x] done"))
        XCTAssertTrue(NoteTextDerivation.containsChecklist("  + [X] indented"))

        XCTAssertFalse(NoteTextDerivation.containsChecklist("- [draft] not a box"))
        XCTAssertFalse(NoteTextDerivation.containsChecklist("- [x]no space after the box"))
        XCTAssertFalse(NoteTextDerivation.containsChecklist("a sentence mentioning - [ ] mid-line"))
        XCTAssertFalse(NoteTextDerivation.containsChecklist(""))
    }

    func testSummaryCarriesTheChecklistFlagAndLockingIsNotItsJob() {
        XCTAssertTrue(
            NoteTextDerivation.summary(
                markdown: "Trip\n- [ ] passport",
                title: nil,
                requiresBiometricUnlock: true
            ).hasChecklist
        )
    }

    func testTaskBlocksCarryTheirSourceLine() {
        let markdown = "Packing\n- [ ] charger\ntext\n- [x] socks"
        let blocks = NoteMarkdownBlock.blocks(of: markdown)

        XCTAssertEqual(blocks.count, 4)
        guard case .task(let first) = blocks[1], case .task(let second) = blocks[3] else {
            return XCTFail("Expected two task blocks, got \(blocks)")
        }
        XCTAssertEqual(first, NoteMarkdownBlock.Task(isDone: false, text: "charger", lineIndex: 1))
        XCTAssertEqual(second, NoteMarkdownBlock.Task(isDone: true, text: "socks", lineIndex: 3))
    }

    func testTogglingATaskRewritesOnlyThatBox() {
        let markdown = "- [ ] repeat\n- [ ] repeat"

        let first = NoteMarkdownBlock.togglingTask(atLine: 0, in: markdown)
        XCTAssertEqual(first, "- [x] repeat\n- [ ] repeat")
        XCTAssertEqual(NoteMarkdownBlock.togglingTask(atLine: 1, in: first), "- [x] repeat\n- [x] repeat")
        // Ticking twice is unticking, and indentation and marker survive both directions.
        XCTAssertEqual(
            NoteMarkdownBlock.togglingTask(atLine: 0, in: "  + [X] socks"),
            "  + [ ] socks"
        )
    }

    /// The body can have been edited between the render and the tap; rewriting a line that is now
    /// prose would corrupt the note silently.
    func testTogglingANonTaskLineChangesNothing() {
        XCTAssertEqual(NoteMarkdownBlock.togglingTask(atLine: 0, in: "just text"), "just text")
        XCTAssertEqual(NoteMarkdownBlock.togglingTask(atLine: 9, in: "- [ ] one"), "- [ ] one")
        XCTAssertEqual(NoteMarkdownBlock.togglingTask(atLine: 0, in: "- [draft] no"), "- [draft] no")
    }
}
