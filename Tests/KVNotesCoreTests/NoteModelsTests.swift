import Foundation
import KVNotesCore
import XCTest

final class NoteModelsTests: XCTestCase {
    func testIndexDerivesFoldersByCountThenName() {
        let notes = [
            NoteDigest(title: "One", snippet: nil, characterCount: 1, folder: "Work"),
            NoteDigest(title: "Two", snippet: nil, characterCount: 1, folder: "Personal"),
            NoteDigest(title: "Three", snippet: nil, characterCount: 1, folder: "Work")
        ]

        XCTAssertEqual(NoteIndex(notes: notes).folders, ["Work", "Personal"])
    }

    func testLockedDigestCanWithholdSnippetStructurally() {
        let digest = NoteDigest(
            title: "Recovery",
            snippet: nil,
            characterCount: 82,
            requiresBiometricUnlock: true
        )

        XCTAssertNil(digest.snippet)
    }

    func testNoteTemplatesProvideInitialMarkdownIconsAndCaretOffsets() {
        XCTAssertEqual(NoteTemplate.allCases.count, 5)

        for template in NoteTemplate.allCases {
            XCTAssertFalse(template.id.isEmpty)
            XCTAssertFalse(template.iconSymbol.isEmpty)
            XCTAssertGreaterThanOrEqual(template.initialCaretOffset, 0)
            XCTAssertLessThanOrEqual(template.initialCaretOffset, template.initialMarkdown.utf16.count)
        }

        XCTAssertTrue(NoteTemplate.blank.initialMarkdown.isEmpty)
        XCTAssertEqual(NoteTemplate.blank.initialCaretOffset, 0)
        XCTAssertNil(NoteTemplate.blank.defaultIcon)

        XCTAssertTrue(NoteTextDerivation.containsChecklist(NoteTemplate.checklist.initialMarkdown))
        XCTAssertEqual(NoteTemplate.checklist.defaultIcon, "🧾")

        XCTAssertTrue(NoteTemplate.seedPhrase.initialMarkdown.contains("1. "))
        XCTAssertEqual(NoteTemplate.seedPhrase.defaultIcon, "🔑")

        XCTAssertTrue(NoteTemplate.bankCard.initialMarkdown.contains("- **Bank**: "))
        XCTAssertEqual(NoteTemplate.bankCard.defaultIcon, "💳")

        XCTAssertTrue(NoteTemplate.credentials.initialMarkdown.contains("- **Service**: "))
        XCTAssertEqual(NoteTemplate.credentials.defaultIcon, "🔒")
    }
}
