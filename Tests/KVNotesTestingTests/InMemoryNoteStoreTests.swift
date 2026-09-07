import KVNotesCore
import KVNotesTesting
import XCTest

final class InMemoryNoteStoreTests: XCTestCase {
    func testCreateUpdatePatchRenameAndDiscard() async throws {
        let store = InMemoryNoteStore()
        var note = await store.create(NoteDraft(body: "first", title: "Title", folder: " Work "))
        let initialBody = try await store.body(note.id)
        XCTAssertEqual(note.folder, "Work")
        XCTAssertEqual(initialBody, "first")

        note = try await store.update(note.id, body: "second", title: "Renamed")
        XCTAssertEqual(note.characterCount, 6)
        XCTAssertEqual(note.snippet, "second")

        note = try await store.apply(
            NoteAttributePatch(requiresBiometricUnlock: true),
            to: note.id
        )
        XCTAssertNil(note.snippet)

        let renamedCount = await store.renameFolder("Work", to: "Archive")
        let renamedIndex = await store.index()
        XCTAssertEqual(renamedCount, 1)
        XCTAssertEqual(renamedIndex.folders, ["Archive"])

        try await store.discard(note.id)
        let emptyIndex = await store.index()
        XCTAssertTrue(emptyIndex.isEmpty)
    }

    func testMissingNoteThrows() async {
        let store = InMemoryNoteStore()
        let id = NoteID()

        do {
            _ = try await store.body(id)
            XCTFail("Expected missing note")
        } catch {
            XCTAssertEqual(error as? InMemoryNoteStoreError, .noteNotFound(id))
        }
    }

    func testDuplicateClonesBodyAndDigestWithNewIdentityAndUnpinned() async throws {
        let store = InMemoryNoteStore()
        let original = await store.create(NoteDraft(
            body: "Meeting notes",
            title: "Sync",
            folder: "Work",
            icon: "💼",
            requiresBiometricUnlock: false,
            hidesPreview: true
        ))
        _ = try await store.apply(NoteAttributePatch(isPinned: true), to: original.id)

        let clone = try await store.duplicate(original.id)

        XCTAssertNotEqual(clone.id, original.id)
        XCTAssertEqual(clone.title, "Sync")
        XCTAssertEqual(clone.folder, "Work")
        XCTAssertEqual(clone.icon, "💼")
        XCTAssertFalse(clone.isPinned, "Duplicate must never be pinned")
        XCTAssertTrue(clone.hidesPreview)
        let cloneBody = try await store.body(clone.id)
        XCTAssertEqual(cloneBody, "Meeting notes")

        let index = await store.index()
        XCTAssertEqual(index.notes.count, 2)
    }
}
