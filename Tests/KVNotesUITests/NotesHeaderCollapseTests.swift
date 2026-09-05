import SwiftUI
import XCTest
@testable import KVNotesUI

/// The fold used to be a private method on a `View`, so the only way to know whether it worked
/// was to scroll a simulator and watch. These are the cases that were being watched for.
@MainActor
final class NotesHeaderCollapseTests: XCTestCase {
    private let animation = Animation.linear(duration: 0)

    /// One reading, and then a run of readings at a fixed inset — the shape a real scroll has.
    private func scroll(_ collapse: NotesHeaderCollapse, _ offsets: [CGFloat], insetTop: CGFloat = 200) {
        for offset in offsets {
            collapse.scrolled(offset: offset, insetTop: insetTop, animation: animation)
        }
    }

    func testASlowReadStillFoldsTheHeader() {
        let collapse = NotesHeaderCollapse()
        // 4pt a frame is what reading looks like at 120 Hz. The version this replaces compared
        // single frames against an 8pt gate, so this scroll never folded anything at all.
        scroll(collapse, [20] + stride(from: CGFloat(24), through: 60, by: 4).map { $0 })
        XCTAssertTrue(collapse.isCollapsed)
    }

    func testATwitchDoesNotFoldTheHeader() {
        let collapse = NotesHeaderCollapse()
        scroll(collapse, [20, 32, 30, 33, 29, 34])
        XCTAssertFalse(collapse.isCollapsed)
    }

    func testScrollingBackUpUnfoldsWithoutReturningToTheTop() {
        let collapse = NotesHeaderCollapse()
        scroll(collapse, [200, 240, 280])
        XCTAssertTrue(collapse.isCollapsed)
        scroll(collapse, [270, 250, 240])
        XCTAssertFalse(collapse.isCollapsed)
    }

    func testReachingTheTopAlwaysUnfolds() {
        let collapse = NotesHeaderCollapse()
        scroll(collapse, [100, 140, 180])
        XCTAssertTrue(collapse.isCollapsed)
        // A flick that lands on the first row is still travelling downward when it stops; the
        // header is folded over a list with nothing above it unless the top overrules direction.
        collapse.scrolled(offset: 0, insetTop: 200, animation: animation)
        XCTAssertFalse(collapse.isCollapsed)
    }

    func testTheHeaderResizingIsNotReadAsAScroll() {
        let collapse = NotesHeaderCollapse()
        scroll(collapse, [100, 140, 180])
        XCTAssertTrue(collapse.isCollapsed)
        // Folding shrinks the list's top inset. Those frames report the header moving, not the
        // finger, and reacting to them is the loop that made the first version flap.
        for inset in stride(from: CGFloat(200), through: 90, by: -10) {
            collapse.scrolled(offset: 180 - (200 - inset), insetTop: inset, animation: animation)
        }
        XCTAssertTrue(collapse.isCollapsed)
    }

    func testAHoldIgnoresContentMovingUnderAStillFinger() {
        let collapse = NotesHeaderCollapse()
        // A pinned row travelling to the top, or a swiped row leaving, shifts the content offset
        // with nobody touching the screen.
        collapse.holdSteady()
        scroll(collapse, [200, 260, 320])
        XCTAssertFalse(collapse.isCollapsed)
    }

    func testSwappingScrollViewsDoesNotReadAsAFlick() {
        let collapse = NotesHeaderCollapse()
        scroll(collapse, [200, 260, 320])
        XCTAssertTrue(collapse.isCollapsed)
        scroll(collapse, [300, 260, 220])
        XCTAssertFalse(collapse.isCollapsed)

        // The grid replaces the list: a new scroll view, starting at its own zero, whose first
        // reading would otherwise be measured against the old one's last.
        collapse.rebase()
        collapse.scrolled(offset: 400, insetTop: 200, animation: animation)
        XCTAssertFalse(collapse.isCollapsed)
    }
}
