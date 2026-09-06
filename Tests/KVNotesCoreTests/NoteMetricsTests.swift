import Foundation
import KVNotesCore
import XCTest

final class NoteMetricsTests: XCTestCase {
    func testLockedNoteHidesWordCharacterAndLineCounts() {
        let created = Date(timeIntervalSince1970: 1000)
        let edited = Date(timeIntervalSince1970: 2000)

        let metrics = NoteMetrics(
            body: "Secret recovery seed words inside",
            isLocked: true,
            createdAt: created,
            lastEditedAt: edited
        )

        XCTAssertNil(metrics.words)
        XCTAssertNil(metrics.characters)
        XCTAssertNil(metrics.lines)
        XCTAssertEqual(metrics.storedBytes, 1024)
        XCTAssertEqual(metrics.cipherDescription, "AES-256-GCM")
        XCTAssertEqual(metrics.createdAt, created)
        XCTAssertEqual(metrics.lastEditedAt, edited)
    }

    func testUnlockedNoteComputesAccurateCountsAndPaddedStorage() {
        let created = Date(timeIntervalSince1970: 1000)
        let edited = Date(timeIntervalSince1970: 2000)
        let body = "First line of text.\nSecond line with five words!"

        let metrics = NoteMetrics(
            body: body,
            isLocked: false,
            createdAt: created,
            lastEditedAt: edited
        )

        XCTAssertEqual(metrics.words, 9)
        XCTAssertEqual(metrics.characters, body.count)
        XCTAssertEqual(metrics.lines, 2)
        XCTAssertEqual(metrics.storedBytes, 1024)
        XCTAssertEqual(metrics.cipherDescription, "AES-256-GCM")
    }

    func testEmptyBodyComputesZeroCountsAndMinimumPaddedBlock() {
        let now = Date()
        let metrics = NoteMetrics(body: "", isLocked: false, createdAt: now, lastEditedAt: now)

        XCTAssertEqual(metrics.words, 0)
        XCTAssertEqual(metrics.characters, 0)
        XCTAssertEqual(metrics.lines, 0)
        XCTAssertEqual(metrics.storedBytes, 1024)
    }

    func testLargeBodyPadsToMultipleKiBBlocks() {
        let now = Date()
        // 1020 bytes body + 5 header = 1025 bytes -> rounds to 2048
        let largeBody = String(repeating: "A", count: 1020)
        let metrics = NoteMetrics(body: largeBody, isLocked: false, createdAt: now, lastEditedAt: now)

        XCTAssertEqual(metrics.storedBytes, 2048)
    }

    func testDigestMetricsForLockedAndUnlockedNotes() {
        let lockedDigest = NoteDigest(
            title: "Bank PIN",
            snippet: nil,
            characterCount: 42,
            requiresBiometricUnlock: true
        )
        let lockedMetrics = NoteMetrics(digest: lockedDigest)
        XCTAssertNil(lockedMetrics.words)
        XCTAssertNil(lockedMetrics.characters)
        XCTAssertNil(lockedMetrics.lines)
        XCTAssertEqual(lockedMetrics.storedBytes, 1024)

        let openDigest = NoteDigest(
            title: "Shopping List",
            snippet: "Milk, Bread",
            characterCount: 65,
            requiresBiometricUnlock: false
        )
        let openMetrics = NoteMetrics(digest: openDigest)
        XCTAssertNil(openMetrics.words)
        XCTAssertEqual(openMetrics.characters, 65)
        XCTAssertNil(openMetrics.lines)
        XCTAssertEqual(openMetrics.storedBytes, 1024)
    }
}
