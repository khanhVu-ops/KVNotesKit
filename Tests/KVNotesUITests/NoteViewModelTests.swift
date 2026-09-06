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
        // The row moves before the write returns; waiting for storage makes it sit still under
        // the finger and then jump.
        XCTAssertEqual(viewModel.state.pinnedCount, 2)
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
        first.send(.setLayout(.grid))

        // A second screen, as if the user had left the flow and come back.
        let second = NotesListViewModel(store: store, preferences: preferences)
        XCTAssertEqual(second.state.sortOrder, .title)
        XCTAssertEqual(second.state.filter, .locked)
        XCTAssertEqual(second.state.layout, .grid)
        second.send(.onAppear)
        try await settle { second.state.phase == .loaded }
        XCTAssertEqual(second.state.visibleNotes.map(\.title), ["Hardware wallet"])

        // And a screen with nowhere to read from opens on the defaults rather than crashing.
        let third = NotesListViewModel(store: store)
        XCTAssertEqual(third.state.sortOrder, .lastEditedNewest)
        XCTAssertEqual(third.state.filter, .all)
        XCTAssertEqual(third.state.layout, .list)
    }

    func testTheLayoutIsAViewChoiceAndNotAFilter() async throws {
        let store = InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies)
        let viewModel = NotesListViewModel(store: store)
        viewModel.send(.onAppear)
        try await settle { viewModel.state.phase == .loaded }

        let rows = viewModel.state.visibleNotes.map(\.id)
        viewModel.send(.setLayout(.grid))

        // Same notes, same order, same pinned split: the grid draws the list, it does not
        // compute a different one. `isNarrowed` marks the sort control, and a layout that lit
        // it would be telling the user their notes are being hidden.
        XCTAssertEqual(viewModel.state.visibleNotes.map(\.id), rows)
        XCTAssertEqual(viewModel.state.pinnedCount, 1)
        XCTAssertFalse(viewModel.state.isNarrowed)
    }

    func testAPreferencesBlobWrittenBeforeTheLayoutExistedKeepsItsSortAndFilter() throws {
        // Exactly what a device upgrading from 0.1.0 has on disk.
        let legacy = Data(#"{"sortOrder":"title","filter":"locked"}"#.utf8)
        let decoded = try JSONDecoder().decode(NoteListPreferences.self, from: legacy)

        XCTAssertEqual(decoded.sortOrder, .title)
        XCTAssertEqual(decoded.filter, .locked)
        XCTAssertEqual(decoded.layout, .list)
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

    func testUndoCoversTypingTheToolbarAndTheCheckboxes() async throws {
        let store = InMemoryNoteStore()
        let viewModel = NoteEditorViewModel(store: store, unlockAuthority: UnlockAuthority())

        XCTAssertFalse(viewModel.state.canUndo)
        viewModel.send(.setBody("milk"))
        XCTAssertTrue(viewModel.state.canUndo)

        // A toolbar key opens its own entry, so one undo takes the formatting off and leaves the
        // typing — the thing UIKit's own stack could not do, because assigning `.text` clears it.
        viewModel.send(.insert(.bold, 0..<4))
        XCTAssertEqual(viewModel.state.body, "**milk**")
        viewModel.send(.undo)
        XCTAssertEqual(viewModel.state.body, "milk")
        XCTAssertTrue(viewModel.state.canRedo)
        viewModel.send(.redo)
        XCTAssertEqual(viewModel.state.body, "**milk**")

        // Typing after an undo abandons the redo branch rather than leaving a stale future.
        viewModel.send(.undo)
        viewModel.send(.setBody("bread"))
        XCTAssertFalse(viewModel.state.canRedo)

        // And a ticked checkbox is undoable like anything else.
        viewModel.send(.setBody("- [ ] milk"))
        viewModel.send(.save)
        try await settle { viewModel.state.note != nil }
        viewModel.send(.toggleTask(line: 0))
        XCTAssertEqual(viewModel.state.body, "- [x] milk")
        viewModel.send(.undo)
        XCTAssertEqual(viewModel.state.body, "- [ ] milk")
    }

    func testListContinuationIsUndoable() async throws {
        let viewModel = NoteEditorViewModel(store: InMemoryNoteStore(), unlockAuthority: UnlockAuthority())
        viewModel.send(.setBody("- [ ] milk"))
        viewModel.send(.applyContinuation(text: "- [ ] milk\n- [ ] ", caretOffset: 17))
        XCTAssertEqual(viewModel.state.body, "- [ ] milk\n- [ ] ")
        XCTAssertEqual(viewModel.state.selection, 17..<17)

        viewModel.send(.undo)
        XCTAssertEqual(viewModel.state.body, "- [ ] milk")
    }

    func testIndentAndOutdentAreUndoable() async throws {
        let viewModel = NoteEditorViewModel(store: InMemoryNoteStore(), unlockAuthority: UnlockAuthority())
        viewModel.send(.setBody("- [ ] milk"))
        viewModel.send(.setSelection(2..<2))

        viewModel.send(.indent)
        XCTAssertEqual(viewModel.state.body, "  - [ ] milk")
        XCTAssertEqual(viewModel.state.selection, 4..<4)

        viewModel.send(.outdent)
        XCTAssertEqual(viewModel.state.body, "- [ ] milk")
        XCTAssertEqual(viewModel.state.selection, 2..<2)

        viewModel.send(.undo)
        XCTAssertEqual(viewModel.state.body, "  - [ ] milk")
    }

    func testHistoryDiesWithTheSession() async throws {
        let viewModel = NoteEditorViewModel(store: InMemoryNoteStore(), unlockAuthority: UnlockAuthority())

        viewModel.send(.setBody("recovery phrase"))
        viewModel.send(.sessionLocked)

        // Every entry holds a copy of the note, so history is plaintext by another name.
        XCTAssertFalse(viewModel.state.canUndo)
        XCTAssertFalse(viewModel.state.canRedo)
        viewModel.send(.undo)
        XCTAssertEqual(viewModel.state.body, "")
    }

    func testInsertedTextLandsAtTheCaretAndIsUndoable() {
        let viewModel = NoteEditorViewModel(store: InMemoryNoteStore(), unlockAuthority: UnlockAuthority())

        viewModel.send(.setBody("password: "))
        viewModel.send(.insertText("s3cret", 10..<10))

        XCTAssertEqual(viewModel.state.body, "password: s3cret")
        XCTAssertEqual(viewModel.state.pendingCaretOffset, 16)

        // The caret the ViewModel issues is also the point the *next* insertion uses, which is
        // what a sheet's stale copy of the view struct got wrong before the caret moved here.
        XCTAssertEqual(viewModel.state.selection, 16..<16)
        viewModel.send(.insertText("!", viewModel.state.selection))
        XCTAssertEqual(viewModel.state.body, "password: s3cret!")

        // A selection is replaced rather than appended to, and the whole insertion is one undo.
        viewModel.send(.insertText("other", 10..<17))
        XCTAssertEqual(viewModel.state.body, "password: other")
        viewModel.send(.undo)
        XCTAssertEqual(viewModel.state.body, "password: s3cret!")
    }

    func testFindCountsMatchesStepsThroughThemAndFollowsTheBody() {
        let viewModel = NoteEditorViewModel(store: InMemoryNoteStore(), unlockAuthority: UnlockAuthority())
        viewModel.send(.setBody("ledger one\nLEDGER two\nnothing"))
        viewModel.send(.setSelection(0..<0))

        viewModel.send(.openFind)
        // Find reads the source, so it opens the editor rather than searching the rendered view.
        XCTAssertEqual(viewModel.state.mode, .edit)

        viewModel.send(.setFindQuery("ledger"))
        XCTAssertEqual(viewModel.state.find.matches.count, 2)
        XCTAssertEqual(viewModel.state.find.currentNumber, 1)

        viewModel.send(.stepFind(forward: true))
        XCTAssertEqual(viewModel.state.find.currentNumber, 2)
        // Stepping past the end wraps rather than stopping dead.
        viewModel.send(.stepFind(forward: true))
        XCTAssertEqual(viewModel.state.find.currentNumber, 1)
        viewModel.send(.stepFind(forward: false))
        XCTAssertEqual(viewModel.state.find.currentNumber, 2)

        // A match range into text that has moved is a highlight over the wrong words.
        viewModel.send(.setBody("ledger one"))
        XCTAssertEqual(viewModel.state.find.matches.count, 1)

        viewModel.send(.closeFind)
        XCTAssertFalse(viewModel.state.find.isOpen)
        XCTAssertTrue(viewModel.state.find.matches.isEmpty)
    }

    func testFindStartsAtTheMatchNearestTheCaret() {
        let viewModel = NoteEditorViewModel(store: InMemoryNoteStore(), unlockAuthority: UnlockAuthority())
        viewModel.send(.setBody("key at the top\n\nand a key far below"))
        viewModel.send(.setSelection(20..<20))

        viewModel.send(.openFind)
        viewModel.send(.setFindQuery("key"))

        // Opening find where the reader is should not throw them back to the top of the note.
        XCTAssertEqual(viewModel.state.find.currentNumber, 2)
    }

    func testASecondWriteQueuesBehindTheFirstRatherThanBeingDropped() async throws {
        let store = InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies)
        let viewModel = NotesListViewModel(store: store)
        viewModel.send(.onAppear)
        try await settle { viewModel.state.phase == .loaded }

        // Two swipes in the same breath. Both rows have already moved on screen, so a write
        // refused for arriving while the first one was still in flight would leave the second
        // note pinned in the list and unpinned in the vault until something reloaded it.
        viewModel.send(.togglePin(NoteFixtures.bank.id))
        viewModel.send(.togglePin(NoteFixtures.journal.id))
        XCTAssertTrue(viewModel.state.isBusy)
        try await settle { !viewModel.state.isBusy }

        let index = await store.index()
        XCTAssertTrue(index.notes.first { $0.id == NoteFixtures.bank.id }?.isPinned == true)
        XCTAssertTrue(index.notes.first { $0.id == NoteFixtures.journal.id }?.isPinned == true)
        XCTAssertEqual(viewModel.state.pinnedCount, 3)
    }

    func testAHiddenPreviewStopsBeingDrawnButKeepsBeingSearchable() async throws {
        let store = InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies)
        let viewModel = NotesListViewModel(store: store)
        viewModel.send(.onAppear)
        try await settle { viewModel.state.phase == .loaded }

        let bank = try XCTUnwrap(viewModel.state.visibleNotes.first { $0.id == NoteFixtures.bank.id })
        XCTAssertEqual(bank.visiblePreview, bank.snippet)

        _ = try await store.apply(NoteAttributePatch(hidesPreview: true), to: NoteFixtures.bank.id)
        viewModel.send(.refresh)
        try await settle { viewModel.state.index.notes.contains { $0.hidesPreview } }

        let hidden = try XCTUnwrap(viewModel.state.visibleNotes.first { $0.id == NoteFixtures.bank.id })
        // Nothing for a row to draw…
        XCTAssertNil(hidden.visiblePreview)
        // …and the text is still there for the person who owns the vault to search on. Hiding a
        // preview is about the room, not about locking the owner out of their own note.
        XCTAssertEqual(hidden.snippet, NoteFixtures.bank.snippet)
        XCTAssertFalse(hidden.requiresBiometricUnlock)

        viewModel.send(.updateSearchQuery("transfer"))
        XCTAssertEqual(viewModel.state.visibleNotes.map(\.title), ["Bank details"])
    }

    func testALockedNoteHasNoPreviewToHideOrToSearch() async throws {
        let store = InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies)
        let viewModel = NotesListViewModel(store: store)
        viewModel.send(.onAppear)
        try await settle { viewModel.state.phase == .loaded }

        // The gate is the stronger promise and it is unaffected by the weaker one: the host
        // withholds the snippet entirely, so `visiblePreview` is nil whichever way the flag sits.
        let wallet = try XCTUnwrap(viewModel.state.visibleNotes.first { $0.id == NoteFixtures.wallet.id })
        XCTAssertTrue(wallet.requiresBiometricUnlock)
        XCTAssertNil(wallet.snippet)
        XCTAssertNil(wallet.visiblePreview)
    }

    func testTheOptionSheetReadsTheNoteItIsAboutRatherThanACopy() async throws {
        let store = InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies)
        let viewModel = NotesListViewModel(store: store)
        viewModel.send(.onAppear)
        try await settle { viewModel.state.phase == .loaded }

        viewModel.send(.openOptions(.note(NoteFixtures.bank.id)))
        XCTAssertEqual(viewModel.state.optionSheetNote?.isPinned, false)

        // The sheet stays open long enough to animate out after its own Pin was tapped, and in
        // that window it must not still be offering to pin a note it has already pinned.
        viewModel.send(.togglePin(NoteFixtures.bank.id))
        XCTAssertEqual(viewModel.state.optionSheetNote?.isPinned, true)

        // A confirmation replaces the options it was asked from rather than stacking on them.
        viewModel.send(.requestDiscard(NoteFixtures.bank))
        XCTAssertNil(viewModel.state.optionSheet)
        XCTAssertNil(viewModel.state.optionSheetNote)
        XCTAssertNotNil(viewModel.state.pendingDiscard)
    }

    func testLeavingSelectionClosesTheBatchOptions() async throws {
        let store = InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies)
        let viewModel = NotesListViewModel(store: store)
        viewModel.send(.onAppear)
        try await settle { viewModel.state.phase == .loaded }

        viewModel.send(.startSelecting)
        viewModel.send(.toggleSelection(NoteFixtures.bank.id))
        viewModel.send(.openOptions(.batch))
        XCTAssertEqual(viewModel.state.optionSheet, .batch)

        // Batch options with nothing selected are a list of actions on nothing.
        viewModel.send(.stopSelecting)
        XCTAssertNil(viewModel.state.optionSheet)
    }

    func testBatchActionsApplyToEverySelectedNoteAndThenEndTheSelection() async throws {
        let store = InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies)
        let viewModel = NotesListViewModel(store: store)
        viewModel.send(.onAppear)
        try await settle { viewModel.state.phase == .loaded }

        viewModel.send(.startSelecting)
        viewModel.send(.selectAllOrNone)
        XCTAssertTrue(viewModel.state.isEverythingSelected)
        // One fixture is already pinned, so the mixed selection pins the rest rather than
        // toggling each note into the opposite of what it was.
        XCTAssertTrue(viewModel.state.batchWouldPin)

        viewModel.send(.batchPin)
        // Selection ends with the batch: five rows left ticked are a selection of things that
        // are no longer where the user left them.
        XCTAssertFalse(viewModel.state.isSelecting)
        XCTAssertTrue(viewModel.state.selection.isEmpty)
        try await settle { !viewModel.state.isBusy }
        let afterPin = await store.index()
        XCTAssertTrue(afterPin.notes.allSatisfy(\.isPinned))

        viewModel.send(.startSelecting)
        viewModel.send(.toggleSelection(NoteFixtures.journal.id))
        viewModel.send(.batchMoveToFolder("Archive"))
        try await settle { !viewModel.state.isBusy }
        let afterMove = await store.index()
        XCTAssertEqual(
            afterMove.notes.first { $0.id == NoteFixtures.journal.id }?.folder,
            "Archive"
        )
        XCTAssertEqual(afterMove.notes.first { $0.id == NoteFixtures.bank.id }?.folder, "Banking")
    }

    func testABatchTrashAsksFirstAndDiscardsEveryChosenNote() async throws {
        let store = InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies)
        let viewModel = NotesListViewModel(store: store)
        viewModel.send(.onAppear)
        try await settle { viewModel.state.phase == .loaded }

        viewModel.send(.startSelecting)
        viewModel.send(.toggleSelection(NoteFixtures.journal.id))
        viewModel.send(.toggleSelection(NoteFixtures.bank.id))
        viewModel.send(.requestBatchDiscard)
        XCTAssertTrue(viewModel.state.pendingBatchDiscard)

        viewModel.send(.cancelBatchDiscard)
        XCTAssertFalse(viewModel.state.pendingBatchDiscard)
        let afterCancel = await store.index().notes.count
        XCTAssertEqual(afterCancel, 3)

        viewModel.send(.requestBatchDiscard)
        viewModel.send(.confirmBatchDiscard)
        try await settle { !viewModel.state.isBusy }
        let remaining = await store.index().notes.map(\.id)
        XCTAssertEqual(remaining, [NoteFixtures.wallet.id])
    }

    func testFolderManagementRenamesTintsAndRemovesWithoutLosingNotes() async throws {
        let store = InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies)
        let viewModel = NotesListViewModel(store: store)
        viewModel.send(.onAppear)
        try await settle { viewModel.state.phase == .loaded }

        viewModel.send(.selectFolder("Banking"))
        viewModel.send(.renameFolder("Banking", to: "Money"))
        // The chip was filtering on a name that is about to stop existing.
        XCTAssertEqual(viewModel.state.selectedFolder, "Money")
        try await settle { !viewModel.state.isBusy }
        XCTAssertEqual(viewModel.state.index.folders.sorted(), ["Money", "Passwords"])

        viewModel.send(.tintFolder("Money", .teal))
        try await settle { !viewModel.state.isBusy }
        XCTAssertEqual(viewModel.state.index.folderTints["Money"], .teal)

        let before = viewModel.state.index.notes.count
        viewModel.send(.removeFolder("Money"))
        XCTAssertNil(viewModel.state.selectedFolder)
        try await settle { !viewModel.state.isBusy }
        // Removing a label is not removing the things it was on.
        XCTAssertEqual(viewModel.state.index.notes.count, before)
        XCTAssertFalse(viewModel.state.index.folders.contains("Money"))
        XCTAssertNil(viewModel.state.index.notes.first { $0.id == NoteFixtures.bank.id }?.folder)
    }

    func testEditorWithUnmodifiedTemplateRefusesToSaveSkeleton() async throws {
        let store = InMemoryNoteStore()
        let viewModel = NoteEditorViewModel(template: .seedPhrase, store: store, unlockAuthority: UnlockAuthority())

        XCTAssertEqual(viewModel.state.body, NoteTemplate.seedPhrase.initialMarkdown)
        XCTAssertEqual(viewModel.state.icon, "🔑")
        XCTAssertEqual(viewModel.state.pendingCaretOffset, NoteTemplate.seedPhrase.initialCaretOffset)
        XCTAssertFalse(viewModel.state.hasContent)

        viewModel.send(.save)
        await Task.yield()

        let index = await store.index()
        XCTAssertEqual(index.notes.count, 0)
        XCTAssertNil(viewModel.state.note)
    }

    func testEditorWithModifiedTemplateSavesToStore() async throws {
        let store = InMemoryNoteStore()
        let viewModel = NoteEditorViewModel(template: .seedPhrase, store: store, unlockAuthority: UnlockAuthority())

        viewModel.send(.setBody(NoteTemplate.seedPhrase.initialMarkdown + "apple banana cherry"))
        XCTAssertTrue(viewModel.state.hasContent)

        viewModel.send(.save)
        try await settle { viewModel.state.note != nil && !viewModel.state.isDirty }

        let index = await store.index()
        XCTAssertEqual(index.notes.count, 1)
        XCTAssertEqual(index.notes.first?.icon, "🔑")

        let id = try XCTUnwrap(viewModel.state.note?.id)
        let body = try await store.body(id)
        XCTAssertTrue(body.contains("apple banana cherry"))
    }

    func testEditorWithTemplateTitleOnlySavesToStore() async throws {
        let store = InMemoryNoteStore()
        let viewModel = NoteEditorViewModel(template: .bankCard, store: store, unlockAuthority: UnlockAuthority())

        viewModel.send(.setTitle("My Chase Card"))
        XCTAssertTrue(viewModel.state.hasContent)

        viewModel.send(.save)
        try await settle { viewModel.state.note != nil && !viewModel.state.isDirty }

        let index = await store.index()
        XCTAssertEqual(index.notes.count, 1)
        XCTAssertEqual(index.notes.first?.title, "My Chase Card")
        XCTAssertEqual(index.notes.first?.icon, "💳")
    }

    func testOpenAndCloseTemplatesOptionSheet() {
        let store = InMemoryNoteStore()
        let viewModel = NotesListViewModel(store: store)

        viewModel.send(.openOptions(.templates))
        XCTAssertEqual(viewModel.state.optionSheet, .templates)

        viewModel.send(.closeOptions)
        XCTAssertNil(viewModel.state.optionSheet)
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

    func tintFolder(_ name: String, with tint: NoteFolderTint) async throws -> Int {
        await base.tintFolder(name, with: tint)
    }

    func removeFolder(_ name: String) async throws -> Int {
        await base.removeFolder(name)
    }

    func writeCount() -> Int { writes }

}
