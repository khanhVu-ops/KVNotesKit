import Foundation

/// The blocks read mode draws. Unsupported lines remain paragraphs so authored text never
/// disappears merely because the renderer does not understand its syntax.
public enum NoteMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case code(String)
    case divider

    public static func blocks(of markdown: String) -> [NoteMarkdownBlock] {
        var blocks: [NoteMarkdownBlock] = []
        var fenced: [String]?

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let open = fenced {
                    blocks.append(.code(open.joined(separator: "\n")))
                    fenced = nil
                } else {
                    fenced = []
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
                blocks.append(.code(String(line.dropFirst().dropLast())))
            } else if let bullet = ["- ", "* ", "+ "].first(where: line.hasPrefix) {
                blocks.append(.bullet(String(line.dropFirst(bullet.count))))
            } else {
                blocks.append(.paragraph(line))
            }
        }
        if let open = fenced, !open.isEmpty {
            blocks.append(.code(open.joined(separator: "\n")))
        }
        return blocks
    }

    private static func isSingleBacktickedValue(_ line: String) -> Bool {
        guard line.count > 2, line.hasPrefix("`"), line.hasSuffix("`") else { return false }
        return !line.dropFirst().dropLast().contains("`")
    }

    private static func strip(_ line: String, _ marker: String) -> String {
        String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
    }
}
