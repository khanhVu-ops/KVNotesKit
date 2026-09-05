import XCTest
@testable import KVNotesCore

final class NoteFindTests: XCTestCase {
    func testMatchesIgnoreCaseAndAccentsAndKeepTheirPlaceInTheOriginal() {
        let text = "Ledger seed\nledger backup\nLEDGER" as NSString

        let matches = NoteFind.matches(of: "ledger", in: text)

        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(text.substring(with: matches[0]), "Ledger")
        XCTAssertEqual(text.substring(with: matches[2]), "LEDGER")
    }

    /// The case Foundation's own diacritic folding gets wrong, and the reason this type exists.
    func testVietnameseDeeIsFoldedSoTheObviousSearchWorks() {
        let text = "Đường dây và duong khac" as NSString

        let matches = NoteFind.matches(of: "duong", in: text)

        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(text.substring(with: matches[0]), "Đường")
        XCTAssertEqual(text.substring(with: matches[1]), "duong")
    }

    func testAnEmptyOrBlankQueryFindsNothingRatherThanEverything() {
        let text = "anything" as NSString
        XCTAssertTrue(NoteFind.matches(of: "", in: text).isEmpty)
        XCTAssertTrue(NoteFind.matches(of: "   \n", in: text).isEmpty)
    }

    func testOverlappingRunsAdvancePastEachMatchRatherThanLooping() {
        let text = "aaaa" as NSString

        let matches = NoteFind.matches(of: "aa", in: text)

        XCTAssertEqual(matches.map(\.location), [0, 2])
    }

    func testTheMatchCountIsBounded() {
        let text = String(repeating: "a ", count: 2_000) as NSString

        XCTAssertEqual(NoteFind.matches(of: "a", in: text).count, NoteFind.matchLimit)
    }

    func testFindStartsFromWhereTheReaderIsRatherThanTheTop() {
        let matches = [NSRange(location: 5, length: 2), NSRange(location: 40, length: 2)]

        XCTAssertEqual(NoteFind.indexOfMatch(at: 20, in: matches), 1)
        XCTAssertEqual(NoteFind.indexOfMatch(at: 0, in: matches), 0)
        // Past the last match it wraps to the first, which is where "next" would go anyway.
        XCTAssertEqual(NoteFind.indexOfMatch(at: 900, in: matches), 0)
        XCTAssertNil(NoteFind.indexOfMatch(at: 0, in: []))
    }
}
