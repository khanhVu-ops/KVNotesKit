import KVNotesCore
import KVNotesTesting
import SwiftUI

private struct PreviewUnlockAuthority: NoteUnlockAuthority {
    let offer = NoteUnlockOffer(biometric: .faceID)
    func authenticate(reason: LocalizedStringResource) async throws -> Bool { true }
}

private struct PreviewSecretPolicy: NoteSecretPolicy {
    func copyTransient(_ value: String) {}
}

#Preview("Notes list") {
    NotesListScreen(
        store: InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies),
        theme: .preview,
        onClose: {},
        onOpenNote: { _ in },
        onCreateNote: {}
    )
}

#Preview("Note editor") {
    NoteEditorScreen(
        note: NoteFixtures.bank,
        store: InMemoryNoteStore(notes: NoteFixtures.all, bodies: NoteFixtures.bodies),
        unlockAuthority: PreviewUnlockAuthority(),
        secretPolicy: PreviewSecretPolicy(),
        theme: .preview,
        onClose: {}
    )
}
