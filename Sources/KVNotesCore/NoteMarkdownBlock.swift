import Foundation

/// The blocks read mode draws. Unsupported lines remain paragraphs so authored text never
/// disappears merely because the renderer does not understand its syntax.
public enum NoteMarkdownBlock: Equatable, Sendable {
    /// A Markdown task item, and the line of the source it came from.
    ///
    /// The line index is what makes read mode writable: a tap has to flip one box in the note's
    /// own text, and matching by the item's words would toggle the wrong one the moment a note
    /// has two identical steps ("- [ ] repeat").
    public struct Task: Equatable, Sendable {
        public let isDone: Bool
        public let text: String
        public let lineIndex: Int

        public init(isDone: Bool, text: String, lineIndex: Int) {
            self.isDone = isDone
            self.text = text
            self.lineIndex = lineIndex
        }
    }

    case heading(level: Int, text: String)
    case paragraph(String)
    /// A fenced or backticked value, and whether the note asked for it to be masked.
    ///
    /// The flag lives in the note's own text — a fence opened as ```` ```secret ```` — rather than
    /// in a side table. A mask stored anywhere else is a mask that a copy, an export or a restore
    /// silently loses, and the value it was hiding is the kind that only has to surface once.
    public struct Code: Equatable, Sendable {
        public let value: String
        public let isSecret: Bool

        public init(value: String, isSecret: Bool = false) {
            self.value = value
            self.isSecret = isSecret
        }

        /// What a reader is shown. Dots rather than a blur: a blurred password is still on
        /// screen, and a screenshot or a shoulder recovers it — the characters are simply not
        /// drawn until asked for. The count is padded and capped so the dots do not report the
        /// length of the value they hide.
        public func displayed(revealed: Bool) -> String {
            guard isSecret, !revealed else { return value }
            return String(repeating: "•", count: min(max(value.count, 8), 32))
        }
    }

    case bullet(String)
    case quote(String)
    case task(Task)
    case code(Code)
    case divider

    /// The info string that marks a fenced block as one to hide until asked for.
    public static let secretFenceInfo = "secret"

    public static func blocks(of markdown: String) -> [NoteMarkdownBlock] {
        var blocks: [NoteMarkdownBlock] = []
        var fenced: [String]?
        var fenceIsSecret = false

        for (lineIndex, rawLine) in markdown.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let open = fenced {
                    blocks.append(.code(Code(
                        value: open.joined(separator: "\n"),
                        isSecret: fenceIsSecret
                    )))
                    fenced = nil
                    fenceIsSecret = false
                } else {
                    fenced = []
                    fenceIsSecret = isSecretFence(line)
                }
                continue
            }
            if fenced != nil {
                fenced?.append(rawLine)
                continue
            }
            if line.isEmpty { continue }
            if line == "---" || line == "***" || line == "___" {
                blocks.append(.divider)
            } else if line.hasPrefix("###") {
                blocks.append(.heading(level: 3, text: strip(line, "###")))
            } else if line.hasPrefix("##") {
                blocks.append(.heading(level: 2, text: strip(line, "##")))
            } else if line.hasPrefix("#") {
                blocks.append(.heading(level: 1, text: strip(line, "#")))
            } else if isSingleBacktickedValue(line) {
                blocks.append(.code(Code(value: String(line.dropFirst().dropLast()))))
            } else if line.hasPrefix("> ") {
                blocks.append(.quote(strip(line, ">")))
            } else if let task = task(in: line, lineIndex: lineIndex) {
                blocks.append(.task(task))
            } else if let bullet = ["- ", "* ", "+ "].first(where: line.hasPrefix) {
                blocks.append(.bullet(String(line.dropFirst(bullet.count))))
            } else {
                blocks.append(.paragraph(line))
            }
        }
        if let open = fenced, !open.isEmpty {
            blocks.append(.code(Code(value: open.joined(separator: "\n"), isSecret: fenceIsSecret)))
        }
        return blocks
    }

    /// Flips one task box in the note's own text, leaving every other character alone.
    ///
    /// Returns `markdown` unchanged when the line is not a task any more — the body can have been
    /// edited between the render and the tap, and rewriting a line that is now prose would be a
    /// silent corruption of the note.
    public static func togglingTask(atLine lineIndex: Int, in markdown: String) -> String {
        var lines = markdown.components(separatedBy: .newlines)
        guard lines.indices.contains(lineIndex) else { return markdown }
        let line = lines[lineIndex]
        guard let box = boxRange(in: line) else { return markdown }
        let isDone = line[box.lowerBound] != " "
        lines[lineIndex] = line.replacingCharacters(in: box, with: isDone ? " " : "x")
        return lines.joined(separator: "\n")
    }

    private static func task(in line: String, lineIndex: Int) -> Task? {
        guard let box = boxRange(in: line) else { return nil }
        let text = String(line[line.index(box.upperBound, offsetBy: 1)...])
            .trimmingCharacters(in: .whitespaces)
        return Task(isDone: line[box.lowerBound] != " ", text: text, lineIndex: lineIndex)
    }

    /// The range of the single character inside `[ ]`, or `nil` when the line is not a task.
    ///
    /// The one definition of what a task line looks like: the renderer, the toggle and the
    /// list's *has checklist* flag all ask this, so the three cannot drift into disagreeing
    /// about whether `- [x]done` counts.
    static func boxRange(in line: String) -> Range<String.Index>? {
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        guard index < line.endIndex, "-*+".contains(line[index]) else { return nil }
        index = line.index(after: index)
        while index < line.endIndex, line[index] == " " {
            index = line.index(after: index)
        }
        guard index < line.endIndex, line[index] == "[" else { return nil }
        let box = line.index(after: index)
        guard box < line.endIndex, line[box] == " " || line[box] == "x" || line[box] == "X" else {
            return nil
        }
        let closing = line.index(after: box)
        guard closing < line.endIndex, line[closing] == "]" else { return nil }
        let afterClosing = line.index(after: closing)
        guard afterClosing < line.endIndex, line[afterClosing] == " " else { return nil }
        return box..<closing
    }

    /// ```` ```secret ```` opens a masked block; any other info string is an ordinary fence.
    public static func isSecretFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces)
            .dropFirst(3)
            .trimmingCharacters(in: .whitespaces)
            .lowercased() == secretFenceInfo
    }

    private static func isSingleBacktickedValue(_ line: String) -> Bool {
        guard line.count > 2, line.hasPrefix("`"), line.hasSuffix("`") else { return false }
        return !line.dropFirst().dropLast().contains("`")
    }

    private static func strip(_ line: String, _ marker: String) -> String {
        String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
    }
}
