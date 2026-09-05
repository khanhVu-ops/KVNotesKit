import Foundation

public struct NoteTextSummary: Equatable, Sendable {
    public let title: String
    public let snippet: String
    public let characterCount: Int
    public let isTitleUserProvided: Bool
    /// Whether the note contains at least one Markdown task item.
    ///
    /// Derived here, at write time, because the list's *has checklist* filter must be answerable
    /// from metadata alone. Opening one content blob per note to answer it would decrypt the
    /// whole vault to draw one filter chip.
    public let hasChecklist: Bool
}

/// Pure Markdown-to-list derivation shared by the package UI and the host's persisted schema.
public enum NoteTextDerivation {
    public static let snippetLimit = 120
    public static let titleLimit = 80

    public static func summary(
        markdown: String,
        title: String?,
        requiresBiometricUnlock: Bool
    ) -> NoteTextSummary {
        let typedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isTitleUserProvided = !typedTitle.isEmpty
        let resolvedTitle: String
        if isTitleUserProvided {
            resolvedTitle = truncated(typedTitle, to: titleLimit)
        } else if requiresBiometricUnlock {
            resolvedTitle = ""
        } else {
            resolvedTitle = derivedTitle(from: markdown)
        }
        return NoteTextSummary(
            title: resolvedTitle,
            snippet: requiresBiometricUnlock ? "" : snippet(from: markdown, alreadyShowing: resolvedTitle),
            characterCount: markdown.count,
            isTitleUserProvided: isTitleUserProvided,
            hasChecklist: containsChecklist(markdown)
        )
    }

    /// A Markdown task item: a bullet marker, then `[ ]` or `[x]`, then a space.
    ///
    /// Deliberately strict about the trailing space so a note that merely mentions `- [x]` inside
    /// a sentence, or a line reading `- [draft]`, is not counted.
    public static func containsChecklist(_ markdown: String) -> Bool {
        markdown.components(separatedBy: .newlines).contains { NoteMarkdownBlock.boxRange(in: $0) != nil }
    }

    public static func normalizedFolder(_ folder: String?) -> String? {
        guard let trimmed = folder?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    public static func derivedTitle(from markdown: String) -> String {
        for line in markdown.split(whereSeparator: \.isNewline) {
            let plain = plainText(from: String(line))
            if !plain.isEmpty { return truncated(plain, to: titleLimit) }
        }
        return ""
    }

    public static func snippet(from markdown: String, alreadyShowing title: String = "") -> String {
        var lines = markdown.split(whereSeparator: \.isNewline).map(String.init)
        while let first = lines.first, plainText(from: first).isEmpty { lines.removeFirst() }
        if let first = lines.first {
            let plain = plainText(from: first)
            let trimmed = first.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || (!title.isEmpty && truncated(plain, to: titleLimit) == title) {
                lines.removeFirst()
            }
        }
        var parts: [String] = []
        var length = 0
        for line in lines {
            let plain = plainText(from: line)
            guard !plain.isEmpty else { continue }
            parts.append(plain)
            length += plain.count + 1
            if length > snippetLimit { break }
        }
        return truncated(parts.joined(separator: " "), to: snippetLimit)
    }

    public static func plainText(from line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("---") || text.hasPrefix("***") || text.hasPrefix("```") { return "" }
        while let first = text.first, first == "#" || first == ">" {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        for bullet in ["- [ ] ", "- [x] ", "- ", "* ", "+ "] where text.hasPrefix(bullet) {
            text.removeFirst(bullet.count)
            break
        }
        if let marker = orderedListMarkerLength(of: text) { text.removeFirst(marker) }
        for token in ["***", "**", "~~", "`", "*", "_"] {
            text = text.replacingOccurrences(of: token, with: "")
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func orderedListMarkerLength(of text: String) -> Int? {
        var digits = 0
        for character in text {
            if character.isNumber {
                digits += 1
                continue
            }
            guard digits > 0, character == "." || character == ")" else { return nil }
            let afterSeparator = text.index(text.startIndex, offsetBy: digits + 1)
            guard afterSeparator < text.endIndex, text[afterSeparator] == " " else { return nil }
            return digits + 2
        }
        return nil
    }

    private static func truncated(_ value: String, to limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit - 1)) + "…"
    }
}
