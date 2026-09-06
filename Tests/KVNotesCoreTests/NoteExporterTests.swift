import XCTest
@testable import KVNotesCore

final class NoteExporterTests: XCTestCase {
    func testMarkdownExportPrependsHeadingWhenNotPresent() {
        let payload = NoteExporter.export(
            title: "Shopping List",
            body: "- [ ] Milk\n- [ ] Bread",
            format: .markdown
        )

        XCTAssertEqual(payload.filename, "Shopping List.md")
        XCTAssertEqual(payload.content, "# Shopping List\n\n- [ ] Milk\n- [ ] Bread")
        XCTAssertEqual(payload.format, .markdown)
    }

    func testMarkdownExportPreservesExistingHeading() {
        let payload = NoteExporter.export(
            title: "Shopping List",
            body: "# Shopping List\n- [ ] Milk",
            format: .markdown
        )

        XCTAssertEqual(payload.filename, "Shopping List.md")
        XCTAssertEqual(payload.content, "# Shopping List\n- [ ] Milk")
    }

    func testMarkdownExportDerivesTitleWhenEmpty() {
        let payload = NoteExporter.export(
            title: "",
            body: "# My Secret Recipe\n1 cup flour",
            format: .markdown
        )

        XCTAssertEqual(payload.filename, "My Secret Recipe.md")
        XCTAssertEqual(payload.content, "# My Secret Recipe\n1 cup flour")
    }

    func testPlainTextExportIncludesTitleAndBody() {
        let payload = NoteExporter.export(
            title: "Meeting Notes",
            body: "Discussed roadmap and timeline.",
            format: .plainText
        )

        XCTAssertEqual(payload.filename, "Meeting Notes.txt")
        XCTAssertEqual(payload.content, "Meeting Notes\n\nDiscussed roadmap and timeline.")
        XCTAssertEqual(payload.format, .plainText)
    }

    func testFilenameSanitizationRemovesIllegalCharacters() {
        let dirty = "Project / Alpha: Budget * 2026? <Confidential>"
        let sanitized = NoteExporter.sanitizedFilename(dirty)
        XCTAssertFalse(sanitized.contains("/"))
        XCTAssertFalse(sanitized.contains(":"))
        XCTAssertFalse(sanitized.contains("*"))
        XCTAssertFalse(sanitized.contains("?"))
        XCTAssertFalse(sanitized.contains("<"))
        XCTAssertFalse(sanitized.contains(">"))

        XCTAssertEqual(NoteExporter.sanitizedFilename(""), "Untitled")
        XCTAssertEqual(NoteExporter.sanitizedFilename("   "), "Untitled")
        XCTAssertEqual(NoteExporter.sanitizedFilename("///:::"), "Untitled")
    }
}
