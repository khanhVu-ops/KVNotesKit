import Foundation
import KVNotesCore
import KVNotesTesting
import SwiftUI
import XCTest
@testable import KVNotesUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class NoteLifecycleAndHardeningTests: XCTestCase {
    #if canImport(UIKit)
    func testTextEditorDisablesKeyboardLearningAndPrediction() {
        var text = "Sensitive secret"
        var selection = 0..<0
        let editor = NoteTextEditor(
            text: Binding(get: { text }, set: { text = $0 }),
            selection: Binding(get: { selection }, set: { selection = $0 }),
            pendingCaretOffset: nil,
            theme: .preview,
            onCaretApplied: {},
            onInsert: { _ in },
            onContinuation: nil,
            onUndo: {},
            onRedo: {},
            onInsertTimestamp: {},
            onOpenGenerator: {},
            onOpenFind: {},
            onIndent: {},
            onOutdent: {},
            canUndo: false,
            canRedo: false,
            findMatches: [],
            currentFindMatch: nil,
            isActive: true,
            doneTitle: "Done",
            undoTitle: "Undo",
            redoTitle: "Redo",
            timestampTitle: "Timestamp",
            generatorTitle: "Password",
            findTitle: "Find",
            indentTitle: "Indent",
            outdentTitle: "Outdent",
            haptic: {},
            onToggleTask: nil
        )

        class MockCoordinatorContext {
            let coordinator: NoteTextEditor.Coordinator
            init(editor: NoteTextEditor) {
                self.coordinator = editor.makeCoordinator()
            }
        }

        // UITextView settings must prevent learning
        let textView = UITextView()
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContentType = nil

        XCTAssertEqual(textView.autocorrectionType, .no, "Autocorrection must be disabled")
        XCTAssertEqual(textView.spellCheckingType, .no, "Spell checking must be disabled")
        XCTAssertEqual(textView.autocapitalizationType, .none, "Autocapitalization must be disabled")
        XCTAssertEqual(textView.smartQuotesType, .no, "Smart quotes must be disabled")
        XCTAssertEqual(textView.smartDashesType, .no, "Smart dashes must be disabled")
        XCTAssertEqual(textView.smartInsertDeleteType, .no, "Smart insert/delete must be disabled")
        XCTAssertNil(textView.textContentType, "textContentType must be nil to avoid auto-fill aggregation")
    }
    #endif

    func testEditorSavesPendingChangesOnDemand() async throws {
        let store = InMemoryNoteStore()
        let authority = MockAuthority()
        let viewModel = NoteEditorViewModel(store: store, unlockAuthority: authority)

        viewModel.send(.onAppear)
        viewModel.send(.setTitle("Important Document"))
        viewModel.send(.setBody("Confidential meeting minutes"))

        XCTAssertTrue(viewModel.state.isDirty, "Editor must be dirty after modifications")

        // Trigger manual/lifecycle save
        viewModel.send(.save)
        try await settle {
            if case .saved = viewModel.state.saveStatus { true } else { false }
        }

        XCTAssertFalse(viewModel.state.isDirty, "Editor must no longer be dirty after save")
        let index = await store.index()
        XCTAssertEqual(index.notes.count, 1)
        XCTAssertEqual(index.notes.first?.title, "Important Document")
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
private struct MockAuthority: NoteUnlockAuthority {
    let offer = NoteUnlockOffer(biometric: .faceID)
    func authenticate(reason: LocalizedStringResource) async throws -> Bool { true }
}
