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
        viewModel.send(.togglePin(NoteFixtures.bank.id))
        try await settle { !viewModel.state.isBusy }
        let pinnedIndex = await store.index()
        XCTAssertTrue(pinnedIndex.notes.first(where: { $0.id == NoteFixtures.bank.id })?.isPinned == true)
        // Both fixtures that are now pinned lead the list, and the rest keep their edit order.
        XCTAssertEqual(viewModel.state.pinnedCount, 2)
        XCTAssertTrue(viewModel.state.pinnedNotes.allSatisfy(\.isPinned))
        XCTAssertTrue(viewModel.state.timelineNotes.allSatisfy { !$0.isPinned })

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

    func testEditorQueuesTheLatestBufferWhileASaveIsInFlight() async throws {
        let store = DelayedNoteStore(delay: .milliseconds(60))
        let viewModel = NoteEditorViewModel(store: store, unlockAuthority: UnlockAuthority())

        viewModel.send(.setBody("first version"))
        viewModel.send(.save)
        try await settle { viewModel.state.saveStatus == .saving }

        viewModel.send(.setBody("latest version"))
        viewModel.send(.save)

        try await settle {
            guard case .saved = viewModel.state.saveStatus else { return false }
            return viewModel.state.note != nil
        }
        let id = try XCTUnwrap(viewModel.state.note?.id)
        let storedBody = try await store.body(id)
        let writeCount = await store.writeCount()
        XCTAssertEqual(storedBody, "latest version")
        XCTAssertEqual(writeCount, 2)
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

    func testSortAndFilterNarrowTheListWithoutLosingThePinnedSection() async throws {
        let store = InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies)
        let viewModel = NotesListViewModel(store: store)

        viewModel.send(.onAppear)
        try await settle { viewModel.state.phase == .loaded }
        XCTAssertFalse(viewModel.state.isNarrowed)

        viewModel.send(.setSortOrder(.title))
        // Pinned notes keep the head of the list; the sort orders within each group.
        XCTAssertEqual(viewModel.state.pinnedNotes.map(\.title), ["Hardware wallet"])
        XCTAssertEqual(viewModel.state.timelineNotes.map(\.title), ["Bank details", "Friday journal"])
        XCTAssertTrue(viewModel.state.isNarrowed)

        viewModel.send(.setSortOrder(.lastEditedOldest))
        XCTAssertEqual(viewModel.state.timelineNotes.map(\.title), ["Friday journal", "Bank details"])

        viewModel.send(.setFilter(.locked))
        XCTAssertEqual(viewModel.state.visibleNotes.map(\.title), ["Hardware wallet"])

        // No fixture carries a checklist, so this is the empty-because-of-filter state rather
        // than an empty vault — the two show different screens.
        viewModel.send(.setFilter(.hasChecklist))
        XCTAssertTrue(viewModel.state.visibleNotes.isEmpty)
        XCTAssertTrue(viewModel.state.isEmptyBecauseOfFilter)
        XCTAssertFalse(viewModel.state.isEmptyBecauseStoreIsEmpty)

        viewModel.send(.setFilter(.all))
        viewModel.send(.setSortOrder(.lastEditedNewest))
        XCTAssertFalse(viewModel.state.isNarrowed)
        XCTAssertEqual(viewModel.state.visibleNotes.count, 3)
    }

    func testTheListRemembersHowItWasLastShown() async throws {
        let store = InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies)
        let preferences = InMemoryNoteListPreferences()
        let first = NotesListViewModel(store: store, preferences: preferences)

        first.send(.onAppear)
        try await settle { first.state.phase == .loaded }
        first.send(.setSortOrder(.title))
        first.send(.setFilter(.locked))

        // A second screen, as if the user had left the flow and come back.
        let second = NotesListViewModel(store: store, preferences: preferences)
        XCTAssertEqual(second.state.sortOrder, .title)
        XCTAssertEqual(second.state.filter, .locked)
        second.send(.onAppear)
        try await settle { second.state.phase == .loaded }
        XCTAssertEqual(second.state.visibleNotes.map(\.title), ["Hardware wallet"])

        // And a screen with nowhere to read from opens on the defaults rather than crashing.
        let third = NotesListViewModel(store: store)
        XCTAssertEqual(third.state.sortOrder, .lastEditedNewest)
        XCTAssertEqual(third.state.filter, .all)
    }

    func testTickingATaskWritesThroughTheOrdinarySavePipeline() async throws {
        let store = InMemoryNoteStore()
        let viewModel = NoteEditorViewModel(store: store, unlockAuthority: UnlockAuthority())

        viewModel.send(.setBody("Packing\n- [ ] charger"))
        viewModel.send(.save)
        try await settle { viewModel.state.note != nil }

        viewModel.send(.toggleTask(line: 1))
        XCTAssertEqual(viewModel.state.body, "Packing\n- [x] charger")
        try await settle { viewModel.state.saveStatus != .saving && viewModel.state.saveStatus != .unsaved }

        let id = try XCTUnwrap(viewModel.state.note?.id)
        let stored = try await store.body(id)
        XCTAssertEqual(stored, "Packing\n- [x] charger")

        // A locked note has no body loaded, so a tap that somehow arrived must do nothing.
        viewModel.send(.sessionLocked)
        viewModel.send(.toggleTask(line: 1))
        XCTAssertEqual(viewModel.state.body, "")
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

private actor DelayedNoteStore: NoteStore {
    private let base = InMemoryNoteStore()
    private let delay: Duration
    private var writes = 0

    init(delay: Duration) { self.delay = delay }

    func index() async throws -> NoteIndex { await base.index() }
    func body(_ id: NoteID) async throws -> String { try await base.body(id) }

    func create(_ draft: NoteDraft) async throws -> NoteDigest {
        try await Task.sleep(for: delay)
        writes += 1
        return await base.create(draft)
    }

    func update(_ id: NoteID, body: String, title: String?) async throws -> NoteDigest {
        try await Task.sleep(for: delay)
        writes += 1
        return try await base.update(id, body: body, title: title)
    }

    func apply(_ patch: NoteAttributePatch, to id: NoteID) async throws -> NoteDigest {
        try await base.apply(patch, to: id)
    }

    func discard(_ id: NoteID) async throws { try await base.discard(id) }
    func renameFolder(_ name: String, to newName: String) async throws -> Int {
        await base.renameFolder(name, to: newName)
    }

    func writeCount() -> Int { writes }

}
