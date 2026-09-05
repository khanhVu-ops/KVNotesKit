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
