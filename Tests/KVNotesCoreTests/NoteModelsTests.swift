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
}
