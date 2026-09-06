import Foundation

/// Handles auto-pairing brackets/quotes, smart-wrapping selections, skipping over closing
/// punctuation, and pair deletion on Backspace.
public enum MarkdownAutoPairing {
    public struct Result: Equatable, Sendable {
        public var text: String
        public var caretOffset: Int
        public var selectedRange: Range<Int>

        public init(text: String, caretOffset: Int) {
            self.text = text
            self.caretOffset = caretOffset
            self.selectedRange = caretOffset..<caretOffset
        }

        public init(text: String, selectedRange: Range<Int>) {
            self.text = text
            self.caretOffset = selectedRange.upperBound
            self.selectedRange = selectedRange
        }
    }

    private static let bracketPairs: [(open: Character, close: Character)] = [
        ("(", ")"),
        ("[", "]"),
        ("{", "}"),
        ("\"", "\""),
        ("`", "`")
    ]

    private static let wrappingSymbols: [Character: (open: String, close: String)] = [
        "(": ("(", ")"),
        ")": ("(", ")"),
        "[": ("[", "]"),
        "]": ("[", "]"),
        "{": ("{", "}"),
        "}": ("{", "}"),
        "\"": ("\"", "\""),
        "`": ("`", "`"),
        "*": ("*", "*"),
        "~": ("~", "~"),
        "_": ("_", "_")
    ]

    /// Evaluates a typed character.
    ///
    /// - Returns: An updated `Result` if auto-pairing, smart-wrapping, or skip-over occurred,
    ///   or `nil` if standard typing should proceed.
    public static func handleTyping(
        _ string: String,
        in text: String,
        selection range: Range<Int>
    ) -> Result? {
        guard string.count == 1, let char = string.first else { return nil }

        let clamped = clamp(range, in: text)

        // 1. Selection > 0: Smart wrapping
        if clamped.lowerBound < clamped.upperBound {
            guard let pair = wrappingSymbols[char] else { return nil }
            let start = index(text, clamped.lowerBound)
            let end = index(text, clamped.upperBound)
            let selected = String(text[start..<end])

            var result = text
            let replacement = pair.open + selected + pair.close
            result.replaceSubrange(start..<end, with: replacement)

            // Place caret right after the closing wrapper
            let newCaret = clamped.lowerBound + replacement.count
            return Result(text: result, caretOffset: newCaret)
        }

        // 2. Selection == 0: Caret typing
        let caret = clamped.lowerBound
        let caretIndex = index(text, caret)

        // 2a. Skip-over existing closing character
        if caretIndex < text.endIndex, text[caretIndex] == char {
            let isClosing = bracketPairs.contains { $0.close == char }
            if isClosing {
                // Caret simply moves over the existing closing character
                return Result(text: text, caretOffset: caret + 1)
            }
        }

        // 2b. Auto-pair opening bracket / quote
        if let pair = bracketPairs.first(where: { $0.open == char }) {
            // For quotes and backticks, only auto-close if followed by whitespace, newline, closing bracket, or end of line.
            if char == "\"" || char == "`" {
                if caretIndex < text.endIndex {
                    let nextChar = text[caretIndex]
                    let allowedFollowers: [Character] = [" ", "\t", "\n", "\r", ")", "]", "}", ",", ".", ";"]
                    guard allowedFollowers.contains(nextChar) else { return nil }
                }
            }

            var result = text
            let pairString = String([pair.open, pair.close])
            result.insert(contentsOf: pairString, at: caretIndex)

            // Caret lands between the pair
            return Result(text: result, caretOffset: caret + 1)
        }

        return nil
    }

    /// Evaluates Backspace when deleting 1 character at caret.
    ///
    /// - Returns: An updated `Result` deleting both characters if caret was between an empty pair,
    ///   or `nil` if standard Backspace should proceed.
    public static func handleBackspace(
        in text: String,
        selection range: Range<Int>
    ) -> Result? {
        guard range.lowerBound == range.upperBound, range.lowerBound > 0 else { return nil }
        let caret = range.lowerBound
        guard caret < text.count else { return nil }

        let prevIndex = index(text, caret - 1)
        let nextIndex = index(text, caret)

        let prevChar = text[prevIndex]
        let nextChar = text[nextIndex]

        let isPair = bracketPairs.contains { $0.open == prevChar && $0.close == nextChar }
        guard isPair else { return nil }

        // Delete both characters
        var result = text
        let afterNext = text.index(after: nextIndex)
        result.replaceSubrange(prevIndex..<afterNext, with: "")

        return Result(text: result, caretOffset: caret - 1)
    }

    // MARK: - Helpers

    private static func index(_ text: String, _ offset: Int) -> String.Index {
        text.index(text.startIndex, offsetBy: min(max(offset, 0), text.count))
    }

    private static func clamp(_ range: Range<Int>, in text: String) -> Range<Int> {
        let lower = min(max(range.lowerBound, 0), text.count)
        return lower..<min(max(range.upperBound, lower), text.count)
    }
}
