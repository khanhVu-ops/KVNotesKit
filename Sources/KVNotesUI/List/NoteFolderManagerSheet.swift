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
        .confirmationDialog(
            Text(.notesKit("Remove this folder?")),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button(.notesKit("Remove folder"), role: .destructive) {
                if let removing { onRemove(removing) }
                removing = nil
            }
            Button(.notesKit("Cancel"), role: .cancel) { removing = nil }
        } message: {
            Text(.notesKit("The notes in it stay in the vault, with no folder."))
        }
    }

    private var header: some View {
        HStack {
            Text(.notesKit("Folders"))
                .font(theme.sectionFont)
                .textCase(.uppercase)
                .tracking(1.6)
                .foregroundStyle(theme.primaryText)
            Spacer()
            Button(action: onDismiss) {
                Text(.notesKit("Done"))
                    .font(theme.modeFont)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(theme.primaryText)
            }
            .buttonStyle(NotePressButtonStyle())
        }
        .padding(theme.medium)
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
            HStack(spacing: theme.small) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.color(for: tint))

                if renaming == folder {
                    TextField(text: $draftName) { Text(.notesKit("Folder name")) }
                        .textFieldStyle(.plain)
                        .font(theme.rowFont)
                        .foregroundStyle(theme.primaryText)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { commitRename(folder) }
                } else {
                    Text(verbatim: folder)
                        .font(theme.rowFont)
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
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
                    Text(.notesKit(count: "\(counts[folder] ?? 0) notes"))
                        .font(theme.metadataFont)
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(theme.disabledText)

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
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 32, height: 32)
                    }
                }
            }

            tintRow(folder, current: tint)
        }
        .noteCard(theme: theme, padding: theme.small + 4)
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: renaming)
    }

    private func tintRow(_ folder: String, current: NoteFolderTint) -> some View {
        HStack(spacing: theme.small) {
            ForEach(NoteFolderTint.allCases, id: \.self) { tint in
                Button {
                    haptic()
                    onTint(folder, tint)
                } label: {
                    Circle()
                        .fill(theme.color(for: tint))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle().strokeBorder(
                                tint == current ? theme.primaryText : theme.separator,
                                lineWidth: tint == current ? 2 : 0.75
                            )
                        }
                        .opacity(tint == .neutral ? 0.5 : 1)
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
