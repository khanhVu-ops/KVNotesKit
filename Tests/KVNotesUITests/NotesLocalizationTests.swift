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

    /// A plural table is silently optional: leave one language without a `.stringsdict` and its
    /// count line falls back to the flat table, which no longer has that key — the screen then
    /// shows the raw `%lld notes`. Nothing fails, so this test is the only thing that would.
    func testEveryLanguageHasTheSamePluralKeys() throws {
        let english = try pluralTable(for: "en")
        XCTAssertEqual(Set(english.keys), ["%lld notes", "%lld characters"])

        for language in NotesLocalization.supportedLanguages {
            let table = try pluralTable(for: language)
            XCTAssertEqual(Set(table.keys), Set(english.keys), "Plural keys differ for \(language)")
            for (key, rule) in table {
                let variants = try XCTUnwrap(rule["count"] as? [String: Any], "\(language) \(key)")
                // `other` is the fallback every language must carry; the rest are its own.
                XCTAssertNotNil(variants["other"], "\(language) \(key) has no `other` form")
                XCTAssertEqual(variants["NSStringFormatValueTypeKey"] as? String, "lld")
            }
        }
    }

    /// The plural table is only worth having if the count actually selects a form. Resolving it
    /// here also proves the `.stringsdict` reaches the built bundle: SwiftPM processes it as a
    /// resource, and a file that never arrived would leave the flat table's answer standing.
    func testCountSelectsThePluralForm() throws {
        XCTAssertEqual(resolved("%lld notes", count: 1, language: "en"), "1 note")
        XCTAssertEqual(resolved("%lld notes", count: 3, language: "en"), "3 notes")
        XCTAssertEqual(resolved("%lld characters", count: 1, language: "en"), "1 character")
        XCTAssertEqual(resolved("%lld characters", count: 93, language: "en"), "93 characters")
        // Vietnamese has one form for every count, which is the answer, not a missing case.
        XCTAssertEqual(resolved("%lld notes", count: 1, language: "vi"), "1 ghi chú")
        XCTAssertEqual(resolved("%lld notes", count: 3, language: "vi"), "3 ghi chú")
        // Russian's three forms are the reason a number beside a fixed noun could not work.
        XCTAssertEqual(resolved("%lld notes", count: 1, language: "ru"), "1 заметка")
        XCTAssertEqual(resolved("%lld notes", count: 3, language: "ru"), "3 заметки")
        XCTAssertEqual(resolved("%lld notes", count: 5, language: "ru"), "5 заметок")
    }

    func testPackageDeclaresAllNineteenLanguages() {
        XCTAssertEqual(NotesLocalization.supportedLanguages.count, 19)
        XCTAssertEqual(Set(NotesLocalization.supportedLanguages).count, 19)
    }

    private func resolved(_ key: String, count: Int, language: String) -> String {
        guard let path = NotesLocalization.bundle.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return "" }
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        // The locale has to be passed explicitly: the plural rule is chosen by the *formatting*
        // locale, not by the bundle the format came from, so a test machine running in English
        // would otherwise answer Russian text with English's two-form rule.
        return String(format: format, locale: Locale(identifier: language), count)
    }

    private func pluralTable(for language: String) throws -> [String: [String: Any]] {
        let url = try XCTUnwrap(NotesLocalization.bundle.url(
            forResource: "Localizable",
            withExtension: "stringsdict",
            subdirectory: nil,
            localization: language
        ), "No stringsdict for \(language)")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]]
        )
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
