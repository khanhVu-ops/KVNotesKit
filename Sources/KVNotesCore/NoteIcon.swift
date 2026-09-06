import Foundation

/// Structured representation of a note's visual icon.
///
/// A note's icon is persisted as an optional string (`String?`) to remain wire and schema
/// compatible with legacy store entries. This type parses and validates that string as either:
/// - A curated or arbitrary Emoji (e.g. `"🔑"`, `"🚀"`).
/// - An SF Symbol prefixed with `"sf:"` (e.g. `"sf:key.fill"`, `"sf:lock.shield.fill"`).
public enum NoteIcon: Equatable, Hashable, Sendable {
    case emoji(String)
    case symbol(String)

    public static let symbolPrefix = "sf:"

    /// Parses an optional raw string into a `NoteIcon`.
    /// Returns `nil` if the string is nil, empty, or whitespace-only.
    public static func parse(_ raw: String?) -> NoteIcon? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix(symbolPrefix) {
            let symbolName = String(trimmed.dropFirst(symbolPrefix.count))
            return symbolName.isEmpty ? nil : .symbol(symbolName)
        }
        return .emoji(trimmed)
    }

    /// The raw string representation suitable for storage in `NoteDigest.icon` and attributes.
    public var rawValue: String {
        switch self {
        case .emoji(let emoji):
            return emoji
        case .symbol(let symbolName):
            return "\(Self.symbolPrefix)\(symbolName)"
        }
    }

    /// Symbol name if this icon represents an SF Symbol.
    public var symbolName: String? {
        if case .symbol(let name) = self { return name }
        return nil
    }

    /// Emoji string if this icon represents an emoji.
    public var emoji: String? {
        if case .emoji(let string) = self { return string }
        return nil
    }
}

/// Sanitizes arbitrary user input for emoji note icons.
///
/// Ensures inputs are capped at exactly one extended grapheme cluster, and filters out
/// wide multi-scalar sequences (such as country flags and multi-person ZWJ family sequences)
/// that break the fixed monogram tile frame.
public enum NoteIconSanitizer {
    public static func sanitizeEmoji(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstCluster = trimmed.first else { return nil }
        let scalars = Array(firstCluster.unicodeScalars)

        // Reject regional indicator sequences (country flags)
        let isFlag = scalars.count >= 2 && scalars.allSatisfy { (0x1F1E6...0x1F1FF).contains($0.value) }
        if isFlag { return nil }

        // Reject Zero-Width Joiner sequences (family, multi-person sequences)
        if scalars.contains(where: { $0.value == 0x200D }) {
            return nil
        }

        // Must actually render as an emoji (either default emoji presentation or explicit emoji variation selector)
        let isPresentedAsEmoji = scalars.contains { $0.properties.isEmojiPresentation }
            || (scalars.contains { $0.properties.isEmoji } && scalars.contains { $0.value == 0xFE0F })
        guard isPresentedAsEmoji else {
            return nil
        }

        return String(firstCluster)
    }
}

/// Curated collections of SF Symbols and Emojis for the note options icon picker.
public enum NoteIconLibrary {
    public enum Category: String, CaseIterable, Identifiable, Sendable {
        case general
        case security
        case finance
        case work
        case tech
        case places
        case emoji

        public var id: String { rawValue }

        public var titleKey: String {
            switch self {
            case .general: "General"
            case .security: "Security"
            case .finance: "Finance"
            case .work: "Work"
            case .tech: "Tech"
            case .places: "Places"
            case .emoji: "Emoji"
            }
        }
    }

    public static let generalSymbols: [String] = [
        "note.text", "star.fill", "bookmark.fill", "tag.fill",
        "pin.fill", "flag.fill", "archivebox.fill", "tray.fill",
        "bell.fill", "clock.fill", "checklist"
    ]

    public static let securitySymbols: [String] = [
        "lock.fill", "lock.shield.fill", "key.fill", "shield.fill",
        "hand.raised.fill", "touchid", "checkmark.shield.fill", "eye.slash.fill",
        "lock.badge.clock.fill", "faceid", "key.horizontal.fill"
    ]

    public static let financeSymbols: [String] = [
        "creditcard.fill", "banknote.fill", "dollarsign.circle.fill", "cart.fill",
        "bag.fill", "chart.line.uptrend.xyaxis", "receipt.fill", "wallet.pass.fill",
        "bitcoinsign.circle.fill", "eurosign.circle.fill", "sterlingsign.circle.fill"
    ]

    public static let workSymbols: [String] = [
        "briefcase.fill", "graduationcap.fill", "folder.fill", "doc.text.fill",
        "book.closed.fill", "pencil.and.ruler.fill", "calendar", "newspaper.fill",
        "chart.bar.fill", "building.2.fill", "person.2.fill"
    ]

    public static let techSymbols: [String] = [
        "desktopcomputer", "laptopcomputer", "iphone", "camera.fill",
        "photo.fill", "music.note", "gamecontroller.fill", "server.rack",
        "cpu.fill", "wifi", "bolt.fill"
    ]

    public static let placesSymbols: [String] = [
        "house.fill", "heart.fill", "pills.fill", "cross.case.fill",
        "airplane", "car.fill", "globe.americas.fill", "map.fill",
        "sparkles", "cup.and.saucer.fill", "fork.knife"
    ]

    public static func symbols(for category: Category) -> [String] {
        switch category {
        case .general: generalSymbols
        case .security: securitySymbols
        case .finance: financeSymbols
        case .work: workSymbols
        case .tech: techSymbols
        case .places: placesSymbols
        case .emoji: []
        }
    }

    public static let curatedEmojis: [String] = [
        "🔑", "🏦", "💳", "🧾", "📓", "🖥",
        "🔒", "🧭", "✈️", "🏠", "💊", "🎓",
        "⭐️", "💡", "🛡", "📦", "🏷", "🎯",
        "❤️", "☕️", "💼", "🚗", "🚀"
    ]

    /// Determines the best category to open for a given raw icon string.
    public static func category(for rawIcon: String?) -> Category {
        guard let parsed = NoteIcon.parse(rawIcon) else { return .general }
        switch parsed {
        case .emoji:
            return .emoji
        case .symbol(let name):
            for cat in Category.allCases where cat != .emoji {
                if symbols(for: cat).contains(name) {
                    return cat
                }
            }
            return .general
        }
    }
}
