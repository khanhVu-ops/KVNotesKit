import SwiftUI

/// The one way this flow asks "are you sure".
///
/// A sheet rather than a confirmation dialog: on iPad and on a Mac a dialog is a popover anchored
/// to whatever was tapped, which for a swipe action is a row that is already sliding away, and its
/// buttons are system-styled in the middle of a screen that is not. A sheet lands in the same
/// place every time, in this flow's own type and colours, and reads its message at a size a person
/// can take in before tapping the destructive button.
struct NoteConfirmSheet: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let confirmTitle: LocalizedStringResource
    let icon: String
    let isDestructive: Bool
    let theme: NoteTheme
    let onConfirm: @MainActor @Sendable () -> Void
    let onCancel: @MainActor @Sendable () -> Void

    var body: some View {
        VStack(spacing: theme.medium) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(isDestructive ? theme.error : theme.primaryText)
                .frame(width: 64, height: 64)
                .overlay {
                    Circle().strokeBorder(
                        (isDestructive ? theme.error : theme.separator).opacity(isDestructive ? 0.35 : 1),
                        lineWidth: 0.75
                    )
                }
                .padding(.top, theme.large)

            VStack(spacing: theme.xs) {
                Text(title)
                    .font(theme.titleFont)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.primaryText)
                Text(message)
                    .font(theme.bodyFont)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, theme.medium)

            Spacer(minLength: theme.small)

            VStack(spacing: theme.small) {
                Button(action: onConfirm) {
                    Text(confirmTitle)
                        .font(theme.modeFont)
                        .textCase(.uppercase)
                        .tracking(1.3)
                        .foregroundStyle(isDestructive ? theme.onAccent : theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(isDestructive ? theme.error : theme.accent, in: Capsule())
                }
                .buttonStyle(NotePressButtonStyle())

                Button(action: onCancel) {
                    Text(.notesKit("Cancel"))
                        .font(theme.modeFont)
                        .textCase(.uppercase)
                        .tracking(1.3)
                        .foregroundStyle(theme.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(theme.card, in: Capsule())
                        .overlay { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
                }
                .buttonStyle(NotePressButtonStyle())
            }
            .padding(.horizontal, theme.medium)
            .padding(.bottom, theme.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.sheet)
    }
}

extension View {
    /// Presents the same confirmation *inside* the current sheet rather than on top of it.
    ///
    /// A sheet presented from a sheet replaces what is under it, so cancelling a folder removal
    /// would have left the user on the list with the folder manager gone. An overlay keeps the
    /// screen they were working in behind the question, which is also what makes "cancel" mean
    /// what it says.
    func noteConfirmOverlay(
        isPresented: Binding<Bool>,
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        confirmTitle: LocalizedStringResource,
        icon: String = "trash",
        isDestructive: Bool = true,
        theme: NoteTheme,
        reduceMotion: Bool,
        onConfirm: @escaping @MainActor @Sendable () -> Void,
        onCancel: @escaping @MainActor @Sendable () -> Void
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture(perform: onCancel)
                        .transition(.opacity)

                    NoteConfirmSheet(
                        title: title,
                        message: message,
                        confirmTitle: confirmTitle,
                        icon: icon,
                        isDestructive: isDestructive,
                        theme: theme,
                        onConfirm: onConfirm,
                        onCancel: onCancel
                    )
                    .frame(maxHeight: 380)
                    .clipShape(RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous))
                    .padding(theme.small)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(NoteMotion.mode(reduceMotion: reduceMotion), value: isPresented.wrappedValue)
    }

    /// Presents a confirmation over this view, sized to its content.
    func noteConfirmSheet(
        isPresented: Binding<Bool>,
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        confirmTitle: LocalizedStringResource,
        icon: String = "trash",
        isDestructive: Bool = true,
        theme: NoteTheme,
        onConfirm: @escaping @MainActor @Sendable () -> Void,
        onCancel: @escaping @MainActor @Sendable () -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            NoteConfirmSheet(
                title: title,
                message: message,
                confirmTitle: confirmTitle,
                icon: icon,
                isDestructive: isDestructive,
                theme: theme,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
            .presentationDetents([.height(380)])
        }
    }
}

#Preview {
    NoteConfirmSheet(
        title: "Move this note to Recently Deleted?",
        message: "It stays in the vault's trash until you empty it.",
        confirmTitle: "Move to Trash",
        icon: "trash",
        isDestructive: true,
        theme: .preview,
        onConfirm: {},
        onCancel: {}
    )
}
