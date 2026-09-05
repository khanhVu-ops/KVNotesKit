import Foundation
import KVNotesCore

public enum NoteFixtures {
    private static let walletTitle = "Hardware wallet"
    private static let bankTitle = "Bank details"
    private static let journalTitle = "Friday journal"

    public static let wallet = NoteDigest(
        title: walletTitle,
        snippet: "Recovery phrase and device PIN",
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
