import Foundation
import KVNotesCore
import XCTest

final class NoteIconTests: XCTestCase {
    func testParseEmojiAndSymbol() {
        XCTAssertNil(NoteIcon.parse(nil))
        XCTAssertNil(NoteIcon.parse(""))
        XCTAssertNil(NoteIcon.parse("   "))
        XCTAssertNil(NoteIcon.parse("sf:"))

        XCTAssertEqual(NoteIcon.parse("🔑"), .emoji("🔑"))
        XCTAssertEqual(NoteIcon.parse("🔑")?.emoji, "🔑")
        XCTAssertNil(NoteIcon.parse("🔑")?.symbolName)
        XCTAssertEqual(NoteIcon.parse("🔑")?.rawValue, "🔑")

        XCTAssertEqual(NoteIcon.parse("sf:lock.shield.fill"), .symbol("lock.shield.fill"))
        XCTAssertEqual(NoteIcon.parse("sf:lock.shield.fill")?.symbolName, "lock.shield.fill")
        XCTAssertNil(NoteIcon.parse("sf:lock.shield.fill")?.emoji)
        XCTAssertEqual(NoteIcon.parse("sf:lock.shield.fill")?.rawValue, "sf:lock.shield.fill")
    }

    func testSanitizeEmojiCappedAtOneGraphemeCluster() {
        XCTAssertEqual(NoteIconSanitizer.sanitizeEmoji("🔑"), "🔑")
        XCTAssertEqual(NoteIconSanitizer.sanitizeEmoji("🔑abc"), "🔑")
        XCTAssertEqual(NoteIconSanitizer.sanitizeEmoji(" 🚀 "), "🚀")
        XCTAssertEqual(NoteIconSanitizer.sanitizeEmoji("⭐️"), "⭐️")
        XCTAssertEqual(NoteIconSanitizer.sanitizeEmoji("✈️"), "✈️")
        XCTAssertEqual(NoteIconSanitizer.sanitizeEmoji("👍🏽"), "👍🏽")
    }

    func testSanitizeEmojiRejectsNonEmojiText() {
        XCTAssertNil(NoteIconSanitizer.sanitizeEmoji(""))
        XCTAssertNil(NoteIconSanitizer.sanitizeEmoji("hello"))
        XCTAssertNil(NoteIconSanitizer.sanitizeEmoji("123"))
        XCTAssertNil(NoteIconSanitizer.sanitizeEmoji("   "))
    }

    func testSanitizeEmojiRejectsFlagsAndFamilySequences() {
        // Multi-person / Family ZWJ sequence
        XCTAssertNil(NoteIconSanitizer.sanitizeEmoji("👨‍👩‍👧‍👦"))
        // Flag regional indicator sequence
        XCTAssertNil(NoteIconSanitizer.sanitizeEmoji("🇻🇳"))
        XCTAssertNil(NoteIconSanitizer.sanitizeEmoji("🇺🇸"))
    }

    func testLibraryCategoriesAndCuratedLists() {
        XCTAssertEqual(NoteIconLibrary.Category.allCases.count, 7)
        XCTAssertFalse(NoteIconLibrary.curatedEmojis.isEmpty)

        for category in NoteIconLibrary.Category.allCases where category != .emoji {
            let symbols = NoteIconLibrary.symbols(for: category)
            XCTAssertEqual(symbols.count, 11)
            for symbol in symbols {
                XCTAssertFalse(symbol.isEmpty)
                XCTAssertFalse(symbol.contains(" "))
            }
        }

        XCTAssertEqual(NoteIconLibrary.category(for: nil), .general)
        XCTAssertEqual(NoteIconLibrary.category(for: "🔑"), .emoji)
        XCTAssertEqual(NoteIconLibrary.category(for: "sf:lock.fill"), .security)
        XCTAssertEqual(NoteIconLibrary.category(for: "sf:creditcard.fill"), .finance)
        XCTAssertEqual(NoteIconLibrary.category(for: "sf:briefcase.fill"), .work)
        XCTAssertEqual(NoteIconLibrary.category(for: "sf:desktopcomputer"), .tech)
        XCTAssertEqual(NoteIconLibrary.category(for: "sf:airplane"), .places)
    }
}
