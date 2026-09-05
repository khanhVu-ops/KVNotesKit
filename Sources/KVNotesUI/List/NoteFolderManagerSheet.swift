import KVNotesCore
import SwiftUI

/// Rename, recolour and remove folders.
///
/// A folder here is not a record — it is the set of notes that name it — so every action in this
/// sheet writes those notes. That is why removing one is not destructive: the label comes off,
/// the notes stay, and the sheet says so rather than making the user guess.
struct NoteFolderManagerSheet: View {
    let folders: [String]
    let counts: [String: Int]
    let tints: [String: NoteFolderTint]
    let isBusy: Bool
    let theme: NoteTheme
    let haptic: @MainActor @Sendable () -> Void
    let onRename: @MainActor @Sendable (String, String) -> Void
    let onTint: @MainActor @Sendable (String, NoteFolderTint) -> Void
    let onRemove: @MainActor @Sendable (String) -> Void
    let onDismiss: @MainActor @Sendable () -> Void

    @State private var renaming: String?
    @State private var draftName = ""
    @State private var removing: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if folders.isEmpty { empty } else { list }
        }
        .background(theme.sheet)
        .noteConfirmOverlay(
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            title: .notesKit("Remove this folder?"),
            message: .notesKit("The notes in it stay in the vault, with no folder."),
            confirmTitle: .notesKit("Remove folder"),
            icon: "folder.badge.minus",
            theme: theme,
            reduceMotion: reduceMotion,
            onConfirm: {
                if let removing { onRemove(removing) }
                removing = nil
            },
            onCancel: { removing = nil }
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(.notesKit("Folders"))
                    .font(theme.titleFont)
                    .foregroundStyle(theme.primaryText)
                Text(.notesKit(count: "\(folders.count) folders"))
                    .font(theme.metadataFont)
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(theme.secondaryText)
                    .contentTransition(.numericText())
            }
            Spacer()
            Button(action: onDismiss) {
                Text(.notesKit("Done"))
                    .font(theme.modeFont)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, theme.medium)
                    .frame(height: 36)
                    .background(theme.accent, in: Capsule())
            }
            .buttonStyle(NotePressButtonStyle())
        }
        .padding(.horizontal, theme.medium)
        .padding(.top, theme.medium)
        .padding(.bottom, theme.small)
    }

    private var empty: some View {
        VStack(spacing: theme.small) {
            Image(systemName: "folder")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.secondaryText)
            Text(.notesKit("No folders yet"))
                .font(theme.bodyFont)
                .foregroundStyle(theme.secondaryText)
            Text(.notesKit("A folder appears as soon as a note claims one."))
                .font(theme.captionFont)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.disabledText)
        }
        .frame(maxWidth: .infinity)
        .padding(theme.large)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: theme.small) {
                ForEach(folders, id: \.self) { folder in row(folder) }
            }
            .padding(.horizontal, theme.medium)
            .padding(.bottom, theme.extraLarge)
        }
        .scrollIndicators(.hidden)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
    }

    @ViewBuilder
    private func row(_ folder: String) -> some View {
        let tint = tints[folder] ?? .neutral
        VStack(alignment: .leading, spacing: theme.small) {
            HStack(spacing: theme.small + 2) {
                // The tint reads as the folder's own colour, not as decoration beside it.
                ZStack {
                    RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous)
                        .fill(theme.color(for: tint).opacity(tint == .neutral ? 0.12 : 0.18))
                    Image(systemName: "folder.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.color(for: tint))
                }
                .frame(width: 36, height: 36)

                if renaming == folder {
                    TextField(text: $draftName) { Text(.notesKit("Folder name")) }
                        .textFieldStyle(.plain)
                        .font(theme.rowFont)
                        .foregroundStyle(theme.primaryText)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { commitRename(folder) }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: folder)
                            .font(theme.rowFont)
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                        Text(.notesKit(count: "\(counts[folder] ?? 0) notes"))
                            .font(theme.metadataFont)
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .foregroundStyle(theme.disabledText)
                    }
                }

                Spacer(minLength: theme.small)

                if renaming == folder {
                    Button { commitRename(folder) } label: {
                        Text(.notesKit("Save"))
                            .font(theme.modeFont)
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(NotePressButtonStyle())
                } else {
                    Menu {
                        Button {
                            draftName = folder
                            renaming = folder
                        } label: {
                            Label(.notesKit("Rename"), systemImage: "pencil")
                        }
                        Button(role: .destructive) { removing = folder } label: {
                            Label(.notesKit("Remove folder"), systemImage: "folder.badge.minus")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 36, height: 36)
                            .background(theme.elevatedCard, in: Circle())
                    }
                    .accessibilityLabel(Text(.notesKit("Folder options")))
                }
            }

            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.75)

            tintRow(folder, current: tint)
        }
        .noteCard(theme: theme, padding: theme.small + 4)
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: renaming)
    }

    private func tintRow(_ folder: String, current: NoteFolderTint) -> some View {
        HStack(spacing: theme.xs) {
            ForEach(NoteFolderTint.allCases, id: \.self) { tint in
                Button {
                    haptic()
                    onTint(folder, tint)
                } label: {
                    ZStack {
                        Circle()
                            .fill(theme.color(for: tint).opacity(tint == .neutral ? 0.35 : 1))
                            .frame(width: 20, height: 20)
                        if tint == current {
                            // A ring outside the swatch rather than a border on it: a border eats
                            // into the colour it is meant to be confirming.
                            Circle()
                                .strokeBorder(theme.primaryText, lineWidth: 1.5)
                                .frame(width: 28, height: 28)
                        }
                    }
                }
                .buttonStyle(NotePressButtonStyle())
                .frame(width: 32, height: 32)
                .accessibilityLabel(Text(.notesKit(tintName(tint))))
                .accessibilityAddTraits(tint == current ? [.isSelected] : [])
            }
        }
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: current)
    }

    private func tintName(_ tint: NoteFolderTint) -> String {
        switch tint {
        case .neutral: "No colour"
        case .amber: "Amber"
        case .rose: "Rose"
        case .violet: "Violet"
        case .teal: "Teal"
        case .green: "Green"
        }
    }

    private func commitRename(_ folder: String) {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !trimmed.isEmpty, trimmed != folder else { return }
        onRename(folder, trimmed)
    }
}

#Preview {
    NoteFolderManagerSheet(
        folders: ["Banking", "Passwords"],
        counts: ["Banking": 3, "Passwords": 1],
        tints: ["Banking": .teal],
        isBusy: false,
        theme: .preview,
        haptic: {},
        onRename: { _, _ in },
        onTint: { _, _ in },
        onRemove: { _ in },
        onDismiss: {}
    )
}
