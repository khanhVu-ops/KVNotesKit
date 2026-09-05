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
    ///
    /// Read `visiblePreview`, not this, to decide what a row draws — a note can carry a snippet
    /// it does not want drawn.
    public var snippet: String?
    public var characterCount: Int
    public var folder: String?
    public var folderTint: NoteFolderTint
    public var icon: String?
    public var requiresBiometricUnlock: Bool
    public var isTitleUserProvided: Bool
    /// Pinned notes lead the list under their own header. Notes have Pin where the rest of the
    /// vault has Favourite, and never both — two "keep this at the top" gestures on one row.
    public var isPinned: Bool
    /// `false` for a locked note whatever it contains — the host withholds this the way it
    /// withholds the snippet, so *has checklist* cannot be used to probe a note behind the gate.
    public var hasChecklist: Bool
    /// The user asked for this note's opening not to be drawn on the list.
    ///
    /// A display setting, not a gate, and the difference is the whole point of it existing beside
    /// `requiresBiometricUnlock`. The note still opens with one tap; the snippet is still stored
    /// and still searchable by its owner. What it buys is that the first line of a note called
    /// "Bank" is not facing the room while the list is open — the common case, and a biometric
    /// prompt on every open is far too much to pay for it.
    public var hidesPreview: Bool
    public var createdAt: Date
    public var lastEditedAt: Date

    public init(
        id: NoteID = NoteID(),
        title: String,
        snippet: String?,
        characterCount: Int,
        folder: String? = nil,
        folderTint: NoteFolderTint = .neutral,
        icon: String? = nil,
        requiresBiometricUnlock: Bool = false,
        isTitleUserProvided: Bool = false,
        isPinned: Bool = false,
        hasChecklist: Bool = false,
        hidesPreview: Bool = false,
        createdAt: Date = Date(),
        lastEditedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.characterCount = characterCount
        self.folder = folder
        self.folderTint = folderTint
        self.icon = icon
        self.requiresBiometricUnlock = requiresBiometricUnlock
        self.isTitleUserProvided = isTitleUserProvided
        self.isPinned = isPinned
        self.hasChecklist = hasChecklist
        self.hidesPreview = hidesPreview
        self.createdAt = createdAt
        self.lastEditedAt = lastEditedAt
    }

    /// The preview a row may draw, or `nil` when it may draw none.
    ///
    /// The one property the UI reads, so "withheld by the host" and "hidden by the user" cannot
    /// be handled in two places and drift apart. `snippet` stays what it was — the text search
    /// matches on, because hiding a preview from the room is not hiding the note from the person
    /// who owns it and is typing into their own search field.
    public var visiblePreview: String? { hidesPreview ? nil : snippet }
}

/// Plaintext supplied to `NoteStore.create`. A store must consume it without persisting an
/// unencrypted copy; KVNotesKit itself never writes it anywhere.
public struct NoteDraft: Equatable, Sendable {
    public var body: String
    public var title: String?
    public var folder: String?
    public var icon: String?
    public var requiresBiometricUnlock: Bool
    public var hidesPreview: Bool

    public init(
        body: String,
        title: String? = nil,
        folder: String? = nil,
        icon: String? = nil,
        requiresBiometricUnlock: Bool = false,
        hidesPreview: Bool = false
    ) {
        self.body = body
        self.title = title
        self.folder = folder
        self.icon = icon
        self.requiresBiometricUnlock = requiresBiometricUnlock
        self.hidesPreview = hidesPreview
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
    public var hidesPreview: Bool?

    public init(
        folder: NoteOptionalPatch<String> = .unchanged,
        icon: NoteOptionalPatch<String> = .unchanged,
        requiresBiometricUnlock: Bool? = nil,
        isPinned: Bool? = nil,
        hidesPreview: Bool? = nil
    ) {
        self.folder = folder
        self.icon = icon
        self.requiresBiometricUnlock = requiresBiometricUnlock
        self.isPinned = isPinned
        self.hidesPreview = hidesPreview
    }
}

public struct NoteIndex: Equatable, Sendable {
    public var notes: [NoteDigest]
    public var folders: [String]

    public init(notes: [NoteDigest] = [], folders: [String]? = nil) {
        self.notes = notes
        self.folders = folders ?? Self.deriveFolders(from: notes)
    }

    /// The tint each folder claims, taken from the notes in it.
    ///
    /// The first note wins where they disagree — a disagreement only exists between a recolour
    /// and the write that failed halfway through it, and the alternative is a folder that draws
    /// two colours at once.
    public var folderTints: [String: NoteFolderTint] {
        var tints: [String: NoteFolderTint] = [:]
        for note in notes {
            guard let folder = note.folder, tints[folder] == nil, note.folderTint != .neutral else {
                continue
            }
            tints[folder] = note.folderTint
        }
        return tints
    }

    public func count(inFolder folder: String) -> Int {
        notes.reduce(0) { $0 + ($1.folder == folder ? 1 : 0) }
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

/// A folder's colour, as a name rather than a colour value.
///
/// Folders are labels, not records — there is no folder table — so anything about a folder lives
/// on the notes that claim it, encrypted with them. A name keeps the package out of the host's
/// palette: KVNotesUI asks the theme for the colour, and the vault answers with its own token.
public enum NoteFolderTint: String, CaseIterable, Equatable, Codable, Sendable {
    case neutral
    case amber
    case rose
    case violet
    case teal
    case green
}

public enum NoteSortOrder: String, CaseIterable, Equatable, Codable, Sendable {
    case lastEditedNewest
    case lastEditedOldest
    case createdNewest
    case title
}

public enum NoteFilter: String, CaseIterable, Equatable, Codable, Sendable {
    case all
    case locked
    case hasChecklist
}

/// How the list draws its notes.
///
/// Two shapes for two ways of reading. Rows are the working view — full-width titles, one line of
/// preview, and a swipe on either edge. The grid trades the swipe for three lines of preview and
/// twice the notes per screen, which is what a person wants when they are looking *for* a note
/// rather than working through one.
public enum NoteListLayout: String, CaseIterable, Equatable, Codable, Sendable {
    case list
    case grid
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
