import Foundation

/// A quick-start skeleton for new private notes.
public enum NoteTemplate: String, CaseIterable, Identifiable, Sendable {
    case blank
    case seedPhrase
    case bankCard
    case credentials
    case checklist

    public var id: String { rawValue }

    /// SF Symbol icon identifying the template in menus and pickers.
    public var iconSymbol: String {
        switch self {
        case .blank:
            "square.and.pencil"
        case .seedPhrase:
            "key.fill"
        case .bankCard:
            "creditcard.fill"
        case .credentials:
            "person.badge.key.fill"
        case .checklist:
            "checklist"
        }
    }

    /// Suggested emoji icon stored with the note on first save.
    public var defaultIcon: String? {
        switch self {
        case .blank:
            nil
        case .seedPhrase:
            "🔑"
        case .bankCard:
            "💳"
        case .credentials:
            "🔒"
        case .checklist:
            "🧾"
        }
    }

    /// Initial Markdown content populated when creating a note from this template.
    public var initialMarkdown: String {
        switch self {
        case .blank:
            ""
        case .seedPhrase:
            """
            # Recovery Phrase

            > Keep this phrase offline and never share it with anyone.

            1. 
            2. 
            3. 
            4. 
            5. 
            6. 
            7. 
            8. 
            9. 
            10. 
            11. 
            12. 
            """
        case .bankCard:
            """
            # Bank & Card

            - **Bank**: 
            - **Account Name**: 
            - **Account Number**: 
            - **Routing / Swift**: 
            - **Card Number**: 
            - **Expiry Date**: 
            - **CVV / CVC**: 
            - **PIN**: 
            - **Notes**: 
            """
        case .credentials:
            """
            # Login Credentials

            - **Service**: 
            - **Username**: 
            - **Email**: 
            - **Password**: 
            - **URL**: 
            - **2FA Recovery**: 
            - **Notes**: 
            """
        case .checklist:
            """
            # Checklist

            - [ ] 
            - [ ] 
            - [ ] 
            """
        }
    }

    /// The offset in UTF-16 code units where typing should begin when the template loads.
    public var initialCaretOffset: Int {
        switch self {
        case .blank:
            0
        case .seedPhrase:
            offset(after: "1. ")
        case .bankCard:
            offset(after: "- **Bank**: ")
        case .credentials:
            offset(after: "- **Service**: ")
        case .checklist:
            offset(after: "- [ ] ")
        }
    }

    private func offset(after pattern: String) -> Int {
        guard let range = initialMarkdown.range(of: pattern) else {
            return initialMarkdown.utf16.count
        }
        return initialMarkdown[..<range.upperBound].utf16.count
    }
}
