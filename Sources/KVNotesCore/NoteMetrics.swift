import Foundation

/// Calculated statistics and cryptographic storage metrics for a private note.
public struct NoteMetrics: Equatable, Sendable {
    /// Number of words in the note body.
    /// `nil` if the note is locked or body is withheld, to avoid leaking length.
    public let words: Int?

    /// Number of characters in the note body.
    /// `nil` if the note is locked or body is withheld.
    public let characters: Int?

    /// Number of lines in the note body.
    /// `nil` if the note is locked or body is withheld.
    public let lines: Int?

    /// Estimated on-disk encrypted size including 1 KiB block framing and zero-padding.
    public let storedBytes: Int

    /// Description of the cryptographic cipher used to seal the note in the vault.
    public let cipherDescription: String

    /// Date the note was created.
    public let createdAt: Date

    /// Date the note was last modified.
    public let lastEditedAt: Date

    /// Initializes metrics from the note's body content and lock state.
    ///
    /// When `isLocked` is true, body counts remain `nil` to prevent information leakage.
    public init(
        body: String?,
        isLocked: Bool,
        createdAt: Date,
        lastEditedAt: Date
    ) {
        self.createdAt = createdAt
        self.lastEditedAt = lastEditedAt
        self.cipherDescription = "AES-256-GCM"

        if isLocked || body == nil {
            self.words = nil
            self.characters = nil
            self.lines = nil
            self.storedBytes = 1024
        } else {
            let content = body ?? ""
            self.characters = content.count
            self.lines = content.isEmpty ? 0 : content.split(separator: "\n", omittingEmptySubsequences: false).count

            var wordCount = 0
            content.enumerateSubstrings(in: content.startIndex..<content.endIndex, options: [.byWords, .substringNotRequired]) { _, _, _, _ in
                wordCount += 1
            }
            self.words = wordCount

            // Payload framing: 5 bytes header (1 byte version + 4 bytes length) + UTF-8 content,
            // padded to the next 1 KiB (1024 bytes) boundary.
            let payloadBytes = 5 + content.utf8.count
            let blocks = max(1, (payloadBytes + 1023) / 1024)
            self.storedBytes = blocks * 1024
        }
    }

    /// Initializes metrics from a list digest where body is not loaded into memory.
    public init(digest: NoteDigest) {
        self.createdAt = digest.createdAt
        self.lastEditedAt = digest.lastEditedAt
        self.cipherDescription = "AES-256-GCM"

        if digest.requiresBiometricUnlock {
            self.words = nil
            self.characters = nil
            self.lines = nil
            self.storedBytes = 1024
        } else {
            self.words = nil
            self.characters = digest.characterCount
            self.lines = nil

            let payloadBytes = 5 + digest.characterCount
            let blocks = max(1, (payloadBytes + 1023) / 1024)
            self.storedBytes = blocks * 1024
        }
    }
}
