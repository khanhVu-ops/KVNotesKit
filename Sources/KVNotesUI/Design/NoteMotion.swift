import SwiftUI

enum NoteMotion {
    static func selection(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.38, dampingFraction: 0.9)
    }

    /// The read/edit switch: one curve for the sliding pill and both surfaces, so the control
    /// and the thing it controls move together rather than at two different speeds.
    static func mode(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.34, dampingFraction: 0.86)
    }

    static func content(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.44, dampingFraction: 0.92)
    }

    /// The header folding away and coming back.
    ///
    /// Fully damped, and that is not taste. The header is a `safeAreaInset`, so its height *is*
    /// the list's top content inset: a spring that overshoots drives the inset past its mark and
    /// back, and the scroll view re-adjusts its own offset on every frame of the overshoot. Under
    /// a finger that has already stopped, that reads as the list twitching rather than as bounce —
    /// and each of those frames is another offset reading the fold has to recognise as its own.
    static func header(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.3, dampingFraction: 1)
    }

    /// Rows becoming cards.
    ///
    /// A spring, unlike `header`: nothing here is a scroll inset, so a little overshoot is a card
    /// arriving somewhere rather than a list twitching. Slower than `reorder` because these
    /// travel further and change shape on the way — every card moves at once, and a stiff curve
    /// on that many frames reads as a cut with extra steps.
    static func layout(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.42, dampingFraction: 0.86)
    }

    /// A row changing places in a list.
    ///
    /// Quicker and stiffer than `content`: a row that travels the length of the list on a 0.44s
    /// spring reads as the list thinking about it, and any overshoot at the end looks like the
    /// row bouncing off the one above. Fully damped, and short enough to still belong to the
    /// swipe that asked for it.
    static func reorder(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.34, dampingFraction: 1)
    }
}

struct NotePressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension View {
    func noteShimmer(theme: NoteTheme) -> some View {
        modifier(NoteShimmerModifier(theme: theme))
    }
}

private struct NoteShimmerModifier: ViewModifier {
    let theme: NoteTheme

    func body(content: Content) -> some View {
        ZStack {
            content
            NoteShimmerBand(theme: theme)
                .mask(content)
                .blendMode(.plusLighter)
        }
    }
}

private struct NoteShimmerBand: View {
    let theme: NoteTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = reduceMotion ? 0.5 : (time * 0.9).truncatingRemainder(dividingBy: 1)

            GeometryReader { proxy in
                let diagonal = hypot(proxy.size.width, proxy.size.height)
                let band = max(16, diagonal * 0.28)
                let travel = diagonal + band
                let offset = (phase * 2 - 1) * travel / 2

                LinearGradient(
                    colors: [.clear, theme.card, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: band, height: travel)
                .rotationEffect(.degrees(20))
                .offset(x: proxy.size.width / 2 + offset - band / 2,
                        y: proxy.size.height / 2 - travel / 2)
                .allowsHitTesting(false)
            }
        }
    }
}
