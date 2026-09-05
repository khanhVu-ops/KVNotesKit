import Foundation

public protocol NoteStore: Sendable {
    func index() async throws -> NoteIndex
    func body(_ id: NoteID) async throws -> String
    func create(_ draft: NoteDraft) async throws -> NoteDigest
    func update(_ id: NoteID, body: String, title: String?) async throws -> NoteDigest
    func apply(_ patch: NoteAttributePatch, to id: NoteID) async throws -> NoteDigest
    func discard(_ id: NoteID) async throws
    func renameFolder(_ name: String, to newName: String) async throws -> Int
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
