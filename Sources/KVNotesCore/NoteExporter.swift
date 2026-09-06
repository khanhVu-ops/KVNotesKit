import Foundation

/// Supported export formats for private notes.
public enum NoteExportFormat: String, CaseIterable, Sendable {
    case markdown
    case plainText

    public var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        }
    }
}

/// The result of preparing a note for export.
public struct NoteExportPayload: Equatable, Sendable {
    public let filename: String
    public let content: String
    public let format: NoteExportFormat

    public init(filename: String, content: String, format: NoteExportFormat) {
        self.filename = filename
        self.content = content
        self.format = format
    }
}

/// Pure formatting and filename sanitization for exporting notes.
public enum NoteExporter {
    /// Formats note title and body into an exportable payload.
    ///
    /// For Markdown:
    /// - If the title is present and the body does not already start with `# `, a top-level heading
    ///   `# <Title>` is prepended.
    /// - Otherwise, the body is preserved verbatim.
    ///
    /// For Plain Text:
    /// - If the title is present, `<Title>\n\n<body>` is emitted.
    /// - Otherwise, the body is preserved verbatim.
    public static func export(
        title: String,
        body: String,
        format: NoteExportFormat
    ) -> NoteExportPayload {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle: String
        if trimmedTitle.isEmpty {
            resolvedTitle = NoteTextDerivation.derivedTitle(from: body)
        } else {
            resolvedTitle = trimmedTitle
        }

        let baseFilename = resolvedTitle.isEmpty ? "Untitled" : sanitizedFilename(resolvedTitle)
        let filename = "\(baseFilename).\(format.fileExtension)"

        let formattedContent: String
        switch format {
        case .markdown:
            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty && !trimmedBody.hasPrefix("#") {
                formattedContent = "# \(trimmedTitle)\n\n\(body)"
            } else {
                formattedContent = body
            }
        case .plainText:
            if !trimmedTitle.isEmpty {
                formattedContent = "\(trimmedTitle)\n\n\(body)"
            } else {
                formattedContent = body
            }
        }

        return NoteExportPayload(
            filename: filename,
            content: formattedContent,
            format: format
        )
    }

    /// Strips illegal filesystem characters and trims whitespace, falling back to "Untitled".
    public static func sanitizedFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|\0")
        let components = name.components(separatedBy: invalidCharacters)
        let joined = components.filter { !$0.isEmpty }.joined(separator: "-")
        let sanitized = joined.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_"))
        )
        return sanitized.isEmpty ? "Untitled" : sanitized
    }
}
