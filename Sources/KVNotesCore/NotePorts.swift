import Foundation

public protocol NoteStore: Sendable {
    func index() async throws -> NoteIndex
    func body(_ id: NoteID) async throws -> String
    func create(_ draft: NoteDraft) async throws -> NoteDigest
    func update(_ id: NoteID, body: String, title: String?) async throws -> NoteDigest
    func apply(_ patch: NoteAttributePatch, to id: NoteID) async throws -> NoteDigest
    func discard(_ id: NoteID) async throws
    func renameFolder(_ name: String, to newName: String) async throws -> Int
    /// Paints every note in the folder with one tint. Folders are labels, so this is the only
    /// place the colour can live.
    func tintFolder(_ name: String, with tint: NoteFolderTint) async throws -> Int
    /// Takes the folder off its notes. It never discards a note: a folder is a label, and
    /// removing a label is not removing the thing it was on.
    func removeFolder(_ name: String) async throws -> Int
}

@MainActor
public protocol NoteUnlockAuthority: Sendable {
    var offer: NoteUnlockOffer { get }
    func authenticate(reason: LocalizedStringResource) async throws -> Bool
}

@MainActor
public protocol NoteSecretPolicy: Sendable {
    var transientCopyLifetime: TimeInterval { get }
    func copyTransient(_ value: String)
}

public extension NoteSecretPolicy {
    var transientCopyLifetime: TimeInterval { 60 }
}

/// How the user last chose to see the list.
public struct NoteListPreferences: Equatable, Codable, Sendable {
    public var sortOrder: NoteSortOrder
    public var filter: NoteFilter

    public init(sortOrder: NoteSortOrder = .lastEditedNewest, filter: NoteFilter = .all) {
        self.sortOrder = sortOrder
        self.filter = filter
    }
}

/// Where those choices survive between visits.
///
/// A port rather than `UserDefaults` inside the package: the host decides where a preference
/// lives, and a package that wrote to the app's defaults suite would be writing into a container
/// it does not own. Nothing secret passes through here — a sort order says nothing about what the
/// notes contain — which is also why it is not the encrypted store's problem.
public protocol NoteListPreferencesStore: Sendable {
    func load() -> NoteListPreferences
    func save(_ preferences: NoteListPreferences)
}
