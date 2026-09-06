import Foundation

/// Determines how Return (`\n`) in the note editor handles Markdown lists, checklists, numbered lists,
/// and blockquotes.
///
/// Supports:
/// - Unordered bullets: `- `, `* `, `+ `
/// - Tasks / checklists: `- [ ] `, `- [x] `, `- [X] `, `* [ ] `, etc. (always continues as unchecked `[ ]`)
/// - Numbered lists: `1. `, `2) `, etc. (increments counter)
/// - Blockquotes: `> `, `>> `
/// - Preserves nested indentation (spaces, tabs)
/// - Outdents nested empty list items on Return
/// - Exits root empty list items on Return to a blank line
/// - Ignores Return inside code fences (```` ``` ````)
public enum MarkdownListContinuation {
    public struct Result: Equatable, Sendable {
        public var text: String
        public var caretOffset: Int

        public init(text: String, caretOffset: Int) {
            self.text = text
            self.caretOffset = caretOffset
        }
    }

    public enum ContinuationAction: Equatable, Sendable {
        /// A list was continued by inserting a newline and the next prefix.
        case continueList(Result)
        /// An empty indented item had its indentation reduced.
        case outdent(Result)
        /// An empty root item was cleared, exiting the list to a blank line.
        case exitList(Result)
        /// Not a list item or cursor in a position where continuation should not apply.
        case none
    }

    /// Evaluates whether pressing Return at the given selection/caret should continue a list,
    /// outdent an empty indented item, exit an empty list, or do nothing (standard newline).
    ///
    /// - Parameters:
    ///   - text: The full document text.
    ///   - selection: The current selection range (in character indices).
    /// - Returns: A `ContinuationAction` indicating what edit should take place.
    public static func evaluate(
        in text: String,
        selection: Range<Int>
    ) -> ContinuationAction {
        // Multi-character selection replaces selection with a plain newline.
        guard selection.lowerBound == selection.upperBound else { return .none }

        let caret = min(max(selection.lowerBound, 0), text.count)
        let caretIndex = text.index(text.startIndex, offsetBy: caret)

        // Find line boundaries
        var lineStartIndex = caretIndex
        while lineStartIndex > text.startIndex {
            let prev = text.index(before: lineStartIndex)
            if text[prev].isNewline { break }
            lineStartIndex = prev
        }

        var lineEndIndex = caretIndex
        while lineEndIndex < text.endIndex {
            if text[lineEndIndex].isNewline { break }
            lineEndIndex = text.index(after: lineEndIndex)
        }

        // Return inside code fences should not auto-continue lists.
        if isInsideCodeBlock(in: text, before: lineStartIndex) {
            return .none
        }

        let line = String(text[lineStartIndex..<lineEndIndex])
        guard let prefix = parsePrefix(in: line) else { return .none }

        let caretInLine = text.distance(from: lineStartIndex, to: caretIndex)
        // Cursor before or inside the prefix shouldn't auto-continue.
        guard caretInLine >= prefix.fullPrefix.count else { return .none }

        let contentAfterPrefix = line.dropFirst(prefix.fullPrefix.count).trimmingCharacters(in: .whitespaces)
        let isEmptyItem = contentAfterPrefix.isEmpty

        let lineStartOffset = text.distance(from: text.startIndex, to: lineStartIndex)

        if isEmptyItem {
            // Check quote outdent / exit
            if prefix.isQuote {
                if prefix.marker.count > 2 { // e.g. ">> " -> "> "
                    let reducedMarker = String(prefix.marker.dropFirst())
                    let newPrefix = prefix.indentation + reducedMarker
                    var resultText = text
                    resultText.replaceSubrange(lineStartIndex..<lineEndIndex, with: newPrefix)
                    let newCaret = lineStartOffset + newPrefix.count
                    return .outdent(Result(text: resultText, caretOffset: newCaret))
                } else {
                    var resultText = text
                    resultText.replaceSubrange(lineStartIndex..<lineEndIndex, with: "")
                    return .exitList(Result(text: resultText, caretOffset: lineStartOffset))
                }
            }

            // Indented list item: outdent by one indentation level
            if !prefix.indentation.isEmpty {
                let reducedIndentation = outdentedIndentation(from: prefix.indentation)
                let newPrefix = reducedIndentation + prefix.marker
                var resultText = text
                resultText.replaceSubrange(lineStartIndex..<lineEndIndex, with: newPrefix)
                let newCaret = lineStartOffset + newPrefix.count
                return .outdent(Result(text: resultText, caretOffset: newCaret))
            }

            // Root list item: clear the prefix and exit list to a blank line
            var resultText = text
            resultText.replaceSubrange(lineStartIndex..<lineEndIndex, with: "")
            return .exitList(Result(text: resultText, caretOffset: lineStartOffset))
        }

        // Line has content: continue list
        var head = String(text[lineStartIndex..<caretIndex])
        var tail = String(text[caretIndex..<lineEndIndex])

        if tail.hasPrefix(" ") {
            tail.removeFirst()
        } else if head.hasSuffix(" ") && head.count > prefix.fullPrefix.count {
            head.removeLast()
        }

        let nextPrefix = prefix.indentation + prefix.nextMarker
        let replacement = head + "\n" + nextPrefix + tail
        var resultText = text
        resultText.replaceSubrange(lineStartIndex..<lineEndIndex, with: replacement)

        let newCaret = lineStartOffset + head.count + 1 + nextPrefix.count
        return .continueList(Result(text: resultText, caretOffset: newCaret))
    }

    /// Convenience helper returning the updated `Result` if Return should continue, outdent,
    /// or exit a list, or `nil` if standard newline behavior should occur.
    public static func continueOrExitList(
        in text: String,
        selection: Range<Int>
    ) -> Result? {
        switch evaluate(in: text, selection: selection) {
        case .continueList(let result), .outdent(let result), .exitList(let result):
            return result
        case .none:
            return nil
        }
    }

    // MARK: - Prefix Parsing

    private struct ParsedPrefix {
        var indentation: String
        var marker: String
        var nextMarker: String
        var isQuote: Bool = false
        var fullPrefix: String { indentation + marker }
    }

    private static func parsePrefix(in line: String) -> ParsedPrefix? {
        // 1. Task / Checklist (e.g. "- [ ] ", "- [x] ", "  * [X] ")
        if let box = NoteMarkdownBlock.boxRange(in: line) {
            var idx = line.startIndex
            while idx < line.endIndex, line[idx] == " " || line[idx] == "\t" {
                idx = line.index(after: idx)
            }
            let indentation = String(line[line.startIndex..<idx])
            guard idx < line.endIndex else { return nil }
            let bulletChar = line[idx]
            let closingSpace = line.index(after: box.upperBound)
            guard closingSpace < line.endIndex else { return nil }
            let marker = String(line[idx...closingSpace])
            let nextMarker = "\(bulletChar) [ ] "
            return ParsedPrefix(
                indentation: indentation,
                marker: marker,
                nextMarker: nextMarker
            )
        }

        // Leading whitespace for all other types
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == " " || line[idx] == "\t" {
            idx = line.index(after: idx)
        }
        let indentation = String(line[line.startIndex..<idx])
        guard idx < line.endIndex else { return nil }

        // 2. Unordered bullets ("- ", "* ", "+ ")
        if "-*+".contains(line[idx]) {
            let next = line.index(after: idx)
            if next < line.endIndex, line[next] == " " {
                let marker = String(line[idx...next])
                return ParsedPrefix(
                    indentation: indentation,
                    marker: marker,
                    nextMarker: marker
                )
            }
        }

        // 3. Numbered lists ("1. ", "2) ")
        if line[idx].isNumber {
            let digitsStart = idx
            while idx < line.endIndex, line[idx].isNumber {
                idx = line.index(after: idx)
            }
            if idx < line.endIndex, line[idx] == "." || line[idx] == ")" {
                let delim = line[idx]
                let spaceIdx = line.index(after: idx)
                if spaceIdx < line.endIndex, line[spaceIdx] == " " {
                    let digitsStr = String(line[digitsStart..<idx])
                    if let number = Int(digitsStr), number < 1_000_000_000 {
                        let marker = String(line[digitsStart...spaceIdx])
                        let nextMarker = "\(number + 1)\(delim) "
                        return ParsedPrefix(
                            indentation: indentation,
                            marker: marker,
                            nextMarker: nextMarker
                        )
                    }
                }
            }
        }

        // 4. Blockquotes ("> ", ">> ")
        if line[idx] == ">" {
            let quoteStart = idx
            while idx < line.endIndex, line[idx] == ">" {
                idx = line.index(after: idx)
            }
            if idx < line.endIndex, line[idx] == " " {
                let marker = String(line[quoteStart...idx])
                return ParsedPrefix(
                    indentation: indentation,
                    marker: marker,
                    nextMarker: marker,
                    isQuote: true
                )
            } else if idx == line.endIndex {
                let marker = String(line[quoteStart..<idx]) + " "
                return ParsedPrefix(
                    indentation: indentation,
                    marker: marker,
                    nextMarker: marker,
                    isQuote: true
                )
            }
        }

        return nil
    }

    private static func outdentedIndentation(from indentation: String) -> String {
        if indentation.hasPrefix("\t") {
            return String(indentation.dropFirst())
        } else if indentation.hasPrefix("  ") {
            return String(indentation.dropFirst(2))
        } else if indentation.hasPrefix(" ") {
            return String(indentation.dropFirst(1))
        }
        return ""
    }

    private static func isInsideCodeBlock(in text: String, before lineStart: String.Index) -> Bool {
        guard text.contains("```") else { return false }
        let preceding = text[..<lineStart]
        var count = 0
        for rawLine in preceding.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                count += 1
            }
        }
        return count % 2 == 1
    }
}
