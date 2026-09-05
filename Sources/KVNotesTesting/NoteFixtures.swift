import Foundation
import KVNotesCore

public enum NoteFixtures {
    private static let walletTitle = "Hardware wallet"
    private static let bankTitle = "Bank details"
    private static let journalTitle = "Friday journal"

    /// The locked one, and it carries no snippet — which is the point of it.
    ///
    /// It used to hold "Recovery phrase and device PIN", a state no store can produce since
    /// NK-001: the host withholds a locked note's snippet on the way out. A fixture that models
    /// an impossible state is worse than no fixture, because the preview of a locked row drew
    /// real text instead of the redaction bars a person would actually see.
    public static let wallet = NoteDigest(
        title: walletTitle,
        snippet: nil,
        characterCount: 148,
        folder: "Passwords",
        icon: "🔑",
        requiresBiometricUnlock: true,
        isTitleUserProvided: true,
        isPinned: true,
        createdAt: Date().addingTimeInterval(-86_400),
        lastEditedAt: Date().addingTimeInterval(-180)
    )

    public static let bank = NoteDigest(
        title: bankTitle,
        snippet: "Account and transfer details",
        characterCount: 94,
        folder: "Banking",
        icon: "🏦",
        isTitleUserProvided: true,
        createdAt: Date().addingTimeInterval(-172_800),
        lastEditedAt: Date().addingTimeInterval(-7_200)
    )

    public static let journal = NoteDigest(
        title: journalTitle,
        snippet: "A quiet afternoon and a long walk home.",
        characterCount: 320,
        createdAt: Date().addingTimeInterval(-400_000),
        lastEditedAt: Date().addingTimeInterval(-200_000)
    )

    public static let all = [wallet, bank, journal]
    public static let bodies: [NoteID: String] = [
        wallet.id: "# Hardware wallet\n\nRecovery phrase and device PIN",
        bank.id: "# Bank details\n\nAccount and transfer details",
        journal.id: "# Friday journal\n\nA quiet afternoon and a long walk home."
    ]
}
