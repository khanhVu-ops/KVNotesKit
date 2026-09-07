import Foundation
import KVNotesCore
import KVNotesTesting
import SwiftUI
import XCTest
@testable import KVNotesUI

@MainActor
final class NotesPerformanceGateTests: XCTestCase {
    private actor TrackingNoteStore: NoteStore {
        private let base: InMemoryNoteStore
        private(set) var bodyReadCount = 0
        private(set) var indexReadCount = 0
        private(set) var writeCount = 0

        init(base: InMemoryNoteStore) {
            self.base = base
        }

        func index() async throws -> NoteIndex {
            indexReadCount += 1
            return await base.index()
        }

        func body(_ id: NoteID) async throws -> String {
            bodyReadCount += 1
            return try await base.body(id)
        }

        func create(_ draft: NoteDraft) async throws -> NoteDigest {
            writeCount += 1
            return await base.create(draft)
        }

        func update(_ id: NoteID, body: String, title: String?) async throws -> NoteDigest {
            writeCount += 1
            return try await base.update(id, body: body, title: title)
        }

        func apply(_ patch: NoteAttributePatch, to id: NoteID) async throws -> NoteDigest {
            try await base.apply(patch, to: id)
        }

        func duplicate(_ id: NoteID) async throws -> NoteDigest {
            writeCount += 1
            return try await base.duplicate(id)
        }

        func discard(_ id: NoteID) async throws {
            try await base.discard(id)
        }

        func renameFolder(_ name: String, to newName: String) async throws -> Int {
            await base.renameFolder(name, to: newName)
        }

        func tintFolder(_ name: String, with tint: NoteFolderTint) async throws -> Int {
            await base.tintFolder(name, with: tint)
        }

        func removeFolder(_ name: String) async throws -> Int {
            await base.removeFolder(name)
        }
    }

    // MARK: - 500 Notes Performance Gate (PN-650 / NK-520)

    func testListLoadAndFilterAt500NotesReadsZeroContentBlobs() async throws {
        let (digests, bodies) = generateNotes(count: 500)
        let memoryStore = InMemoryNoteStore(notes: digests, bodies: bodies)
        let store = TrackingNoteStore(base: memoryStore)
        let viewModel = NotesListViewModel(store: store)

        let startLoad = Date()
        viewModel.send(.onAppear)
        try await settle { viewModel.state.phase == .loaded }
        let loadDuration = Date().timeIntervalSince(startLoad)

        XCTAssertEqual(viewModel.state.visibleNotes.count, 500)
        let bodyReadsOnLoad = await store.bodyReadCount
        XCTAssertEqual(bodyReadsOnLoad, 0, "D2 violation: Notes list load must read ZERO content blobs")
        XCTAssertLessThan(loadDuration, 0.250, "500 notes first paint / load must settle under 250ms")

        // Search keystroke latency
        let queries = ["Project 42", "Finance", "Urgent", "Meeting", "NonExistentKey"]
        var worstSearchLatency: TimeInterval = 0

        for query in queries {
            let startSearch = Date()
            viewModel.send(.updateSearchQuery(query))
            let searchLatency = Date().timeIntervalSince(startSearch)
            worstSearchLatency = max(worstSearchLatency, searchLatency)
        }

        let bodyReadsAfterSearch = await store.bodyReadCount
        XCTAssertEqual(bodyReadsAfterSearch, 0, "D2 violation: Searching notes list must read ZERO content blobs")
        XCTAssertLessThan(worstSearchLatency, 0.016, "Search keystroke filter across 500 notes must fit within 16ms (60fps frame budget)")

        // Clear query before testing folder switching
        viewModel.send(.updateSearchQuery(""))

        // Folder switching latency
        let startFolder = Date()
        viewModel.send(.selectFolder("Finance"))
        let folderLatency = Date().timeIntervalSince(startFolder)
        XCTAssertLessThan(folderLatency, 0.016, "Folder filter must fit within 16ms")
        XCTAssertEqual(viewModel.state.visibleNotes.count, 50)

        let bodyReadsAfterFolder = await store.bodyReadCount
        XCTAssertEqual(bodyReadsAfterFolder, 0, "D2 violation: Folder filtering must read ZERO content blobs")

        // Reset
        viewModel.send(.selectFolder(nil))
        XCTAssertEqual(viewModel.state.visibleNotes.count, 500)
    }

    func testFolderChipAggregationAt500Notes() async throws {
        let (digests, bodies) = generateNotes(count: 500)
        let memoryStore = InMemoryNoteStore(notes: digests, bodies: bodies)
        let store = TrackingNoteStore(base: memoryStore)
        let viewModel = NotesListViewModel(store: store)

        viewModel.send(.onAppear)
        try await settle { viewModel.state.phase == .loaded }

        // 10 folders with 50 notes each
        XCTAssertEqual(viewModel.state.folderChips.count, 10)
        for chip in viewModel.state.folderChips {
            XCTAssertEqual(chip.count, 50)
        }

        let bodyReads = await store.bodyReadCount
        XCTAssertEqual(bodyReads, 0, "Folder chip count aggregation must read ZERO content blobs")
    }

    // MARK: - 100 KiB Note Open and Autosave Latency

    func testLargeNoteEditorOpenAndAutosaveLatency() async throws {
        let largeBody = String(repeating: "Line of text inside a 100 KiB encrypted private note payload.\n", count: 2_000)
        XCTAssertGreaterThan(largeBody.utf8.count, 100_000)

        let now = Date()
        let id = NoteID()
        let digest = NoteDigest(
            id: id,
            title: "Large Note",
            snippet: "Line of text",
            characterCount: largeBody.count,
            folder: "Work",
            icon: nil,
            requiresBiometricUnlock: false,
            isTitleUserProvided: true,
            isPinned: false,
            hidesPreview: false,
            createdAt: now,
            lastEditedAt: now
        )

        let memoryStore = InMemoryNoteStore(notes: [digest], bodies: [id: largeBody])
        let store = TrackingNoteStore(base: memoryStore)
        let unlockAuthority = MockUnlockAuthority()

        let startOpen = Date()
        let viewModel = NoteEditorViewModel(note: digest, store: store, unlockAuthority: unlockAuthority)
        viewModel.send(.onAppear)
        try await settle { !viewModel.state.isLoading && !viewModel.state.body.isEmpty }
        let openDuration = Date().timeIntervalSince(startOpen)

        XCTAssertEqual(viewModel.state.body.count, largeBody.count)
        let bodyReads = await store.bodyReadCount
        XCTAssertEqual(bodyReads, 1, "Opening note editor should read body exactly once")
        XCTAssertLessThan(openDuration, 0.250, "Opening a 100 KiB note should load in under 250ms")

        // Trigger save on 100 KiB note
        viewModel.send(.setBody(largeBody + "\nAppended line."))
        viewModel.send(.save)
        try await settle {
            if case .saved = viewModel.state.saveStatus { true } else { false }
        }

        let writes = await store.writeCount
        XCTAssertGreaterThanOrEqual(writes, 1, "Autosave must commit to store")
        let updatedBody = try await store.body(id)
        XCTAssertTrue(updatedBody.hasSuffix("Appended line."))
    }

    // MARK: - Helper Methods

    private func generateNotes(count: Int) -> ([NoteDigest], [NoteID: String]) {
        var digests: [NoteDigest] = []
        var bodies: [NoteID: String] = [:]
        let folders = ["Personal", "Work", "Finance", "Ideas", "Travel", "Projects", "Archive", "Health", "Reading", "Keys"]

        for i in 0..<count {
            let id = NoteID()
            let folder = folders[i % folders.count]
            let isPinned = i < 5
            let isLocked = i % 10 == 0
            let title = "Note \(i) in \(folder)"
            let body = "Content of note \(i) with confidential details.\nAnother line of encrypted text."
            let now = Date().addingTimeInterval(-Double(count - i) * 60)

            let digest = NoteDigest(
                id: id,
                title: title,
                snippet: isLocked ? nil : "Content of note \(i)...",
                characterCount: body.count,
                folder: folder,
                icon: nil,
                requiresBiometricUnlock: isLocked,
                isTitleUserProvided: true,
                isPinned: isPinned,
                hidesPreview: false,
                createdAt: now,
                lastEditedAt: now
            )
            digests.append(digest)
            bodies[id] = body
        }
        return (digests, bodies)
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
private struct MockUnlockAuthority: NoteUnlockAuthority {
    let offer = NoteUnlockOffer(biometric: .faceID)
    func authenticate(reason: LocalizedStringResource) async throws -> Bool { true }
}
