import Foundation
import XCTest
@testable import KVNotesUI

final class NotesLocalizationTests: XCTestCase {
    func testEveryLanguageHasTheSameNonEmptyKeys() throws {
        let english = try table(for: "en")
        XCTAssertFalse(english.isEmpty)

        for language in NotesLocalization.supportedLanguages {
            let localized = try table(for: language)
            XCTAssertEqual(Set(localized.keys), Set(english.keys), "Keys differ for \(language)")
            XCTAssertTrue(localized.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
    }

    func testPackageDeclaresAllNineteenLanguages() {
        XCTAssertEqual(NotesLocalization.supportedLanguages.count, 19)
        XCTAssertEqual(Set(NotesLocalization.supportedLanguages).count, 19)
    }

    private func table(for language: String) throws -> [String: String] {
        let url = try XCTUnwrap(NotesLocalization.bundle.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: language
        ))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
    }
}
