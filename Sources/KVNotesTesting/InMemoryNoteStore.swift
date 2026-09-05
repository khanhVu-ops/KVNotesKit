import Foundation
import KVNotesCore

public enum InMemoryNoteStoreError: Error, Equatable {
    case noteNotFound(NoteID)
}

/// An actor-backed store for package tests and previews. Plaintext lives in memory only and is
/// released with the store; production hosts must provide their encrypted implementation.
public actor InMemoryNoteStore: NoteStore {
    private var digests: [NoteID: NoteDigest]
    private var bodies: [NoteID: String]

    public init(notes: [NoteDigest] = [], bodies: [NoteID: String] = [:]) {
        self.digests = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        self.bodies = bodies
    }

    public func index() -> NoteIndex {
        let notes = digests.values.sorted { $0.lastEditedAt > $1.lastEditedAt }
        return NoteIndex(notes: notes)
    }

    public func body(_ id: NoteID) throws -> String {
        guard digests[id] != nil else { throw InMemoryNoteStoreError.noteNotFound(id) }
        return bodies[id, default: ""]
    }

    public func create(_ draft: NoteDraft) -> NoteDigest {
        let now = Date()
        let id = NoteID()
        let title = draft.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let digest = NoteDigest(
            id: id,
            title: title,
            snippet: draft.requiresBiometricUnlock ? nil : draft.body,
            characterCount: draft.body.count,
            folder: normalized(draft.folder),
            icon: draft.icon,
            requiresBiometricUnlock: draft.requiresBiometricUnlock,
            isTitleUserProvided: !title.isEmpty,
            createdAt: now,
            lastEditedAt: now
        )
        digests[id] = digest
        bodies[id] = draft.body
        return digest
    }

    public func update(_ id: NoteID, body: String, title: String?) throws -> NoteDigest {
        var digest = try requireDigest(id)
        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        digest.title = resolvedTitle
        digest.snippet = digest.requiresBiometricUnlock ? nil : body
        digest.characterCount = body.count
        digest.isTitleUserProvided = !resolvedTitle.isEmpty
        digest.lastEditedAt = Date()
        digests[id] = digest
        bodies[id] = body
        return digest
    }

    public func apply(_ patch: NoteAttributePatch, to id: NoteID) throws -> NoteDigest {
        var digest = try requireDigest(id)
        if case .set(let folder) = patch.folder { digest.folder = normalized(folder) }
        if case .set(let icon) = patch.icon { digest.icon = icon }
        if let locked = patch.requiresBiometricUnlock {
            digest.requiresBiometricUnlock = locked
            digest.snippet = locked ? nil : bodies[id]
        }
        if let pinned = patch.isPinned { digest.isPinned = pinned }
        digests[id] = digest
        return digest
    }

    public func discard(_ id: NoteID) throws {
        guard digests.removeValue(forKey: id) != nil else {
            throw InMemoryNoteStoreError.noteNotFound(id)
        }
        bodies.removeValue(forKey: id)
    }

    public func renameFolder(_ name: String, to newName: String) -> Int {
        let replacement = normalized(newName)
        var count = 0
        for id in digests.keys where digests[id]?.folder == name {
            digests[id]?.folder = replacement
            count += 1
        }
        return count
    }

    public func tintFolder(_ name: String, with tint: NoteFolderTint) -> Int {
        var count = 0
        for id in digests.keys where digests[id]?.folder == name {
            digests[id]?.folderTint = tint
            count += 1
        }
        return count
    }

    public func removeFolder(_ name: String) -> Int {
        var count = 0
        for id in digests.keys where digests[id]?.folder == name {
            digests[id]?.folder = nil
            digests[id]?.folderTint = .neutral
            count += 1
        }
        return count
    }

    private func requireDigest(_ id: NoteID) throws -> NoteDigest {
        guard let digest = digests[id] else { throw InMemoryNoteStoreError.noteNotFound(id) }
        return digest
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// A preferences store that forgets, for previews and for tests that assert the default view.
public final class InMemoryNoteListPreferences: NoteListPreferencesStore, @unchecked Sendable {
    private let lock = NSLock()
    private var preferences: NoteListPreferences

    public init(_ preferences: NoteListPreferences = NoteListPreferences()) {
        self.preferences = preferences
    }

    public func load() -> NoteListPreferences {
        lock.lock()
        defer { lock.unlock() }
        return preferences
    }

    public func save(_ preferences: NoteListPreferences) {
        lock.lock()
        defer { lock.unlock() }
        self.preferences = preferences
    }
}
