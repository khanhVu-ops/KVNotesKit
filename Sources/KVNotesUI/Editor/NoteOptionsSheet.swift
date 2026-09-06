import KVNotesCore
import SwiftUI

struct NoteOptionsSheet: View {
    let icon: String?
    let folder: String?
    let folders: [String]
    let isLocked: Bool
    let hidesPreview: Bool
    var metrics: NoteMetrics? = nil
    let theme: NoteTheme
    let haptic: @MainActor @Sendable () -> Void
    let onIcon: (String?) -> Void
    let onFolder: (String?) -> Void
    let onToggleLock: () -> Void
    let onToggleHiddenPreview: () -> Void
    let onDismiss: () -> Void

    @State private var selectedCategory: NoteIconLibrary.Category = .general
    @State private var customEmojiInput = ""
    @State private var newFolder = ""
    @FocusState private var isNamingFolder: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.large) {
                iconSection
                folderSection
                securitySection
                if let metrics {
                    detailsSection(metrics)
                }
            }
            .padding(.horizontal, theme.medium)
            .padding(.top, theme.small)
            .padding(.bottom, theme.extraLarge)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(theme.sheet)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.sheet)
        .onAppear {
            selectedCategory = NoteIconLibrary.category(for: icon)
            if let icon, NoteIcon.parse(icon)?.emoji != nil && !NoteIconLibrary.curatedEmojis.contains(icon) {
                customEmojiInput = icon
            }
        }
    }

    private var header: some View {
        HStack {
            Text(.notesKit("Note options"))
                .font(theme.sectionFont)
                .textCase(.uppercase)
                .tracking(1.8)
                .foregroundStyle(theme.primaryText)
            Spacer()
            Button(action: onDismiss) {
                Text(.notesKit("Done"))
                    .font(theme.modeFont)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, theme.medium)
                    .frame(height: 32)
                    .background(theme.accent, in: Capsule())
            }
            .buttonStyle(NotePressButtonStyle())
        }
        .padding(.horizontal, theme.medium)
        .padding(.vertical, theme.small + 4)
        .background(theme.sheet)
    }

    private var iconSection: some View {
        section(.notesKit("Icon")) {
            VStack(alignment: .leading, spacing: theme.small) {
                categoryPicker
                iconGrid
                if selectedCategory == .emoji {
                    customEmojiField
                }
            }
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.xs + 2) {
                ForEach(NoteIconLibrary.Category.allCases) { cat in
                    let isSelected = selectedCategory == cat
                    Button {
                        haptic()
                        withAnimation(NoteMotion.selection(reduceMotion: reduceMotion)) {
                            selectedCategory = cat
                        }
                    } label: {
                        categoryTitle(cat)
                            .font(theme.modeFont)
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .foregroundStyle(isSelected ? theme.onAccent : theme.secondaryText)
                            .padding(.horizontal, theme.small + 4)
                            .frame(height: 32)
                            .background {
                                if isSelected { Capsule().fill(theme.accent) }
                                else { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
                            }
                    }
                    .buttonStyle(NotePressButtonStyle())
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
    }

    private func categoryTitle(_ category: NoteIconLibrary.Category) -> Text {
        switch category {
        case .general: Text(.notesKit("General"))
        case .security: Text(.notesKit("Security"))
        case .finance: Text(.notesKit("Finance"))
        case .work: Text(.notesKit("Work"))
        case .tech: Text(.notesKit("Tech"))
        case .places: Text(.notesKit("Places"))
        case .emoji: Text(.notesKit("Emoji"))
        }
    }

    private var iconGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: theme.small), count: 6),
            spacing: theme.small
        ) {
            monogramTile
            if selectedCategory == .emoji {
                ForEach(NoteIconLibrary.curatedEmojis, id: \.self) { emojiTile($0) }
            } else {
                ForEach(NoteIconLibrary.symbols(for: selectedCategory), id: \.self) { symbolTile($0) }
            }
        }
    }

    private var monogramTile: some View {
        Button {
            haptic()
            customEmojiInput = ""
            onIcon(nil)
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(icon == nil ? theme.onAccent : theme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(tileBackground(isSelected: icon == nil))
        }
        .buttonStyle(NotePressButtonStyle())
        .accessibilityLabel(Text(.notesKit("Monogram")))
        .accessibilityAddTraits(icon == nil ? [.isSelected] : [])
    }

    private func symbolTile(_ symbolName: String) -> some View {
        let rawCandidate = "\(NoteIcon.symbolPrefix)\(symbolName)"
        let isSelected = icon == rawCandidate
        return Button {
            haptic()
            customEmojiInput = ""
            onIcon(isSelected ? nil : rawCandidate)
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isSelected ? theme.onAccent : theme.primaryText)
                .scaleEffect(isSelected && !reduceMotion ? 1.12 : 1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(tileBackground(isSelected: isSelected))
        }
        .buttonStyle(NotePressButtonStyle())
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func emojiTile(_ candidate: String) -> some View {
        let isSelected = icon == candidate
        return Button {
            haptic()
            if isSelected {
                onIcon(nil)
                customEmojiInput = ""
            } else {
                onIcon(candidate)
                customEmojiInput = ""
            }
        } label: {
            Text(verbatim: candidate)
                .font(.system(size: 20))
                .scaleEffect(isSelected && !reduceMotion ? 1.12 : 1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(tileBackground(isSelected: isSelected))
        }
        .buttonStyle(NotePressButtonStyle())
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var customEmojiField: some View {
        HStack(spacing: theme.small) {
            if let custom = NoteIconSanitizer.sanitizeEmoji(customEmojiInput), icon == custom {
                Text(verbatim: custom)
                    .font(.system(size: 18))
                    .frame(width: 28, height: 28)
                    .background(theme.accent, in: Circle())
            } else {
                Image(systemName: "face.smiling")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.secondaryText)
            }

            TextField(
                text: Binding(
                    get: { customEmojiInput },
                    set: { newValue in
                        handleCustomEmojiChange(newValue)
                    }
                ),
                prompt: Text(.notesKit("Custom emoji")).foregroundStyle(theme.disabledText)
            ) { Text(.notesKit("Custom emoji")) }
                .textFieldStyle(.plain)
                .font(theme.monoFont)
                .foregroundStyle(theme.primaryText)
                .submitLabel(.done)

            if !customEmojiInput.isEmpty {
                Button {
                    haptic()
                    customEmojiInput = ""
                    if !NoteIconLibrary.curatedEmojis.contains(icon ?? "") && NoteIcon.parse(icon)?.emoji != nil {
                        onIcon(nil)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(.notesKit("Cancel")))
            }
        }
        .padding(.horizontal, theme.small + 4)
        .frame(height: 40)
        .background(theme.card, in: Capsule())
        .overlay { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
    }

    private func handleCustomEmojiChange(_ input: String) {
        if let sanitized = NoteIconSanitizer.sanitizeEmoji(input) {
            haptic()
            customEmojiInput = sanitized
            onIcon(sanitized)
        } else if input.isEmpty {
            customEmojiInput = ""
            if !NoteIconLibrary.curatedEmojis.contains(icon ?? "") && NoteIcon.parse(icon)?.emoji != nil {
                onIcon(nil)
            }
        } else {
            customEmojiInput = String(input.prefix(1))
        }
    }

    private func tileBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous)
            .fill(isSelected ? theme.accent : theme.card)
            .overlay {
                RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : theme.separator, lineWidth: 0.75)
            }
    }

    private var folderSection: some View {
        section(.notesKit("Folder")) {
            VStack(alignment: .leading, spacing: theme.small) {
                FlowRow(spacing: theme.xs + 2) {
                    folderChip(title: Text(.notesKit("No folder")), isSelected: folder == nil) {
                        onFolder(nil)
                    }
                    ForEach(folders, id: \.self) { name in
                        folderChip(title: Text(verbatim: name), isSelected: folder == name) {
                            onFolder(name)
                        }
                    }
                }
                newFolderField
            }
        }
    }

    private func folderChip(title: Text, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            haptic()
            action()
        } label: {
            title
                .font(theme.modeFont)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(isSelected ? theme.onAccent : theme.secondaryText)
                .padding(.horizontal, theme.small + 4)
                .frame(height: 34)
                .background {
                    if isSelected { Capsule().fill(theme.accent) }
                    else { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
                }
        }
        .buttonStyle(NotePressButtonStyle())
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var newFolderField: some View {
        HStack(spacing: theme.small) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
            TextField(
                text: $newFolder,
                prompt: Text(.notesKit("New folder")).foregroundStyle(theme.disabledText)
            ) { Text(.notesKit("New folder")) }
                .textFieldStyle(.plain)
                .font(theme.monoFont)
                .foregroundStyle(theme.primaryText)
                .focused($isNamingFolder)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .onSubmit(commitNewFolder)

            if !newFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: commitNewFolder) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Text(.notesKit("Done")))
            }
        }
        .padding(.horizontal, theme.small + 4)
        .frame(height: 40)
        .background(theme.card, in: Capsule())
        .overlay { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: newFolder.isEmpty)
    }

    private func commitNewFolder() {
        let name = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        haptic()
        onFolder(name)
        newFolder = ""
        isNamingFolder = false
    }

    /// Two settings, deliberately in the same section and deliberately not the same size.
    ///
    /// The lock is the strong one and costs a prompt on every open. Hiding the preview is the
    /// cheap one and the one most notes actually want: the list stops drawing the opening line,
    /// and nothing else changes. Their captions have to say which is which, because a person
    /// choosing between them is choosing how much friction to buy.
    private var securitySection: some View {
        section(.notesKit("Security")) {
            VStack(spacing: theme.small) {
                toggleRow(
                    icon: isLocked ? "lock.fill" : "lock.open",
                    tone: isLocked ? theme.success : theme.secondaryText,
                    title: .notesKit("Lock this note"),
                    caption: .notesKit("Even inside an unlocked vault, this note asks to unlock again before it opens."),
                    isOn: isLocked,
                    action: onToggleLock
                )

                toggleRow(
                    icon: hidesPreview ? "eye.slash.fill" : "eye",
                    tone: hidesPreview ? theme.success : theme.secondaryText,
                    title: .notesKit("Hide preview"),
                    caption: isLocked
                        ? .notesKit("The lock already hides it. This is what the list shows if you unlock the note again.")
                        : .notesKit("The list shows this note's name and nothing else. It still opens with one tap."),
                    isOn: hidesPreview,
                    action: onToggleHiddenPreview
                )
            }
        }
    }

    private func toggleRow(
        icon: String,
        tone: Color,
        title: LocalizedStringResource,
        caption: LocalizedStringResource,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            haptic()
            action()
        } label: {
            HStack(spacing: theme.small + 4) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(tone)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(theme.rowFont)
                        .foregroundStyle(theme.primaryText)
                    Text(caption)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: theme.small)
                LockSwitch(isOn: isOn, theme: theme)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .noteCard(theme: theme, padding: theme.small + 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotePressButtonStyle())
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func section<Content: View>(
        _ title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.small) {
            Text(title)
                .font(theme.sectionFont)
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(theme.secondaryText)
            content()
        }
    }

    private func detailsSection(_ metrics: NoteMetrics) -> some View {
        section(.notesKit("Details")) {
            NoteInspectorView(metrics: metrics, theme: theme)
        }
    }
}

private struct LockSwitch: View {
    let isOn: Bool
    let theme: NoteTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(isOn ? theme.success : theme.elevatedCard)
            .frame(width: 46, height: 28)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(theme.onAccent)
                    .frame(width: 22, height: 22)
                    .padding(3)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            }
            .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: isOn)
            .accessibilityHidden(true)
    }
}

struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = layout(subviews: subviews, in: width)
        return CGSize(width: width, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in layout(subviews: subviews, in: bounds.width) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private struct Row {
        var y: CGFloat
        var height: CGFloat
        var items: [(index: Int, x: CGFloat, size: CGSize)]
    }

    private func layout(subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row(y: 0, height: 0, items: [])
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing, height: 0, items: [])
                x = 0
            }
            current.items.append((index, x, size))
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
