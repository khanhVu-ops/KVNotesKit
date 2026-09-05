#if canImport(UIKit)
import KVNotesCore
import UIKit

/// Paints the Markdown the user is typing, one range at a time.
///
/// Scoped by design, not by optimisation: the editor asks for the paragraph an edit touched and
/// for what is on screen, never for the document. A note is one `NSTextStorage`, and restyling
/// all of it per keystroke is the difference between an editor that keeps up with a thumb and
/// one that does not.
///
/// Every attribute dictionary is built once, in `init`. The first version of this type derived a
/// `UIFont` and converted a SwiftUI `Color` to `UIColor` per span, per keystroke; measured at
/// 20 000 characters that cost 4.0ms a keystroke, which is a quarter of a frame spent on work
/// whose answer never changes. Building them up front took the same measurement to well under a
/// millisecond — see `NoteTypingLatencyTests`.
@MainActor
final class NoteSyntaxStyling {
    /// Extra characters styled either side of the visible rectangle, so a fast flick does not
    /// show a band of unstyled text before the next pass catches up.
    static let visibleMargin = 2_000

    let baseFont: UIFont
    private let base: [NSAttributedString.Key: Any]
    private let headings: [Int: [NSAttributedString.Key: Any]]
    private let quote: [NSAttributedString.Key: Any]
    private let bold: [NSAttributedString.Key: Any]
    private let italic: [NSAttributedString.Key: Any]
    private let strikethrough: [NSAttributedString.Key: Any]
    private let inlineCode: [NSAttributedString.Key: Any]
    private let taskDone: [NSAttributedString.Key: Any]
    private let taskOpen: [NSAttributedString.Key: Any]
    private let syntax: [NSAttributedString.Key: Any]
    private let match: [NSAttributedString.Key: Any]
    private let currentMatch: [NSAttributedString.Key: Any]

    init(theme: NoteTheme, baseFont: UIFont) {
        self.baseFont = baseFont
        let primary = UIColor(theme.primaryText)
        let secondary = UIColor(theme.secondaryText)
        let dimmed = UIColor(theme.disabledText)
        let accent = UIColor(theme.accent)
        let codeBackground = UIColor(theme.elevatedCard)

        base = [
            .font: baseFont,
            .foregroundColor: primary,
            .backgroundColor: UIColor.clear,
            .strikethroughStyle: 0
        ]
        headings = [
            1: [.font: Self.scaled(baseFont, by: 1.45, traits: .traitBold), .foregroundColor: primary],
            2: [.font: Self.scaled(baseFont, by: 1.25, traits: .traitBold), .foregroundColor: primary],
            3: [.font: Self.scaled(baseFont, by: 1.12, traits: .traitBold), .foregroundColor: primary]
        ]
        quote = [.font: Self.scaled(baseFont, by: 1, traits: .traitItalic), .foregroundColor: secondary]
        bold = [.font: Self.scaled(baseFont, by: 1, traits: .traitBold)]
        italic = [.font: Self.scaled(baseFont, by: 1, traits: .traitItalic)]
        strikethrough = [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: secondary
        ]
        inlineCode = [.backgroundColor: codeBackground, .foregroundColor: primary]
        taskDone = [.foregroundColor: accent]
        taskOpen = [.foregroundColor: secondary]
        // Dimmed, never hidden. Hiding the markers makes the caret step over glyphs that are not
        // drawn, and selection stops matching what the eye sees.
        syntax = [.foregroundColor: dimmed]
        // Find highlights sit on top of syntax styling rather than replacing it: a match inside a
        // heading is still a heading, and losing that while searching makes the note look like a
        // different note.
        match = [.backgroundColor: accent.withAlphaComponent(0.22)]
        currentMatch = [.backgroundColor: accent, .foregroundColor: UIColor(theme.onAccent)]
    }

    var typingAttributes: [NSAttributedString.Key: Any] { base }

    /// Applies styling to `range` and leaves the rest of the storage untouched.
    ///
    /// `matches` and `current` are the find results; only the ones intersecting `range` cost
    /// anything, so highlighting a search in a long note is still a per-paragraph operation.
    func apply(
        to storage: NSTextStorage,
        range: NSRange,
        matches: [NSRange] = [],
        current: NSRange? = nil
    ) {
        let text = storage.string as NSString
        let target = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard target.length > 0 else { return }

        storage.beginEditing()
        storage.setAttributes(base, range: target)
        for span in NoteSyntaxHighlighting.spans(in: text, range: target) {
            let clipped = NSIntersectionRange(span.range, target)
            guard clipped.length > 0 else { continue }
            storage.addAttributes(attributes(for: span.kind), range: clipped)
        }
        for found in matches {
            let clipped = NSIntersectionRange(found, target)
            guard clipped.length > 0 else { continue }
            storage.addAttributes(found == current ? currentMatch : match, range: clipped)
        }
        storage.endEditing()
    }

    private func attributes(for kind: NoteStyleSpan.Kind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .heading(let level): headings[level] ?? headings[3] ?? base
        case .quote: quote
        case .bold: bold
        case .italic: italic
        case .strikethrough: strikethrough
        case .inlineCode: inlineCode
        case .taskMarker(let isDone): isDone ? taskDone : taskOpen
        case .syntax: syntax
        }
    }

    private static func scaled(
        _ font: UIFont,
        by factor: CGFloat,
        traits: UIFontDescriptor.SymbolicTraits
    ) -> UIFont {
        let size = font.pointSize * factor
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else {
            return font.withSize(size)
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}
#endif
