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
    /// Only one row can be renaming, so one focus flag covers the sheet.
    @FocusState private var isNamingFolder: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The folder mark's side, and with it the inset that lines the swatches up under the name
    /// rather than under the icon.
    private static let markSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if folders.isEmpty { empty } else { list }
        }
        .background(theme.sheet)
        // Renaming without a keyboard means tapping the field the user has just asked to edit.
        // The field is created in the same transaction that dismisses the menu, and focus asked
        // for before it exists is dropped silently — hence the hop rather than `onAppear`.
        .task(id: renaming) {
            guard renaming != nil else { return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            isNamingFolder = true
        }
        .noteConfirmOverlay(
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            title: .notesKit("Remove this folder?"),
            message: .notesKit("The notes in it stay in the vault, with no folder."),
            confirmTitle: .notesKit("Remove folder"),
            icon: "folder.badge.minus",
            theme: theme,
            reduceMotion: reduceMotion,
            onConfirm: {
                let folder = removing
                withAnimation(NoteMotion.mode(reduceMotion: reduceMotion)) { removing = nil }
                if let folder { onRemove(folder) }
            },
            onCancel: {
                withAnimation(NoteMotion.mode(reduceMotion: reduceMotion)) { removing = nil }
            }
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
        // No grabber above this, so the title needs the top margin the grabber used to occupy.
        .padding(.top, theme.large)
        .padding(.bottom, theme.small + 4)
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
            VStack(spacing: theme.small + 2) {
                ForEach(folders, id: \.self) { folder in row(folder) }
            }
            .padding(.horizontal, theme.medium)
            .padding(.bottom, theme.extraLarge)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: isBusy)
    }

    /// One folder as a card that carries its own colour.
    ///
    /// The tint used to be a swatch beside the name; here it washes the card, the mark and the
    /// border, so a coloured folder is recognisable before any of the words are read — which is
    /// the whole point of letting a folder have a colour.
    @ViewBuilder
    private func row(_ folder: String) -> some View {
        let tint = tints[folder] ?? .neutral
        let color = theme.color(for: tint)
        let isTinted = tint != .neutral
        let textInset = Self.markSize + theme.small + 2

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.small + 2) {
                folderMark(tint: tint)

                if renaming == folder {
                    renameField(folder)
                } else {
                    label(folder)
                }

                Spacer(minLength: theme.xs)

                trailingControl(folder)
            }
            .frame(minHeight: 44)

            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.75)
                .padding(.top, theme.small + 2)
                .padding(.leading, textInset)

            tintRow(folder, current: tint)
                .padding(.top, theme.small)
                .padding(.leading, textInset)
        }
        .padding(theme.small + 4)
        .background {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .fill(theme.card)
                .overlay {
                    RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                        .fill(LinearGradient(
                            colors: [color.opacity(isTinted ? 0.16 : 0), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .strokeBorder(isTinted ? color.opacity(0.32) : theme.separator, lineWidth: 0.75)
        }
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: renaming)
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: tint)
    }

    private func label(_ folder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: folder)
                .font(theme.rowFont)
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
            Text(.notesKit(count: "\(counts[folder] ?? 0) notes"))
                .font(theme.metadataFont)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(theme.disabledText)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    private func renameField(_ folder: String) -> some View {
        TextField(text: $draftName) { Text(.notesKit("Folder name")) }
            .textFieldStyle(.plain)
            .font(theme.rowFont)
            .foregroundStyle(theme.primaryText)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($isNamingFolder)
            .onSubmit { commitRename(folder) }
            .padding(.horizontal, theme.small + 2)
            .frame(height: 38)
            .background(theme.elevatedCard, in: Capsule())
            .overlay { Capsule().strokeBorder(theme.accent.opacity(0.55), lineWidth: 1) }
            .transition(.opacity)
    }

    private func folderMark(tint: NoteFolderTint) -> some View {
        let color = theme.color(for: tint)
        let isTinted = tint != .neutral
        return ZStack {
            RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous)
                .fill(color.opacity(isTinted ? 0.18 : 0.10))
            RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous)
                .strokeBorder(color.opacity(isTinted ? 0.34 : 0.16), lineWidth: 0.75)
            Image(systemName: "folder.fill")
                .font(.system(size: 16))
                .foregroundStyle(color)
        }
        .frame(width: Self.markSize, height: Self.markSize)
    }

    @ViewBuilder
    private func trailingControl(_ folder: String) -> some View {
        if renaming == folder {
            HStack(spacing: theme.xs + 2) {
                iconButton(symbol: "xmark", tone: theme.secondaryText, background: theme.elevatedCard) {
                    cancelRename()
                }
                .accessibilityLabel(Text(.notesKit("Cancel")))

                iconButton(symbol: "checkmark", tone: theme.onAccent, background: theme.accent) {
                    commitRename(folder)
                }
                .accessibilityLabel(Text(.notesKit("Save")))
            }
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        } else {
            Menu {
                Button {
                    draftName = folder
                    renaming = folder
                } label: {
                    Label(.notesKit("Rename"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    withAnimation(NoteMotion.mode(reduceMotion: reduceMotion)) { removing = folder }
                } label: {
                    Label(.notesKit("Remove folder"), systemImage: "folder.badge.minus")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(theme.elevatedCard, in: Circle())
                    .overlay { Circle().strokeBorder(theme.separator, lineWidth: 0.75) }
            }
            .accessibilityLabel(Text(.notesKit("Folder options")))
            .transition(.opacity)
        }
    }

    /// Labelled `symbol:` rather than taking the name unlabelled: `check-l10n.sh` reads any
    /// `Button("…")` as user-facing copy, and `iconButton("checkmark")` ends in exactly that.
    private func iconButton(
        symbol: String,
        tone: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tone)
                .frame(width: 34, height: 34)
                .background(background, in: Circle())
        }
        .buttonStyle(NotePressButtonStyle())
    }

    private func tintRow(_ folder: String, current: NoteFolderTint) -> some View {
        HStack(spacing: theme.xs) {
            ForEach(NoteFolderTint.allCases, id: \.self) { tint in
                Button {
                    haptic()
                    onTint(folder, tint)
                } label: {
                    swatch(tint, isCurrent: tint == current)
                }
                .buttonStyle(NotePressButtonStyle())
                .accessibilityLabel(Text(.notesKit(tintName(tint))))
                .accessibilityAddTraits(tint == current ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: current)
    }

    private func swatch(_ tint: NoteFolderTint, isCurrent: Bool) -> some View {
        ZStack {
            if tint == .neutral {
                // "No colour" is the absence of one. Drawn as an empty ring struck through rather
                // than as a grey disc, which reads as a sixth colour sitting next to the five.
                Circle()
                    .strokeBorder(theme.disabledText, lineWidth: 1.2)
                    .frame(width: 18, height: 18)
                // A chord through the centre at 45° is exactly the diameter, so it lands on the
                // ring at both ends without any clipping.
                Rectangle()
                    .fill(theme.disabledText)
                    .frame(width: 18, height: 1.2)
                    .rotationEffect(.degrees(-45))
            } else {
                Circle()
                    .fill(theme.color(for: tint))
                    .frame(width: 18, height: 18)
            }

            if isCurrent {
                // A ring outside the swatch rather than a border on it: a border eats into the
                // colour it is meant to be confirming.
                Circle()
                    .strokeBorder(theme.primaryText, lineWidth: 1.5)
                    .frame(width: 27, height: 27)
            }
        }
        .frame(width: 32, height: 32)
        .contentShape(Circle())
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

    private func cancelRename() {
        isNamingFolder = false
        renaming = nil
        draftName = ""
    }

    private func commitRename(_ folder: String) {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        isNamingFolder = false
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
