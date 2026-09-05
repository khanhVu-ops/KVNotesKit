import Foundation

public enum MarkdownToken: String, CaseIterable, Identifiable, Sendable {
    case heading1
    case heading2
    case heading3
    case bold
    case italic
    case strikethrough
    case bulletList
    case checklist
    case quote
    case inlineCode
    case secretBlock
    case thematicBreak

    public var id: String { rawValue }

    var wrapper: String? {
        switch self {
        case .bold: "**"
        case .italic: "*"
        case .strikethrough: "~~"
        case .inlineCode: "`"
        case .heading1, .heading2, .heading3, .bulletList, .checklist, .quote, .secretBlock,
             .thematicBreak: nil
        }
    }

    var linePrefix: String? {
        switch self {
        case .heading1: "# "
        case .heading2: "## "
        case .heading3: "### "
        case .bulletList: "- "
        case .checklist: "- [ ] "
        case .quote: "> "
        case .bold, .italic, .strikethrough, .inlineCode, .secretBlock, .thematicBreak: nil
        }
    }

    public var keyTitle: String {
        switch self {
        case .heading1: "H1"
        case .heading2: "H2"
        case .heading3: "H3"
        case .bold: "B"
        case .italic: "I"
        case .strikethrough: "S̶"
        case .bulletList: "•"
        case .checklist: "☑"
        case .quote: "❯"
        case .inlineCode: "`"
        case .secretBlock: "•••"
        case .thematicBreak: "—"
        }
    }
}

public enum MarkdownInsertion {
    public struct Result: Equatable, Sendable {
        public var text: String
        public var caretOffset: Int

        public init(text: String, caretOffset: Int) {
            self.text = text
            self.caretOffset = caretOffset
        }
    }

    public static func apply(
        _ token: MarkdownToken,
        to text: String,
        selection range: Range<Int>
    ) -> Result {
        let clamped = clamp(range, in: text)
        if let wrapper = token.wrapper { return wrap(text, range: clamped, with: wrapper) }
        if let prefix = token.linePrefix {
            return prefixLines(of: text, range: clamped, with: prefix)
        }
        if token == .secretBlock { return wrapInSecretFence(text, range: clamped) }
        return insertBlock("\n---\n", into: text, at: clamped)
    }

    private static func wrap(_ text: String, range: Range<Int>, with wrapper: String) -> Result {
        let start = index(text, range.lowerBound)
        let end = index(text, range.upperBound)
        let selected = String(text[start..<end])
        if selected.hasPrefix(wrapper), selected.hasSuffix(wrapper),
           selected.count >= wrapper.count * 2 {
            let stripped = String(selected.dropFirst(wrapper.count).dropLast(wrapper.count))
            var result = text
            result.replaceSubrange(start..<end, with: stripped)
            return Result(text: result, caretOffset: range.lowerBound + stripped.count)
        }
        var result = text
        result.replaceSubrange(start..<end, with: wrapper + selected + wrapper)
        let caret = selected.isEmpty
            ? range.lowerBound + wrapper.count
            : range.upperBound + wrapper.count * 2
        return Result(text: result, caretOffset: caret)
    }

    private static func prefixLines(
        of text: String,
        range: Range<Int>,
        with prefix: String
    ) -> Result {
        let lineStart = startOfLine(in: text, at: range.lowerBound)
        let existing = existingPrefixLength(in: text, atLineStart: lineStart)
        var result = text
        let insertAt = index(text, lineStart)
        if existing > 0 {
            let existingEnd = index(text, lineStart + existing)
            let current = String(text[insertAt..<existingEnd])
            if current == prefix {
                result.replaceSubrange(insertAt..<existingEnd, with: "")
                return Result(text: result, caretOffset: max(lineStart, range.upperBound - existing))
            }
            result.replaceSubrange(insertAt..<existingEnd, with: prefix)
            return Result(text: result, caretOffset: range.upperBound - existing + prefix.count)
        }
        result.insert(contentsOf: prefix, at: insertAt)
        return Result(text: result, caretOffset: range.upperBound + prefix.count)
    }

    /// Wraps the selection in a ```` ```secret ```` fence, keeping the selected text as the
    /// block's contents — the mask is a property of the note, so writing it means writing text.
    private static func wrapInSecretFence(_ text: String, range: Range<Int>) -> Result {
        let start = index(text, range.lowerBound)
        let end = index(text, range.upperBound)
        let selected = String(text[start..<end])
        let opening = "```\(NoteMarkdownBlock.secretFenceInfo)\n"
        let block = "\(opening)\(selected)\n```\n"
        var result = text
        result.replaceSubrange(start..<end, with: block)
        // The caret lands inside the fence, which is where the value goes when the selection was
        // empty and where an edit continues when it was not.
        return Result(text: result, caretOffset: range.lowerBound + opening.count + selected.count)
    }

    private static func insertBlock(
        _ block: String,
        into text: String,
        at range: Range<Int>
    ) -> Result {
        var result = text
        result.replaceSubrange(index(text, range.lowerBound)..<index(text, range.upperBound), with: block)
        return Result(text: result, caretOffset: range.lowerBound + block.count)
    }

    private static func index(_ text: String, _ offset: Int) -> String.Index {
        text.index(text.startIndex, offsetBy: min(max(offset, 0), text.count))
    }

    private static func clamp(_ range: Range<Int>, in text: String) -> Range<Int> {
        let lower = min(max(range.lowerBound, 0), text.count)
        return lower..<min(max(range.upperBound, lower), text.count)
    }

    private static func startOfLine(in text: String, at offset: Int) -> Int {
        var cursor = min(max(offset, 0), text.count)
        while cursor > 0 {
            if text[index(text, cursor - 1)].isNewline { break }
            cursor -= 1
        }
        return cursor
    }

    private static func existingPrefixLength(in text: String, atLineStart offset: Int) -> Int {
        // Longest first: on `- [ ] milk` the bullet marker also matches, and stripping only the
        // `- ` would leave the box behind as `[ ] milk`.
        let markers = ["- [ ] ", "- [x] ", "- [X] ", "### ", "## ", "# ", "> ", "- ", "* ", "+ "]
        let line = text[index(text, offset)...].prefix { !$0.isNewline }
        return markers.first(where: line.hasPrefix)?.count ?? 0
    }
}
