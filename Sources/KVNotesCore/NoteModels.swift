import Foundation

public struct NoteID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: UUID())
    }

    public var id: Self { self }
}

/// The metadata a list may retain for one note. The body is deliberately absent.
public struct NoteDigest: Identifiable, Equatable, Sendable {
    public let id: NoteID
    public var title: String
    /// `nil` means the host withheld the preview, most importantly for a locked note. The UI
    /// must render a protected state and must never try to recover a preview from the body.
    public var snippet: String?
    public var characterCount: Int
    public var folder: String?
    public var icon: String?
    public var requiresBiometricUnlock: Bool
    public var isTitleUserProvided: Bool
    /// Pinned notes lead the list under their own header. Notes have Pin where the rest of the
    /// vault has Favourite, and never both — two "keep this at the top" gestures on one row.
    public var isPinned: Bool
    public var createdAt: Date
    public var lastEditedAt: Date

    public init(
        id: NoteID = NoteID(),
        title: String,
        snippet: String?,
        characterCount: Int,
        folder: String? = nil,
        icon: String? = nil,
        requiresBiometricUnlock: Bool = false,
        isTitleUserProvided: Bool = false,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        lastEditedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.characterCount = characterCount
        self.folder = folder
        self.icon = icon
        self.requiresBiometricUnlock = requiresBiometricUnlock
        self.isTitleUserProvided = isTitleUserProvided
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.lastEditedAt = lastEditedAt
    }
}

/// Plaintext supplied to `NoteStore.create`. A store must consume it without persisting an
/// unencrypted copy; KVNotesKit itself never writes it anywhere.
public struct NoteDraft: Equatable, Sendable {
    public var body: String
    public var title: String?
    public var folder: String?
    public var icon: String?
    public var requiresBiometricUnlock: Bool

    public init(
        body: String,
        title: String? = nil,
        folder: String? = nil,
        icon: String? = nil,
        requiresBiometricUnlock: Bool = false
    ) {
        self.body = body
        self.title = title
        self.folder = folder
        self.icon = icon
        self.requiresBiometricUnlock = requiresBiometricUnlock
    }
}

public enum NoteOptionalPatch<Value: Equatable & Sendable>: Equatable, Sendable {
    case unchanged
    case set(Value?)
}

/// Metadata-only changes. The absence of `body` makes it impossible to accidentally route an
/// attribute edit through a second plaintext write path.
public struct NoteAttributePatch: Equatable, Sendable {
    public var folder: NoteOptionalPatch<String>
    public var icon: NoteOptionalPatch<String>
    public var requiresBiometricUnlock: Bool?
    public var isPinned: Bool?

    public init(
        folder: NoteOptionalPatch<String> = .unchanged,
        icon: NoteOptionalPatch<String> = .unchanged,
        requiresBiometricUnlock: Bool? = nil,
        isPinned: Bool? = nil
    ) {
        self.folder = folder
        self.icon = icon
        self.requiresBiometricUnlock = requiresBiometricUnlock
        self.isPinned = isPinned
    }
}

public struct NoteIndex: Equatable, Sendable {
    public var notes: [NoteDigest]
    public var folders: [String]

    public init(notes: [NoteDigest] = [], folders: [String]? = nil) {
        self.notes = notes
        self.folders = folders ?? Self.deriveFolders(from: notes)
    }

    public var isEmpty: Bool { notes.isEmpty }

    public static func deriveFolders(from notes: [NoteDigest]) -> [String] {
        var counts: [String: Int] = [:]
        for note in notes {
            guard let folder = note.folder else { continue }
            counts[folder, default: 0] += 1
        }
        return counts.keys.sorted {
            let left = counts[$0, default: 0]
            let right = counts[$1, default: 0]
            return left == right
                ? $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                : left > right
        }
    }
}

public enum NoteSortOrder: String, CaseIterable, Equatable, Sendable {
    case lastEditedNewest
    case lastEditedOldest
    case createdNewest
    case title
}

public enum NoteFilter: String, CaseIterable, Equatable, Sendable {
    case all
    case locked
    case hasChecklist
}

public enum NoteBiometricKind: Equatable, Sendable {
    case faceID
    case touchID
    case opticID
}

public struct NoteUnlockOffer: Equatable, Sendable {
    public var biometric: NoteBiometricKind?
    public var allowsPINFallback: Bool

    public init(biometric: NoteBiometricKind? = nil, allowsPINFallback: Bool = true) {
        self.biometric = biometric
        self.allowsPINFallback = allowsPINFallback
    }
}
