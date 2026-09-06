import XCTest
@testable import KVNotesCore

final class NoteMarkdownBlockTests: XCTestCase {
    func testMarkerRangeIdentifiesVariousTaskPrefixes() {
        let task1 = "- [ ] milk"
        guard let range1 = NoteMarkdownBlock.markerRange(in: task1) else {
            return XCTFail("Expected marker range for task1")
        }
        XCTAssertEqual(String(task1[range1]), "- [ ] ")

        let task2 = "- [x] done"
        guard let range2 = NoteMarkdownBlock.markerRange(in: task2) else {
            return XCTFail("Expected marker range for task2")
        }
        XCTAssertEqual(String(task2[range2]), "- [x] ")

        let task3 = "  * [ ] indented"
        guard let range3 = NoteMarkdownBlock.markerRange(in: task3) else {
            return XCTFail("Expected marker range for task3")
        }
        XCTAssertEqual(String(task3[range3]), "  * [ ] ")

        let task4 = "+ [X] uppercase"
        guard let range4 = NoteMarkdownBlock.markerRange(in: task4) else {
            return XCTFail("Expected marker range for task4")
        }
        XCTAssertEqual(String(task4[range4]), "+ [X] ")

        XCTAssertNil(NoteMarkdownBlock.markerRange(in: "Just prose text"))
        XCTAssertNil(NoteMarkdownBlock.markerRange(in: "- Regular bullet"))
        XCTAssertNil(NoteMarkdownBlock.markerRange(in: "1. Numbered item"))
    }

    func testTaskLineIndexMatchesWithinMarkerAndIgnoresBody() {
        let text = """
        # Shopping
        - [ ] Milk
          - [x] Bread
        Don't forget butter
        """

        // Line 0: "# Shopping\n" (0..<11)
        XCTAssertNil(NoteMarkdownBlock.taskLineIndex(at: 0, in: text))
        XCTAssertNil(NoteMarkdownBlock.taskLineIndex(at: 5, in: text))

        // Line 1: "- [ ] Milk\n" (11..<22)
        // Marker "- [ ] " is offsets 11..<17
        XCTAssertEqual(NoteMarkdownBlock.taskLineIndex(at: 11, in: text), 1) // '-'
        XCTAssertEqual(NoteMarkdownBlock.taskLineIndex(at: 13, in: text), 1) // '['
        XCTAssertEqual(NoteMarkdownBlock.taskLineIndex(at: 14, in: text), 1) // ' '
        XCTAssertEqual(NoteMarkdownBlock.taskLineIndex(at: 15, in: text), 1) // ']'
        XCTAssertEqual(NoteMarkdownBlock.taskLineIndex(at: 16, in: text), 1) // trailing ' '

        // Tapping on "Milk" (offset 17+) should NOT register as a checkbox tap
        XCTAssertNil(NoteMarkdownBlock.taskLineIndex(at: 17, in: text)) // 'M'
        XCTAssertNil(NoteMarkdownBlock.taskLineIndex(at: 18, in: text)) // 'i'

        // Line 2: "  - [x] Bread\n" (22..<36)
        // Marker "  - [x] " is offsets 22..<30
        XCTAssertEqual(NoteMarkdownBlock.taskLineIndex(at: 22, in: text), 2) // leading space
        XCTAssertEqual(NoteMarkdownBlock.taskLineIndex(at: 24, in: text), 2) // '-'
        XCTAssertEqual(NoteMarkdownBlock.taskLineIndex(at: 27, in: text), 2) // 'x'
        XCTAssertEqual(NoteMarkdownBlock.taskLineIndex(at: 29, in: text), 2) // trailing space
        XCTAssertNil(NoteMarkdownBlock.taskLineIndex(at: 30, in: text)) // 'B'

        // Line 3: "Don't forget butter" (36..<55)
        XCTAssertNil(NoteMarkdownBlock.taskLineIndex(at: 36, in: text))

        // Out of bounds
        XCTAssertNil(NoteMarkdownBlock.taskLineIndex(at: -1, in: text))
        XCTAssertNil(NoteMarkdownBlock.taskLineIndex(at: 999, in: text))
    }

    func testLineNSRangeReturnsAccurateRanges() {
        let text = "Line 1\nLine 2\nLine 3"
        let r0 = NoteMarkdownBlock.lineNSRange(at: 0, in: text)
        XCTAssertEqual(r0, NSRange(location: 0, length: 6))

        let r1 = NoteMarkdownBlock.lineNSRange(at: 1, in: text)
        XCTAssertEqual(r1, NSRange(location: 7, length: 6))

        let r2 = NoteMarkdownBlock.lineNSRange(at: 2, in: text)
        XCTAssertEqual(r2, NSRange(location: 14, length: 6))

        XCTAssertNil(NoteMarkdownBlock.lineNSRange(at: 3, in: text))
    }

    func testTogglingTaskFlipsCheckboxState() {
        let text = "- [ ] first\n- [x] second"
        let toggled0 = NoteMarkdownBlock.togglingTask(atLine: 0, in: text)
        XCTAssertEqual(toggled0, "- [x] first\n- [x] second")

        let toggled1 = NoteMarkdownBlock.togglingTask(atLine: 1, in: text)
        XCTAssertEqual(toggled1, "- [ ] first\n- [ ] second")
    }
}
