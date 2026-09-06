import XCTest
@testable import KVNotesCore

final class MarkdownListContinuationTests: XCTestCase {

    // MARK: - Unordered Bullets

    func testUnorderedBulletContinuation() {
        let text = "- Buy milk"
        let result = MarkdownListContinuation.evaluate(in: text, selection: text.count..<text.count)

        guard case .continueList(let payload) = result else {
            return XCTFail("Expected .continueList, got \(result)")
        }
        XCTAssertEqual(payload.text, "- Buy milk\n- ")
        XCTAssertEqual(payload.caretOffset, 13)
    }

    func testAsteriskAndPlusBulletContinuation() {
        let textAsterisk = "* First item"
        let resAsterisk = MarkdownListContinuation.continueOrExitList(
            in: textAsterisk,
            selection: textAsterisk.count..<textAsterisk.count
        )
        XCTAssertEqual(resAsterisk?.text, "* First item\n* ")

        let textPlus = "+ Another item"
        let resPlus = MarkdownListContinuation.continueOrExitList(
            in: textPlus,
            selection: textPlus.count..<textPlus.count
        )
        XCTAssertEqual(resPlus?.text, "+ Another item\n+ ")
    }

    func testExitUnorderedBulletOnEmptyLine() {
        let text = "- First\n- "
        let caret = text.count // at the end of the empty bullet
        let result = MarkdownListContinuation.evaluate(in: text, selection: caret..<caret)

        guard case .exitList(let payload) = result else {
            return XCTFail("Expected .exitList, got \(result)")
        }
        XCTAssertEqual(payload.text, "- First\n")
        XCTAssertEqual(payload.caretOffset, 8)
    }

    func testExitUnorderedBulletSoleLineInNote() {
        let text = "- "
        let result = MarkdownListContinuation.evaluate(in: text, selection: 2..<2)

        guard case .exitList(let payload) = result else {
            return XCTFail("Expected .exitList, got \(result)")
        }
        XCTAssertEqual(payload.text, "")
        XCTAssertEqual(payload.caretOffset, 0)
    }

    // MARK: - Checklists / Tasks

    func testChecklistContinuesAsUnchecked() {
        let text = "- [x] Finished task"
        let result = MarkdownListContinuation.evaluate(in: text, selection: text.count..<text.count)

        guard case .continueList(let payload) = result else {
            return XCTFail("Expected .continueList, got \(result)")
        }
        // Even though current was checked [x], the next line must be unchecked [ ]
        XCTAssertEqual(payload.text, "- [x] Finished task\n- [ ] ")
        XCTAssertEqual(payload.caretOffset, 26)
    }

    func testChecklistExitOnEmptyItem() {
        let text = "- [ ] Task 1\n- [ ] "
        let caret = text.count
        let result = MarkdownListContinuation.evaluate(in: text, selection: caret..<caret)

        guard case .exitList(let payload) = result else {
            return XCTFail("Expected .exitList, got \(result)")
        }
        XCTAssertEqual(payload.text, "- [ ] Task 1\n")
        XCTAssertEqual(payload.caretOffset, 13)
    }

    // MARK: - Numbered Lists

    func testNumberedListIncrements() {
        let text = "1. First step"
        let result = MarkdownListContinuation.evaluate(in: text, selection: text.count..<text.count)

        guard case .continueList(let payload) = result else {
            return XCTFail("Expected .continueList, got \(result)")
        }
        XCTAssertEqual(payload.text, "1. First step\n2. ")
        XCTAssertEqual(payload.caretOffset, 17)
    }

    func testNumberedList9To10() {
        let text = "9. Ninth step"
        let result = MarkdownListContinuation.continueOrExitList(in: text, selection: text.count..<text.count)
        XCTAssertEqual(result?.text, "9. Ninth step\n10. ")
        XCTAssertEqual(result?.caretOffset, 18)
    }

    func testNumberedListWithParenthesis() {
        let text = "1) First item"
        let result = MarkdownListContinuation.continueOrExitList(in: text, selection: text.count..<text.count)
        XCTAssertEqual(result?.text, "1) First item\n2) ")
    }

    func testNumberedListExitOnEmptyItem() {
        let text = "1. Step one\n2. "
        let caret = text.count
        let result = MarkdownListContinuation.evaluate(in: text, selection: caret..<caret)

        guard case .exitList(let payload) = result else {
            return XCTFail("Expected .exitList, got \(result)")
        }
        XCTAssertEqual(payload.text, "1. Step one\n")
        XCTAssertEqual(payload.caretOffset, 12)
    }

    // MARK: - Blockquotes

    func testBlockquoteContinuation() {
        let text = "> Quoted thought"
        let result = MarkdownListContinuation.continueOrExitList(in: text, selection: text.count..<text.count)
        XCTAssertEqual(result?.text, "> Quoted thought\n> ")
    }

    func testBlockquoteExitOnEmpty() {
        let text = "> Quoted\n> "
        let caret = text.count
        let result = MarkdownListContinuation.evaluate(in: text, selection: caret..<caret)

        guard case .exitList(let payload) = result else {
            return XCTFail("Expected .exitList, got \(result)")
        }
        XCTAssertEqual(payload.text, "> Quoted\n")
        XCTAssertEqual(payload.caretOffset, 9)
    }

    func testNestedBlockquoteOutdent() {
        let text = ">> "
        let result = MarkdownListContinuation.evaluate(in: text, selection: 3..<3)

        guard case .outdent(let payload) = result else {
            return XCTFail("Expected .outdent, got \(result)")
        }
        XCTAssertEqual(payload.text, "> ")
        XCTAssertEqual(payload.caretOffset, 2)
    }

    // MARK: - Indentation & Outdenting

    func testNestedIndentedBulletContinuation() {
        let text = "  - Nested item"
        let result = MarkdownListContinuation.continueOrExitList(in: text, selection: text.count..<text.count)
        XCTAssertEqual(result?.text, "  - Nested item\n  - ")
    }

    func testNestedIndentedChecklistContinuation() {
        let text = "    - [ ] Deep checklist"
        let result = MarkdownListContinuation.continueOrExitList(in: text, selection: text.count..<text.count)
        XCTAssertEqual(result?.text, "    - [ ] Deep checklist\n    - [ ] ")
    }

    func testIndentedBulletOutdentsStepByStep() {
        // 1. Double indented bullet empty line: outdents to single indent
        let text4Spaces = "    - "
        let res1 = MarkdownListContinuation.evaluate(in: text4Spaces, selection: 6..<6)
        guard case .outdent(let payload1) = res1 else {
            return XCTFail("Expected .outdent, got \(res1)")
        }
        XCTAssertEqual(payload1.text, "  - ")
        XCTAssertEqual(payload1.caretOffset, 4)

        // 2. Single indented bullet empty line: outdents to root level
        let text2Spaces = payload1.text
        let res2 = MarkdownListContinuation.evaluate(in: text2Spaces, selection: 4..<4)
        guard case .outdent(let payload2) = res2 else {
            return XCTFail("Expected .outdent, got \(res2)")
        }
        XCTAssertEqual(payload2.text, "- ")
        XCTAssertEqual(payload2.caretOffset, 2)

        // 3. Root level empty line: exits list
        let textRoot = payload2.text
        let res3 = MarkdownListContinuation.evaluate(in: textRoot, selection: 2..<2)
        guard case .exitList(let payload3) = res3 else {
            return XCTFail("Expected .exitList, got \(res3)")
        }
        XCTAssertEqual(payload3.text, "")
        XCTAssertEqual(payload3.caretOffset, 0)
    }

    // MARK: - Mid-line Enter

    func testMidLineEnterSplitsSentenceAndPrefixesTail() {
        let text = "- Alpha beta"
        // Cursor at "- Alpha |beta" (offset 8)
        let result = MarkdownListContinuation.continueOrExitList(in: text, selection: 8..<8)
        XCTAssertEqual(result?.text, "- Alpha\n- beta")
        XCTAssertEqual(result?.caretOffset, 10)
    }

    func testMidLineEnterChecklistSplitsToUnchecked() {
        let text = "- [x] Done and Pending"
        // Cursor at "- [x] Done |and Pending" (offset 11)
        let result = MarkdownListContinuation.continueOrExitList(in: text, selection: 11..<11)
        XCTAssertEqual(result?.text, "- [x] Done\n- [ ] and Pending")
        XCTAssertEqual(result?.caretOffset, 17)
    }

    func testMidLineEnterNumberedListIncrements() {
        let text = "1. Item one item two"
        // Cursor at "1. Item one |item two" (offset 12)
        let result = MarkdownListContinuation.continueOrExitList(in: text, selection: 12..<12)
        XCTAssertEqual(result?.text, "1. Item one\n2. item two")
        XCTAssertEqual(result?.caretOffset, 15)
    }

    // MARK: - Edge Cases & Rejections

    func testCaretAtStartOfLineDoesNotAutoContinue() {
        let text = "- Buy milk"
        // Cursor at index 0 before the bullet marker
        let result = MarkdownListContinuation.evaluate(in: text, selection: 0..<0)
        XCTAssertEqual(result, .none)
    }

    func testCaretInsidePrefixDoesNotAutoContinue() {
        let text = "- [ ] Milk"
        // Cursor inside the box: "- [|] Milk" (offset 3)
        let result = MarkdownListContinuation.evaluate(in: text, selection: 3..<3)
        XCTAssertEqual(result, .none)
    }

    func testNonListLineDoesNotAutoContinue() {
        let text = "Plain paragraph without list prefix"
        let result = MarkdownListContinuation.evaluate(in: text, selection: text.count..<text.count)
        XCTAssertEqual(result, .none)
    }

    func testThematicBreakDividerDoesNotAutoContinue() {
        let text = "---"
        let result = MarkdownListContinuation.evaluate(in: text, selection: text.count..<text.count)
        XCTAssertEqual(result, .none)
    }

    func testHeadingDoesNotAutoContinue() {
        let text = "### Heading 3"
        let result = MarkdownListContinuation.evaluate(in: text, selection: text.count..<text.count)
        XCTAssertEqual(result, .none)
    }

    func testInsideCodeFenceDoesNotAutoContinue() {
        let text = """
        ```swift
        - not a markdown list
        ```
        """
        // Caret on the line "- not a markdown list"
        let targetLine = "- not a markdown list"
        guard let range = text.range(of: targetLine) else {
            return XCTFail("Substring not found")
        }
        let caret = text.distance(from: text.startIndex, to: range.upperBound)
        let result = MarkdownListContinuation.evaluate(in: text, selection: caret..<caret)
        XCTAssertEqual(result, .none)
    }

    func testSelectionLengthGreaterThanZeroDoesNotAutoContinue() {
        let text = "- Buy milk today"
        // User has "milk" selected
        let result = MarkdownListContinuation.evaluate(in: text, selection: 6..<10)
        XCTAssertEqual(result, .none)
    }
}
