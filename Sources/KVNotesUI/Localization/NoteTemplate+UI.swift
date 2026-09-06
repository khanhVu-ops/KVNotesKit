import Foundation
import KVNotesCore

extension NoteTemplate {
    /// Localized display name of the template.
    public var title: LocalizedStringResource {
        switch self {
        case .blank:
            .notesKit("Blank note")
        case .seedPhrase:
            .notesKit("Crypto seed phrase")
        case .bankCard:
            .notesKit("Bank & card")
        case .credentials:
            .notesKit("Credentials")
        case .checklist:
            .notesKit("Checklist")
        }
    }
}
