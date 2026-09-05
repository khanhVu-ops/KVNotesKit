import Foundation
import SwiftUI

/// How far the notes header has folded, from 0 at rest to 1 pinned.
///
/// Continuous, and that is the whole design. The version this replaces was a `Bool` decided from
/// travelled distance: it waited for 30pt of scrolling and then sprang between two states, so the
/// header was always either not reacting yet or moving on its own clock, and never under the
/// finger. Vault Home had already solved this — its chrome interpolates against a 0…1 progress
/// taken straight off the content offset — and this is that model.
///
/// A reference type rather than `@State` on the screen, and that part matters more here, not
/// less: progress is written on *every* scroll frame, and `@State` written at 120 Hz invalidates
/// the body that declares it — a body that builds the card array, all three option sheets and
/// every folder group before it returns. Only `progress` is observable, and only `NotesListHeader`
/// reads it, so a frame of scrolling redraws a header rather than a screen. Vault Home pays that
/// cost; this does not.
@MainActor
@Observable
final class NotesHeaderCollapse {
    /// 0 while the header is at rest, 1 once it is fully pinned, and every value in between.
    private(set) var progress: Double = 0

    /// How far the list travels between the resting header and the pinned one.
    ///
    /// The same 56pt Vault Home uses. It is short on purpose: the header should have finished
    /// folding by the time the first card has cleared it, not still be folding two screens down.
    private static let distance: CGFloat = 56

    /// How far the list has been scrolled from the top of its own content.
    ///
    /// The header is a `safeAreaInset`, so it *is* the scroll view's top content inset and
    /// `contentOffset.y` rests at `-headerHeight` rather than at zero. Adding the inset back is
    /// what turns that into a distance, and it is the right sum for two separate reasons.
    ///
    /// It needs no resting height, so there is nothing to hard-code and nothing to be wrong about
    /// at a text size other than the author's. Vault Home hard-codes 131 and is wrong for everyone
    /// who has changed theirs.
    ///
    /// And it is invariant under a header that changes height, because UIKit moves
    /// `contentOffset.y` by whatever the inset loses. That mattered enormously when this header
    /// folded itself: re-based on a constant instead, a fold of F points over a travel distance of
    /// D added F/D of progress for free and settled at `p / (1 - F/D)` — 1.75x the intended rate
    /// on Vault Home, and divergent here, where the title and count line were worth more than the
    /// 56pt of travel. Measured, not reasoned: the header snapped shut on a 20pt drag.
    ///
    /// It matters much less now, and that is the point. Nothing this returns can change the height
    /// of the pinned header any more — the part that folds is content inside the scroll view, and
    /// progress only reaches opacity. See `NotesListTitleBlock` for why that had to change.
    func scrolled(offsetY: CGFloat, insetTop: CGFloat) {
        let scrolled = offsetY + insetTop
        let next = min(max(Double(scrolled / Self.distance), 0), 1)
        // Observation fires on assignment and not on change, and this runs on every frame of
        // every scroll: without the guard a list resting at the top would redraw the header a
        // hundred times a second to tell it the same thing.
        guard abs(next - progress) > 0.0005 else { return }
        progress = next
    }
}

extension View {
    /// Feeds a scroll view's geometry to the header that sits on top of it.
    func notesHeaderCollapse(_ collapse: NotesHeaderCollapse) -> some View {
        onScrollGeometryChange(for: NotesScrollMetrics.self) { geometry in
            NotesScrollMetrics(
                offsetY: geometry.contentOffset.y,
                insetTop: geometry.contentInsets.top
            )
        } action: { _, metrics in
            collapse.scrolled(offsetY: metrics.offsetY, insetTop: metrics.insetTop)
        }
    }
}

/// The two numbers the header reads out of the list's scroll view.
struct NotesScrollMetrics: Equatable {
    var offsetY: CGFloat
    var insetTop: CGFloat
}
