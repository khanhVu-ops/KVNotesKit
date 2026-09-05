import SwiftUI
import XCTest
@testable import KVNotesUI

/// The fold used to be a private method on a `View`, so the only way to know whether it worked was
/// to scroll a simulator and watch. These are the cases that were being watched for.
@MainActor
final class NotesHeaderCollapseTests: XCTestCase {
    /// The header's own height, which is also the scroll view's top inset, which is also where
    /// `contentOffset.y` rests.
    private let restingInset: CGFloat = 180

    /// One reading, as the scroll view reports it.
    ///
    /// `insetTop` is the header's *live* height, and the offset moves with it: shrinking the
    /// header by F points makes UIKit add F to `contentOffset.y` so the content stays where the
    /// reader is looking. Both terms move; their sum does not, which is the whole reason it is
    /// the sum that decides.
    private func scroll(
        _ collapse: NotesHeaderCollapse,
        scrolledBy distance: CGFloat,
        foldedBy fold: CGFloat = 0
    ) {
        let insetTop = restingInset - fold
        collapse.scrolled(offsetY: distance - insetTop, insetTop: insetTop)
    }

    private func settle(_ collapse: NotesHeaderCollapse) {
        scroll(collapse, scrolledBy: 0)
    }

    func testProgressTracksTheFingerRatherThanSnapping() {
        let collapse = NotesHeaderCollapse()
        settle(collapse)
        XCTAssertEqual(collapse.progress, 0, accuracy: 0.001)

        // 56pt is the whole fold, so a quarter of it is a quarter folded — not "not yet", which
        // is what a travelled-distance threshold answered until it answered "all of it".
        scroll(collapse, scrolledBy: 14)
        XCTAssertEqual(collapse.progress, 0.25, accuracy: 0.001)

        scroll(collapse, scrolledBy: 28)
        XCTAssertEqual(collapse.progress, 0.5, accuracy: 0.001)

        scroll(collapse, scrolledBy: 56)
        XCTAssertEqual(collapse.progress, 1, accuracy: 0.001)
    }

    func testASlowReadFoldsTheHeaderProportionally() {
        let collapse = NotesHeaderCollapse()
        settle(collapse)
        // 4pt a frame is what reading looks like at 120 Hz. The version this replaces compared
        // single frames against an 8pt gate, so this scroll never folded anything at all.
        for distance in stride(from: CGFloat(4), through: 56, by: 4) {
            scroll(collapse, scrolledBy: distance)
        }
        XCTAssertEqual(collapse.progress, 1, accuracy: 0.001)
    }

    func testProgressIsClampedAtBothEnds() {
        let collapse = NotesHeaderCollapse()
        settle(collapse)
        // The rubber band above the top reports offsets beyond rest.
        scroll(collapse, scrolledBy: -120)
        XCTAssertEqual(collapse.progress, 0, accuracy: 0.001)

        scroll(collapse, scrolledBy: 4_000)
        XCTAssertEqual(collapse.progress, 1, accuracy: 0.001)
    }

    func testScrollingBackUpUnfoldsByTheSameAmount() {
        let collapse = NotesHeaderCollapse()
        settle(collapse)
        scroll(collapse, scrolledBy: 400)
        XCTAssertEqual(collapse.progress, 1, accuracy: 0.001)

        // Direction never enters into it: the header is a function of where the list is, so
        // coming back to 28pt from above lands on exactly the value going out did.
        scroll(collapse, scrolledBy: 28)
        XCTAssertEqual(collapse.progress, 0.5, accuracy: 0.001)
        scroll(collapse, scrolledBy: 0)
        XCTAssertEqual(collapse.progress, 0, accuracy: 0.001)
    }

    /// The one that decides whether any of this works on a device.
    ///
    /// The header shrinking must not read as the reader scrolling. It did, and the header snapped
    /// shut on a 20pt drag: a 62pt fold over 56pt of travel is a feedback gain above one, so the
    /// first nudge ran it straight to pinned.
    func testFoldingIsNotReadAsScrolling() {
        let collapse = NotesHeaderCollapse()
        settle(collapse)
        scroll(collapse, scrolledBy: 20)
        let afterTheDrag = collapse.progress
        XCTAssertEqual(afterTheDrag, 20 / 56, accuracy: 0.001)

        // The header now folds by that fraction of its 62pt block, and every frame of the fold
        // reports a smaller inset and a correspondingly larger offset. Progress must not move.
        for fold in stride(from: CGFloat(0), through: 62 * afterTheDrag, by: 2) {
            scroll(collapse, scrolledBy: 20, foldedBy: fold)
            XCTAssertEqual(collapse.progress, afterTheDrag, accuracy: 0.001)
        }
    }

    /// A fold worth more than the travel distance is the case that diverged rather than settling.
    func testAFoldTallerThanTheTravelDistanceStillHolds() {
        let collapse = NotesHeaderCollapse()
        settle(collapse)
        scroll(collapse, scrolledBy: 28, foldedBy: 62 * 0.5)
        XCTAssertEqual(collapse.progress, 0.5, accuracy: 0.001)
    }

    /// The resting height belongs to the reader's text size, not to a constant in this file.
    func testATallerHeaderStillStartsAtRest() {
        let collapse = NotesHeaderCollapse()
        collapse.scrolled(offsetY: -240, insetTop: 240)
        XCTAssertEqual(collapse.progress, 0, accuracy: 0.001)

        collapse.scrolled(offsetY: 28 - 240, insetTop: 240)
        XCTAssertEqual(collapse.progress, 0.5, accuracy: 0.001)
    }
}
