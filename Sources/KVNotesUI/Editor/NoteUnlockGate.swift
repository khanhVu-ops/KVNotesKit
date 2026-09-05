import KVNotesCore
import SwiftUI

struct NoteUnlockGate: View {
    let note: NoteDigest
    let offer: NoteUnlockOffer
    let isAuthenticating: Bool
    let denied: Bool
    let theme: NoteTheme
    let onUnlock: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            VStack(spacing: theme.large) {
                Spacer()
                Image(systemName: denied ? "exclamationmark.triangle" : biometricSymbol)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(denied ? theme.error : theme.primaryText)
                    .frame(width: 76, height: 76)
                    .overlay { RoundedRectangle(cornerRadius: theme.largeRadius).stroke(theme.separator) }
                Text(denied ? .notesKit("Not unlocked") : .notesKit("Unlocking private note"))
                    .font(theme.sectionFont).textCase(.uppercase).tracking(2).foregroundStyle(theme.primaryText)
                if !note.title.isEmpty { Text(verbatim: note.title).font(theme.monoFont).foregroundStyle(theme.secondaryText) }
                Spacer()
                Button(action: onUnlock) {
                    Label(isAuthenticating ? .notesKit("Authenticating…") : .notesKit("Unlock"), systemImage: "lock.open")
                        .font(theme.modeFont).foregroundStyle(theme.onAccent).frame(maxWidth: .infinity).frame(height: 48)
                        .background(theme.accent, in: Capsule())
                }.disabled(isAuthenticating)
                Button(.notesKit("Cancel"), action: onCancel).foregroundStyle(theme.secondaryText)
            }.padding(theme.large)
        }
    }

    private var biometricSymbol: String {
        switch offer.biometric { case .faceID: "faceid"; case .touchID: "touchid"; default: "lock" }
    }
}
