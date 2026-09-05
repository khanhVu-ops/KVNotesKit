import Foundation

/// One run of the note that should be drawn differently from plain body text.
public struct NoteStyleSpan: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case heading(level: Int)
        case quote
        case bold
        case italic
        case strikethrough
        case inlineCode
        case taskMarker(isDone: Bool)
        /// The Markdown characters themselves. Dimmed rather than hidden: hiding them makes the
        /// caret jump over glyphs that are not there, which is the classic way a "live preview"
        /// editor becomes impossible to edit in.
        case syntax
    }

    public let kind: Kind
    public let range: NSRange

    public init(kind: Kind, range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

/// Finds the runs to style, for one span of the document rather than for all of it.
///
/// **The whole design constraint is that this runs on the keystroke path.** Restyling a whole
/// note on every character is the classic source of typing lag, so the editor asks only for the
/// paragraph it just changed plus whatever is on screen, and this type is built to answer that
/// question in isolation: it takes a range, scans only the lines that intersect it, and returns
/// absolute ranges the caller can apply directly.
///
/// It works in UTF-16 offsets throughout — the unit `NSTextStorage` uses — so nothing has to be
/// converted per keystroke.
public enum NoteSyntaxHighlighting {
    /// Delimiter pairs, longest first: `**` has to be tried before `*`, or every bold run reads
    /// as two empty italics.
    private static let inlinePairs: [(marker: String, kind: NoteStyleSpan.Kind)] = [
        ("**", .bold),
        ("~~", .strikethrough),
        ("`", .inlineCode),
        ("*", .italic)
    ]

    public static func spans(in text: NSString, range: NSRange) -> [NoteStyleSpan] {
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard safe.length > 0 else { return [] }

        var spans: [NoteStyleSpan] = []
        text.enumerateSubstrings(in: safe, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            appendLineSpans(of: text, lineRange: lineRange, into: &spans)
        }
        return spans
    }

    /// The paragraph-shaped unit the editor restyles after an edit: the lines the change touched.
    public static func lineRange(of text: NSString, containing range: NSRange) -> NSRange {
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        return text.lineRange(for: safe.length == 0 ? NSRange(location: min(range.location, text.length), length: 0) : safe)
    }

    private static func appendLineSpans(
        of text: NSString,
        lineRange: NSRange,
        into spans: inout [NoteStyleSpan]
    ) {
        let line = text.substring(with: lineRange) as NSString
        var contentStart = 0
        while contentStart < line.length, isSpace(line.character(at: contentStart)) {
            contentStart += 1
        }
        let start = lineRange.location + contentStart

        if let level = headingLevel(of: line, from: contentStart) {
            let markerLength = level + 1
            spans.append(NoteStyleSpan(kind: .syntax, range: NSRange(location: start, length: markerLength)))
            let bodyStart = start + markerLength
            let bodyLength = max(0, lineRange.location + lineRange.length - bodyStart)
            spans.append(NoteStyleSpan(
                kind: .heading(level: level),
                range: NSRange(location: bodyStart, length: bodyLength)
            ))
        } else if isQuote(line, from: contentStart) {
            spans.append(NoteStyleSpan(kind: .syntax, range: NSRange(location: start, length: 2)))
            let bodyStart = start + 2
            spans.append(NoteStyleSpan(
                kind: .quote,
                range: NSRange(location: bodyStart, length: max(0, lineRange.location + lineRange.length - bodyStart))
            ))
        } else if let task = taskMarker(in: line, from: contentStart) {
            spans.append(NoteStyleSpan(
                kind: .taskMarker(isDone: task.isDone),
                range: NSRange(location: start, length: task.length)
            ))
        } else if isBullet(line, from: contentStart) {
            spans.append(NoteStyleSpan(kind: .syntax, range: NSRange(location: start, length: 2)))
        }

        appendInlineSpans(of: line, lineOrigin: lineRange.location, into: &spans)
    }

    /// Scans one line once, left to right, for the delimiter pairs.
    ///
    /// A regular expression per pair per keystroke is what this avoids: four passes with a
    /// compiled pattern over every visible line costs more than the edit that triggered it.
    private static func appendInlineSpans(
        of line: NSString,
        lineOrigin: Int,
        into spans: inout [NoteStyleSpan]
    ) {
        var index = 0
        while index < line.length {
            guard let pair = inlinePairs.first(where: { matches($0.marker, in: line, at: index) }) else {
                index += 1
                continue
            }
            let markerLength = (pair.marker as NSString).length
            let contentStart = index + markerLength
            guard contentStart < line.length,
                  let closing = closingIndex(of: pair.marker, in: line, from: contentStart)
            else {
                index += markerLength
                continue
            }

            spans.append(NoteStyleSpan(
                kind: .syntax,
                range: NSRange(location: lineOrigin + index, length: markerLength)
            ))
            spans.append(NoteStyleSpan(
                kind: pair.kind,
                range: NSRange(location: lineOrigin + contentStart, length: closing - contentStart)
            ))
            spans.append(NoteStyleSpan(
                kind: .syntax,
                range: NSRange(location: lineOrigin + closing, length: markerLength)
            ))
            index = closing + markerLength
        }
    }

    private static func closingIndex(of marker: String, in line: NSString, from start: Int) -> Int? {
        let markerLength = (marker as NSString).length
        var index = start
        while index + markerLength <= line.length {
            if matches(marker, in: line, at: index) {
                // An empty run (`****`) is not emphasis, it is four characters the author typed.
                return index > start ? index : nil
            }
            index += 1
        }
        return nil
    }

    private static func matches(_ marker: String, in line: NSString, at index: Int) -> Bool {
        let markerCharacters = marker.utf16.map { $0 }
        guard index + markerCharacters.count <= line.length else { return false }
        for (offset, character) in markerCharacters.enumerated()
        where line.character(at: index + offset) != character {
            return false
        }
        return true
    }

    private static func headingLevel(of line: NSString, from start: Int) -> Int? {
        var hashes = 0
        var index = start
        while index < line.length, line.character(at: index) == 0x23 { // #
            hashes += 1
            index += 1
        }
        guard (1...3).contains(hashes), index < line.length, isSpace(line.character(at: index)) else {
            return nil
        }
        return hashes
    }

    private static func isQuote(_ line: NSString, from start: Int) -> Bool {
        start + 1 < line.length && line.character(at: start) == 0x3E && isSpace(line.character(at: start + 1))
    }

    private static func isBullet(_ line: NSString, from start: Int) -> Bool {
        guard start + 1 < line.length else { return false }
        let marker = line.character(at: start)
        return (marker == 0x2D || marker == 0x2A || marker == 0x2B) && isSpace(line.character(at: start + 1))
    }

    private static func taskMarker(in line: NSString, from start: Int) -> (isDone: Bool, length: Int)? {
        guard isBullet(line, from: start), start + 5 < line.length else { return nil }
        var index = start + 1
        while index < line.length, isSpace(line.character(at: index)) { index += 1 }
        guard index + 3 < line.length, line.character(at: index) == 0x5B else { return nil } // [
        let box = line.character(at: index + 1)
        guard box == 0x20 || box == 0x78 || box == 0x58 else { return nil } // space, x, X
        guard line.character(at: index + 2) == 0x5D, isSpace(line.character(at: index + 3)) else {
            return nil
        }
        return (box != 0x20, index + 4 - start)
    }

    private static func isSpace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09
    }
}
