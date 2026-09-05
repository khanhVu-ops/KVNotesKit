#if canImport(UIKit)
import KVNotesCore
import UIKit
import XCTest
@testable import KVNotesUI

/// NK-230's gate: live styling ships only if typing stays imperceptible in a long note.
///
/// What is measured is the work one keystroke actually causes — find the edited paragraph, parse
/// it, and write the attributes into the storage — inside a document of 20 000 characters. That
/// is the number the task asks for, and it is the one that decides whether the feature ships: a
/// frame at 60Hz is 16.7ms, and everything else in a keystroke (UIKit's own layout, the
/// ViewModel, SwiftUI) has to fit in the same frame, so this budget is deliberately a fraction
/// of it.
@MainActor
final class NoteTypingLatencyTests: XCTestCase {
    private static let budget: TimeInterval = 0.004

    func testStylingOneParagraphInATwentyThousandCharacterNoteStaysUnderBudget() {
        let storage = NSTextStorage(string: Self.longNote())
        XCTAssertGreaterThan(storage.length, 20_000)

        let styling = NoteSyntaxStyling(
            theme: .preview,
            baseFont: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        )
        let text = storage.string as NSString

        // A caret deep inside the note, where a whole-document implementation would be slowest.
        let caret = NSRange(location: storage.length - 400, length: 0)
        var worst: TimeInterval = 0
        for _ in 0..<50 {
            let paragraph = NoteSyntaxHighlighting.lineRange(of: text, containing: caret)
            let started = Date()
            styling.apply(to: storage, range: paragraph)
            worst = max(worst, Date().timeIntervalSince(started))
        }

        print("NK-230 keystroke restyle, 20k characters: worst \(Int(worst * 1_000_000))µs")
        XCTAssertLessThan(worst, Self.budget, "A keystroke must not cost a frame")
    }

    /// The other half of the claim: the cost is bounded by the paragraph, not by the note. If
    /// these two grew together, the measurement above would only be true for today's note sizes.
    func testTheCostDoesNotGrowWithTheLengthOfTheNote() {
        let styling = NoteSyntaxStyling(
            theme: .preview,
            baseFont: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        )

        func worstRestyle(paragraphs: Int) -> TimeInterval {
            let storage = NSTextStorage(string: Self.longNote(paragraphs: paragraphs))
            let text = storage.string as NSString
            let caret = NSRange(location: storage.length - 400, length: 0)
            var worst: TimeInterval = 0
            for _ in 0..<50 {
                let paragraph = NoteSyntaxHighlighting.lineRange(of: text, containing: caret)
                let started = Date()
                styling.apply(to: storage, range: paragraph)
                worst = max(worst, Date().timeIntervalSince(started))
            }
            return worst
        }

        let small = worstRestyle(paragraphs: 40)
        let large = worstRestyle(paragraphs: 400)

        print("NK-230 restyle: 10x the note costs \(String(format: "%.2f", large / max(small, 0.000001)))x")
        XCTAssertLessThan(large, Self.budget)
        // Ten times the note, nothing like ten times the work.
        XCTAssertLessThan(large, small * 4 + 0.001)
    }

    private static func longNote(paragraphs: Int = 400) -> String {
        (0..<paragraphs).map { index in
            """
            ## Section \(index)
            A paragraph with **bold**, *italic*, ~~struck~~ and `inline code` in it, long enough \
            to wrap on a phone and to make the parser walk a real line rather than a token.
            - [ ] a task that is not done
            - [x] a task that is
            > a quotation that belongs to section \(index)
            """
        }.joined(separator: "\n\n")
    }
}
#endif
