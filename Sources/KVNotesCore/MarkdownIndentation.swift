import Foundation

/// Handles indenting and outdenting lines or selections in Markdown text by 2 spaces.
public enum MarkdownIndentation {
    public struct Result: Equatable, Sendable {
        public var text: String
        public var selectedRange: Range<Int>

        public init(text: String, selectedRange: Range<Int>) {
            self.text = text
            self.selectedRange = selectedRange
        }

        public var caretOffset: Int { selectedRange.upperBound }
    }

    /// Indents the line(s) intersecting `range` by 2 spaces.
    public static func indent(
        in text: String,
        selection range: Range<Int>
    ) -> Result {
        let clamped = clamp(range, in: text)
        let linesInfo = findLines(in: text, range: clamped)

        var newLines = linesInfo.lines
        var deltaBeforeLower = 0
        var totalDelta = 0

        for i in 0..<newLines.count {
            newLines[i] = "  " + newLines[i]
            if i == 0 { deltaBeforeLower += 2 }
            totalDelta += 2
        }

        var resultText = text
        resultText.replaceSubrange(linesInfo.fullRange, with: newLines.joined(separator: "\n"))

        let isCursor = clamped.lowerBound == clamped.upperBound
        let newLower = clamped.lowerBound + deltaBeforeLower
        let newUpper = isCursor ? newLower : clamped.upperBound + totalDelta

        return Result(text: resultText, selectedRange: newLower..<max(newLower, newUpper))
    }

    /// Outdents the line(s) intersecting `range` by removing up to 2 spaces (or 1 tab).
    public static func outdent(
        in text: String,
        selection range: Range<Int>
    ) -> Result {
        let clamped = clamp(range, in: text)
        let linesInfo = findLines(in: text, range: clamped)

        var newLines = linesInfo.lines
        var deltaFirstLine = 0
        var totalDelta = 0

        for i in 0..<newLines.count {
            let line = newLines[i]
            let removed: Int
            if line.hasPrefix("\t") {
                newLines[i] = String(line.dropFirst())
                removed = 1
            } else if line.hasPrefix("  ") {
                newLines[i] = String(line.dropFirst(2))
                removed = 2
            } else if line.hasPrefix(" ") {
                newLines[i] = String(line.dropFirst())
                removed = 1
            } else {
                removed = 0
            }

            if i == 0 { deltaFirstLine = removed }
            totalDelta += removed
        }

        guard totalDelta > 0 else {
            return Result(text: text, selectedRange: clamped)
        }

        var resultText = text
        resultText.replaceSubrange(linesInfo.fullRange, with: newLines.joined(separator: "\n"))

        let isCursor = clamped.lowerBound == clamped.upperBound
        let firstLineStart = text.distance(from: text.startIndex, to: linesInfo.fullRange.lowerBound)
        let newLower = max(firstLineStart, clamped.lowerBound - deltaFirstLine)
        let newUpper = isCursor ? newLower : max(newLower, clamped.upperBound - totalDelta)

        return Result(text: resultText, selectedRange: newLower..<max(newLower, newUpper))
    }

    // MARK: - Helpers

    private struct LinesInfo {
        var lines: [String]
        var fullRange: Range<String.Index>
    }

    private static func findLines(in text: String, range: Range<Int>) -> LinesInfo {
        let start = index(text, range.lowerBound)
        var end = index(text, range.upperBound)

        // If selection ends right at a newline, exclude the following empty line unless selection is empty
        if range.upperBound > range.lowerBound, end > text.startIndex {
            let prev = text.index(before: end)
            if text[prev].isNewline {
                end = prev
            }
        }

        // Find line start
        var lineStart = start
        while lineStart > text.startIndex {
            let prev = text.index(before: lineStart)
            if text[prev].isNewline { break }
            lineStart = prev
        }

        // Find line end
        var lineEnd = end
        while lineEnd < text.endIndex {
            if text[lineEnd].isNewline { break }
            lineEnd = text.index(after: lineEnd)
        }

        let slice = String(text[lineStart..<lineEnd])
        let lines = slice.components(separatedBy: .newlines)
        return LinesInfo(lines: lines, fullRange: lineStart..<lineEnd)
    }

    private static func index(_ text: String, _ offset: Int) -> String.Index {
        text.index(text.startIndex, offsetBy: min(max(offset, 0), text.count))
    }

    private static func clamp(_ range: Range<Int>, in text: String) -> Range<Int> {
        let lower = min(max(range.lowerBound, 0), text.count)
        return lower..<min(max(range.upperBound, lower), text.count)
    }
}
