import KVNotesCore
import SwiftUI

struct NoteUnlockGate: View {
    let note: NoteDigest
    let offer: NoteUnlockOffer
    let phase: NoteEditorState.UnlockPhase
    let theme: NoteTheme
    let onUnlock: () -> Void
    let onUsePIN: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false
    @State private var didRequestAutomatically = false

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            redactedBody
            VStack(spacing: 0) {
                Spacer()
                mark
                caption
                Spacer()
                actions
            }
            .padding(.horizontal, theme.large)
        }
        .onAppear {
            isBreathing = !reduceMotion
            guard !didRequestAutomatically, offer.biometric != nil else { return }
            didRequestAutomatically = true
            onUnlock()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.notesKit("Unlocking private note")))
    }

    private var redactedBody: some View {
        VStack(alignment: .leading, spacing: theme.small + 2) {
            ForEach(Array(Self.barWidths.enumerated()), id: \.offset) { _, fraction in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.primaryText)
                    .frame(height: 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: fraction, y: 1, anchor: .leading)
            }
        }
        .opacity(0.08)
        .padding(.horizontal, theme.medium)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, theme.extraLarge)
        .accessibilityHidden(true)
    }

    private static let barWidths: [CGFloat] = [0.62, 0.94, 0.78, 0.9, 0.4, 0.86, 0.7]

    private var mark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .strokeBorder(markTone, lineWidth: 1.25)
                .frame(width: 76, height: 76)
            Image(systemName: symbolName)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(markTone)
                .contentTransition(.symbolEffect(.replace))
        }
        .scaleEffect(scale)
        .opacity(phase == .granted ? 0 : 1)
        .animation(breathingAnimation, value: isBreathing)
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: phase)
    }

    private var symbolName: String {
        switch phase {
        case .waiting, .authenticating:
            switch offer.biometric {
            case .faceID: "faceid"
            case .touchID: "touchid"
            case .opticID: "opticid"
            case nil: "lock"
            }
        case .denied: "exclamationmark.triangle"
        case .granted: "lock.open"
        }
    }

    private var markTone: Color {
        switch phase {
        case .denied: theme.error
        case .granted: theme.success
        case .waiting, .authenticating: theme.primaryText
        }
    }

    private var scale: CGFloat {
        switch phase {
        case .granted: 1.4
        case .waiting: isBreathing ? 1 : 0.965
        case .authenticating, .denied: 1
        }
    }

    private var breathingAnimation: Animation? {
        guard phase == .waiting, !reduceMotion else { return nil }
        return .easeInOut(duration: 1.9).repeatForever(autoreverses: true)
    }

    private var caption: some View {
        VStack(spacing: theme.small + 2) {
            Text(headline)
                .font(theme.sectionFont)
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(theme.primaryText)
                .contentTransition(.opacity)
            if !note.title.isEmpty {
                Text(verbatim: note.title)
                    .font(theme.monoFont)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.top, theme.large)
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: phase)
    }

    private var headline: LocalizedStringResource {
        switch phase {
        case .waiting, .granted: .notesKit("Unlocking private note")
        case .authenticating: .notesKit("Authenticating…")
        case .denied: .notesKit("Not unlocked")
        }
    }

    private var actions: some View {
        VStack(spacing: theme.small + 4) {
            if offer.biometric != nil {
                Button(action: onUnlock) {
                    Text(phase == .denied ? .notesKit("Try again") : .notesKit("Unlock"))
                        .font(theme.modeFont)
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, theme.large)
                        .frame(height: 46)
                        .frame(maxWidth: .infinity)
                        .background(theme.accent, in: Capsule())
                }
                .buttonStyle(NotePressButtonStyle())
                .disabled(phase == .authenticating || phase == .granted)
            }

            if offer.allowsPINFallback {
                Button(action: onUsePIN) {
                    Text(.notesKit("Use PIN instead"))
                        .font(theme.modeFont)
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, theme.large)
                        .frame(height: 46)
                        .frame(maxWidth: .infinity)
                        .overlay { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
                }
                .buttonStyle(NotePressButtonStyle())
                .disabled(phase == .granted)
            }

            Button(action: onCancel) {
                Text(.notesKit("Cancel"))
                    .font(theme.modeFont)
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(theme.secondaryText)
                    .frame(height: 40)
            }
            .buttonStyle(NotePressButtonStyle())
        }
        .padding(.bottom, theme.large)
    }
}
