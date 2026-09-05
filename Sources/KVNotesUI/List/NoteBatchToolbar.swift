import KVNotesCore
import SwiftUI

/// The action dock shown while notes are selected.
///
/// Same grammar as the photo grid's: a floating dock over the list, two named actions and a menu
/// for the rest, disabled rather than hidden when nothing is selected — a dock that appears and
/// disappears under the thumb moves every button the moment a row is ticked.
struct NoteBatchToolbar: View {
    let selectionCount: Int
    let wouldPin: Bool
    let wouldLock: Bool
    let folders: [String]
    let isBusy: Bool
    let theme: NoteTheme
    let onPin: @MainActor @Sendable () -> Void
    let onLock: @MainActor @Sendable () -> Void
    let onMoveToFolder: @MainActor @Sendable (String?) -> Void
    let onTrash: @MainActor @Sendable () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: theme.small))
            : AnyLayout(HStackLayout(spacing: theme.small))

        layout {
            Button(action: onPin) {
                label(
                    wouldPin ? .notesKit("Pin") : .notesKit("Unpin"),
                    icon: wouldPin ? "pin" : "pin.slash"
                )
                .foregroundStyle(theme.onAccent)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.smallRadius))
            }

            Button(action: onLock) {
                label(
                    wouldLock ? .notesKit("Lock") : .notesKit("Unlock"),
                    icon: wouldLock ? "lock" : "lock.open"
                )
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.smallRadius))
            }

            Menu {
                Section {
                    Button { onMoveToFolder(nil) } label: {
                        Label(.notesKit("No folder"), systemImage: "tray")
                    }
                    ForEach(folders, id: \.self) { name in
                        Button { onMoveToFolder(name) } label: {
                            Label(name, systemImage: "folder")
                        }
                    }
                } header: {
                    Text(.notesKit("Move to folder"))
                }
                Section {
                    Button(role: .destructive, action: onTrash) {
                        Label(.notesKit("Move to Trash"), systemImage: "trash")
                    }
                }
            } label: {
                label(.notesKit("More"), icon: "ellipsis")
                    .background(theme.card, in: RoundedRectangle(cornerRadius: theme.smallRadius))
            }
            .menuOrder(.fixed)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.primaryText)
        .padding(theme.small)
        .background {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                        .strokeBorder(theme.separator, lineWidth: 0.75)
                }
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        .disabled(isBusy || selectionCount == 0)
        .opacity(isBusy || selectionCount == 0 ? 0.45 : 1)
        .accessibilityElement(children: .contain)
    }

    private func label(_ title: LocalizedStringResource, icon: String) -> some View {
        VStack(spacing: theme.xs) {
            Image(systemName: icon).font(.system(size: 18, weight: .regular))
            Text(title)
                .font(theme.modeFont)
                .textCase(.uppercase)
                .tracking(1.1)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.horizontal, theme.xs)
        .contentShape(Rectangle())
    }
}

#Preview {
    NoteBatchToolbar(
        selectionCount: 3,
        wouldPin: true,
        wouldLock: true,
        folders: ["Banking", "Passwords"],
        isBusy: false,
        theme: .preview,
        onPin: {},
        onLock: {},
        onMoveToFolder: { _ in },
        onTrash: {}
    )
    .padding()
    .background(NoteTheme.preview.background)
}
