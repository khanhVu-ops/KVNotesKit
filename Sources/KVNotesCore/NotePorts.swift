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
    public var layout: NoteListLayout

    public init(
        sortOrder: NoteSortOrder = .lastEditedNewest,
        filter: NoteFilter = .all,
        layout: NoteListLayout = .list
    ) {
        self.sortOrder = sortOrder
        self.filter = filter
        self.layout = layout
    }

    /// Decoded by hand so that a blob written before a key existed still yields the choices it
    /// does carry.
    ///
    /// The synthesised initialiser throws on a missing key rather than falling back to the
    /// property's default, and every caller of this type reads it through `try?` — so adding one
    /// field would have silently reset the sort order and the filter of everyone who upgraded.
    /// A preference that resets itself on upgrade is indistinguishable from one that does not
    /// persist at all.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sortOrder = try container.decodeIfPresent(NoteSortOrder.self, forKey: .sortOrder) ?? .lastEditedNewest
        filter = try container.decodeIfPresent(NoteFilter.self, forKey: .filter) ?? .all
        layout = try container.decodeIfPresent(NoteListLayout.self, forKey: .layout) ?? .list
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
