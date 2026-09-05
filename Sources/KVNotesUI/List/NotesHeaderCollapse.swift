import Foundation
import SwiftUI

/// The two numbers the header reads out of the list's scroll view.
///
/// The inset is here and not only the offset because the header *is* the inset: it lives in a
/// `safeAreaInset`, so folding it changes the number the fold was decided from. Carrying both
/// lets the decision tell a finger apart from the header's own resize, which is the difference
/// between a header that folds and one that flaps.
struct NotesScrollMetrics: Equatable {
    var offset: CGFloat
    var insetTop: CGFloat
}

/// Decides whether the notes header is folded, from the list's scroll geometry.
///
/// A reference type rather than `@State` on the screen, and that is the point rather than a
/// style choice. This bookkeeping is written on *every* scroll frame, and `@State` written at
/// 120 Hz invalidates the body that declares it 120 times a second — a body that builds the row
/// array, all three option sheets and every folder group before it returns. The header's own
/// bookkeeping was costing a full screen rebuild per frame, which is what the stutter was.
///
/// Only `isCollapsed` is observable here, and only the header view reads it, so a fold now
/// redraws the header and leaves the list alone.
@MainActor
@Observable
final class NotesHeaderCollapse {
    /// Whether the title, the count line and the folder chips are folded away.
    private(set) var isCollapsed = false

    /// Sustained travel, in points, before the header changes its mind.
    ///
    /// The first version compared one frame against the frame before it and folded on an 8pt
    /// difference. At 120 Hz a deliberate read scrolls 3–6pt per frame, so that gate never
    /// opened while reading and opened on a single twitch inside a flick — the header both
    /// refused to fold and folded when nobody asked. Distance travelled in one direction is
    /// what a person means by "scrolling down", and it is measured over as many frames as it
    /// takes to add up.
    private static let threshold: CGFloat = 30
    /// Within this of the top the header is open, whatever the finger was doing.
    ///
    /// The top is the one place direction cannot decide: a flick that lands on the first row is
    /// still travelling upward when it stops, and the rubber band reports both ways on the way
    /// back — either way the header stayed folded over a list with nothing above it, which is
    /// the state it exists to fold *out* of.
    private static let floor: CGFloat = 8
    /// A flick banks hundreds of points of travel; capping it keeps the reversal one gesture
    /// away instead of making the user scroll back the whole distance they came.
    private static let clamp: CGFloat = 90
    /// How long a content change that moves the list under a still finger is ignored for.
    private static let hold = Duration.milliseconds(400)

    @ObservationIgnored private var lastOffset: CGFloat = 0
    @ObservationIgnored private var lastInsetTop: CGFloat = .nan
    @ObservationIgnored private var travel: CGFloat = 0
    @ObservationIgnored private var holdsUntil: ContinuousClock.Instant?

    /// Folds on the way down and unfolds on the way up, from travelled distance rather than
    /// from a fixed offset.
    ///
    /// An absolute threshold cannot work here: folding changes the list's top inset, which
    /// changes the offset that decided to fold it, so a fixed line latches the moment it is
    /// crossed. Direction is immune to the resize, and the resize itself is recognised by the
    /// inset moving rather than by a wall-clock window — so the header starts listening again
    /// exactly when the fold animation ends, not a guessed number of milliseconds later.
    func scrolled(offset: CGFloat, insetTop: CGFloat, animation: Animation) {
        let previousOffset = lastOffset
        let previousInsetTop = lastInsetTop
        lastOffset = offset
        lastInsetTop = insetTop

        if offset <= Self.floor {
            travel = 0
            setCollapsed(false, animation: animation)
            return
        }

        // A frame in which the inset moved is a frame about the header, not about the finger.
        // Rebase and decide nothing; the same goes for the first reading of a scroll view that
        // has only just appeared, whose "previous" offset belongs to the one it replaced.
        guard !previousInsetTop.isNaN, abs(insetTop - previousInsetTop) <= 0.5, !isHolding else {
            travel = 0
            return
        }

        let delta = offset - previousOffset
        guard abs(delta) > 0.5 else { return }
        // Changing direction starts the count again, so a scroll down followed by a scroll up
        // does not have to first pay back everything it banked going the other way.
        if (delta > 0) != (travel > 0) { travel = 0 }
        travel = min(max(travel + delta, -Self.clamp), Self.clamp)
        guard abs(travel) >= Self.threshold else { return }
        let collapsed = travel > 0
        travel = 0
        setCollapsed(collapsed, animation: animation)
    }

    /// Ignores the geometry for a moment, for a change that moves the content under a finger
    /// that is not moving.
    ///
    /// A pinned row travelling to the top, or a row leaving on a swipe, shifts the list's own
    /// content offset. Read as a scroll it folds the header underneath the move, which resizes
    /// the list mid-animation — the jump the animation exists to avoid.
    func holdSteady() {
        holdsUntil = ContinuousClock.now.advanced(by: Self.hold)
        travel = 0
    }

    /// Forgets where the list was, for a scroll view that is being replaced by another one.
    ///
    /// Swapping the rows for the grid throws away the scroll view that was reporting offsets,
    /// and the first reading from the new one would otherwise be measured against the old one's
    /// last. Left alone that difference reads as a flick.
    func rebase() {
        lastOffset = 0
        lastInsetTop = .nan
        travel = 0
    }

    /// Opens the header because there is no longer a list to fold it over.
    func expand(animation: Animation) {
        travel = 0
        setCollapsed(false, animation: animation)
    }

    private var isHolding: Bool {
        guard let holdsUntil else { return false }
        guard ContinuousClock.now < holdsUntil else {
            self.holdsUntil = nil
            return false
        }
        return true
    }

    /// Observation fires on assignment and not on change, and this runs on every scroll frame:
    /// without the guard a scrolling list would redraw the header sixty times a second to tell
    /// it the same thing.
    private func setCollapsed(_ collapsed: Bool, animation: Animation) {
        guard collapsed != isCollapsed else { return }
        withAnimation(animation) { isCollapsed = collapsed }
    }
}

extension View {
    /// Feeds a scroll view's geometry to the header that sits on top of it.
    func notesHeaderCollapse(_ collapse: NotesHeaderCollapse, animation: Animation) -> some View {
        onScrollGeometryChange(for: NotesScrollMetrics.self) { geometry in
            NotesScrollMetrics(
                offset: geometry.contentOffset.y + geometry.contentInsets.top,
                insetTop: geometry.contentInsets.top
            )
        } action: { _, metrics in
            collapse.scrolled(
                offset: metrics.offset,
                insetTop: metrics.insetTop,
                animation: animation
            )
        }
    }
}
