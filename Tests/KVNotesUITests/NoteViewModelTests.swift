import Foundation
import KVNotesCore
import KVNotesTesting
import XCTest
@testable import KVNotesUI

@MainActor
final class NoteViewModelTests: XCTestCase {
    func testListLoadsFiltersSearchesAndMutatesThroughStore() async throws {
        let store = InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies)
        let viewModel = NotesListViewModel(store: store)

        viewModel.send(.onAppear)
        try await settle { viewModel.state.phase == .loaded }
        XCTAssertEqual(viewModel.state.visibleNotes.count, 3)
        XCTAssertEqual(viewModel.state.folderChips.map(\.name), ["Banking", "Passwords"])

        viewModel.send(.selectFolder("Banking"))
        XCTAssertEqual(viewModel.state.visibleNotes.map(\.title), ["Bank details"])
        viewModel.send(.selectFolder(nil))
        viewModel.send(.updateSearchQuery("friday"))
        XCTAssertEqual(viewModel.state.visibleNotes.map(\.title), ["Friday journal"])

        viewModel.send(.updateSearchQuery(""))
        viewModel.send(.toggleFavorite(NoteFixtures.bank.id))
        try await settle { !viewModel.state.isBusy }
        let favoriteIndex = await store.index()
        XCTAssertTrue(favoriteIndex.notes.first(where: { $0.id == NoteFixtures.bank.id })?.isFavorite == true)

        viewModel.send(.requestDiscard(NoteFixtures.journal))
        viewModel.send(.confirmDiscard)
        try await settle { !viewModel.state.isBusy }
        let discardedIndex = await store.index()
        XCTAssertFalse(discardedIndex.notes.contains(where: { $0.id == NoteFixtures.journal.id }))
    }

    func testEditorCreatesSavesAndAppliesMarkdownInsertion() async throws {
        let store = InMemoryNoteStore()
        let viewModel = NoteEditorViewModel(store: store, unlockAuthority: UnlockAuthority())

        XCTAssertEqual(viewModel.state.mode, .edit)
        viewModel.send(.setBody("never share"))
        viewModel.send(.insert(.bold, 0..<5))
        XCTAssertEqual(viewModel.state.body, "**never** share")
        XCTAssertEqual(viewModel.state.pendingCaretOffset, 9)

        viewModel.send(.setTitle("Wallet"))
        viewModel.send(.save)
        try await settle { viewModel.state.note != nil && !viewModel.state.isDirty }
        let id = try XCTUnwrap(viewModel.state.note?.id)
        let body = try await store.body(id)
        XCTAssertEqual(body, "**never** share")
    }

    func testLockedEditorDoesNotReadBodyUntilAuthenticationCompletes() async throws {
        let locked = NoteDigest(
            title: "Wallet",
            snippet: nil,
            characterCount: 10,
            requiresBiometricUnlock: true,
            isTitleUserProvided: true
        )
        let store = InMemoryNoteStore(notes: [locked], bodies: [locked.id: "seed words"])
        let viewModel = NoteEditorViewModel(note: locked, store: store, unlockAuthority: UnlockAuthority())

        viewModel.send(.onAppear)
        await Task.yield()
        XCTAssertTrue(viewModel.state.isLocked)
        XCTAssertTrue(viewModel.state.body.isEmpty)

        viewModel.send(.pinAuthenticated)
        try await settle { !viewModel.state.isLoading }
        XCTAssertFalse(viewModel.state.isLocked)
        XCTAssertEqual(viewModel.state.body, "seed words")
    }

    func testSessionLockClearsPlaintext() {
        let viewModel = NoteEditorViewModel(store: InMemoryNoteStore(), unlockAuthority: UnlockAuthority())
        viewModel.send(.setTitle("Wallet"))
        viewModel.send(.setBody("seed words"))

        viewModel.send(.sessionLocked)

        XCTAssertTrue(viewModel.state.title.isEmpty)
        XCTAssertTrue(viewModel.state.body.isEmpty)
        XCTAssertEqual(viewModel.state.saveStatus, .idle)
    }

    private func settle(
        until condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for state", file: file, line: line)
    }
}

@MainActor
private struct UnlockAuthority: NoteUnlockAuthority {
    let offer = NoteUnlockOffer(biometric: .faceID)
    func authenticate(reason: LocalizedStringResource) async throws -> Bool { true }
}
