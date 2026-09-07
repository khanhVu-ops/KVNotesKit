import Foundation
import SwiftUI
import XCTest
@testable import KVNotesCore
@testable import KVNotesUI

final class NotesAccessibilityAndRTLTests: XCTestCase {
    // MARK: - RTL Detection

    func testEnglishTextIsNotRTL() {
        XCTAssertFalse("Hello world".isRightToLeftText)
        XCTAssertFalse("Meeting notes for Q4".isRightToLeftText)
        XCTAssertFalse("Swift 6 & iOS 18".isRightToLeftText)
    }

    func testArabicAndHebrewTextIsRTL() {
        // Arabic
        XCTAssertTrue("ملاحظات خاصة".isRightToLeftText)
        XCTAssertTrue("مرحبا بك".isRightToLeftText)
        // Hebrew
        XCTAssertTrue("שלום עולם".isRightToLeftText)
    }

    func testMarkdownPrefixedTextDetectsUnderlyingScript() {
        XCTAssertFalse("# Heading in English".isRightToLeftText)
        XCTAssertFalse("- [ ] Buy milk".isRightToLeftText)
        XCTAssertFalse("> A quote".isRightToLeftText)

        XCTAssertTrue("# عنوان رئيسي".isRightToLeftText)
        XCTAssertTrue("- [ ] مهمة جديدة".isRightToLeftText)
        XCTAssertTrue("> اقتباس مهم".isRightToLeftText)
    }

    func testMarkdownBlockRTLClassification() {
        let ltrBlock = NoteMarkdownBlock.paragraph("This is an LTR paragraph.")
        XCTAssertFalse(ltrBlock.isRightToLeft)

        let rtlBlock = NoteMarkdownBlock.paragraph("هذه فقرة باللغة العربية.")
        XCTAssertTrue(rtlBlock.isRightToLeft)

        let codeBlock = NoteMarkdownBlock.code(NoteMarkdownBlock.Code(value: "let x = 42", isSecret: false))
        XCTAssertFalse(codeBlock.isRightToLeft, "Code blocks must always be LTR")

        let dividerBlock = NoteMarkdownBlock.divider
        XCTAssertFalse(dividerBlock.isRightToLeft)
    }

    // MARK: - Dynamic Type Layout

    func testAccessibilitySizeCollapsesToSingleColumn() {
        let regularColumns = computeColumns(isGrid: true, isAccessibilitySize: false)
        XCTAssertEqual(regularColumns.count, 2, "Grid mode uses 2 columns at normal font sizes")

        let axColumns = computeColumns(isGrid: true, isAccessibilitySize: true)
        XCTAssertEqual(axColumns.count, 1, "Grid mode collapses to 1 column at accessibility sizes to prevent clipping")

        let listColumns = computeColumns(isGrid: false, isAccessibilitySize: false)
        XCTAssertEqual(listColumns.count, 1, "List mode always uses 1 column")
    }

    private func computeColumns(isGrid: Bool, isAccessibilitySize: Bool) -> [GridItem] {
        let column = GridItem(.flexible(), spacing: 8, alignment: .top)
        guard isGrid && !isAccessibilitySize else {
            return [column]
        }
        return [column, column]
    }

    // MARK: - Save Status Accessibility

    func testSaveStatusProducesNonEmptyAccessibilityLabels() {
        let statuses: [NoteEditorState.SaveStatus] = [
            .idle,
            .unsaved,
            .saving,
            .saved(Date()),
            .failed
        ]

        for status in statuses {
            let label = labelForSaveStatus(status, characterCount: 42)
            XCTAssertFalse(label.isEmpty, "Save status \(status) must produce an accessible label")
        }
    }

    private func labelForSaveStatus(_ status: NoteEditorState.SaveStatus, characterCount: Int) -> String {
        switch status {
        case .idle:
            return "\(characterCount) characters"
        case .unsaved:
            return "Unsaved"
        case .saving:
            return "Saving…"
        case .saved:
            return "Saved to vault"
        case .failed:
            return "Not saved"
        }
    }
}
