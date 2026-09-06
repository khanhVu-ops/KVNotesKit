import KVNotesCore
import SwiftUI

public enum NoteOptionsDestination: Hashable, Sendable {
    case icon
    case folder
    case export
    case details
}

struct NoteOptionsSheet: View {
    let icon: String?
    let folder: String?
    let folders: [String]
    let isLocked: Bool
    let hidesPreview: Bool
    let metrics: NoteMetrics?
    let initialDestination: NoteOptionsDestination?
    let theme: NoteTheme
    let haptic: @MainActor @Sendable () -> Void
    let onIcon: (String?) -> Void
    let onFolder: (String?) -> Void
    let onToggleLock: () -> Void
    let onToggleHiddenPreview: () -> Void
    let onDismiss: () -> Void
    let onExport: (@MainActor @Sendable (NoteExportFormat) -> Void)?

    init(
        icon: String?,
        folder: String?,
        folders: [String],
        isLocked: Bool,
        hidesPreview: Bool,
        metrics: NoteMetrics? = nil,
        initialDestination: NoteOptionsDestination? = nil,
        theme: NoteTheme,
        haptic: @escaping @MainActor @Sendable () -> Void = {},
        onIcon: @escaping (String?) -> Void,
        onFolder: @escaping (String?) -> Void,
        onToggleLock: @escaping () -> Void,
        onToggleHiddenPreview: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onExport: (@MainActor @Sendable (NoteExportFormat) -> Void)? = nil
    ) {
        self.icon = icon
        self.folder = folder
        self.folders = folders
        self.isLocked = isLocked
        self.hidesPreview = hidesPreview
        self.metrics = metrics
        self.initialDestination = initialDestination
        self.theme = theme
        self.haptic = haptic
        self.onIcon = onIcon
        self.onFolder = onFolder
        self.onToggleLock = onToggleLock
        self.onToggleHiddenPreview = onToggleHiddenPreview
        self.onDismiss = onDismiss
        self.onExport = onExport
    }

    @State private var path: [NoteOptionsDestination] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $path) {
            rootView
                .navigationDestination(for: NoteOptionsDestination.self) { destination in
                    switch destination {
                    case .icon:
                        NoteIconPickerView(
                            icon: icon,
                            theme: theme,
                            haptic: haptic,
                            onIcon: onIcon,
                            onDismiss: onDismiss
                        )
                    case .folder:
                        NoteFolderPickerView(
                            folder: folder,
                            folders: folders,
                            theme: theme,
                            haptic: haptic,
                            onFolder: onFolder,
                            onDismiss: onDismiss
                        )
                    case .export:
                        NoteExportOptionView(
                            theme: theme,
                            haptic: haptic,
                            onSelect: { format in
                                onDismiss()
                                onExport?(format)
                            },
                            onDismiss: onDismiss
                        )
                    case .details:
                        if let metrics {
                            NoteInspectorDetailView(
                                metrics: metrics,
                                theme: theme,
                                onDismiss: onDismiss
                            )
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.sheet)
        .presentationDragIndicator(.hidden)
        .onAppear {
            if let initialDestination {
                path = [initialDestination]
            }
        }
    }

    private var rootView: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: theme.medium) {
                    organizationCard
                    securitySection
                    actionsCard
                }
                .padding(.horizontal, theme.medium)
                .padding(.bottom, theme.large)
            }
            .scrollIndicators(.hidden)
        }
        .background(theme.sheet)
        .noteNavigationChrome()
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(.notesKit("Note options"))
                    .font(theme.titleFont)
                    .foregroundStyle(theme.primaryText)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            doneButton
        }
        .padding(.horizontal, theme.medium)
        .padding(.top, theme.large)
        .padding(.bottom, theme.small + 4)
    }

    private var doneButton: some View {
        Button(action: onDismiss) {
            Text(.notesKit("Done"))
                .font(theme.modeFont)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, theme.medium)
                .frame(height: 34)
                .background(theme.accent, in: Capsule())
        }
        .buttonStyle(NotePressButtonStyle())
    }

    private var organizationCard: some View {
        VStack(spacing: 0) {
            NavigationLink(value: NoteOptionsDestination.icon) {
                HStack(spacing: theme.small + 4) {
                    iconBadge(icon: icon)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(.notesKit("Icon"))
                            .font(theme.rowFont)
                            .foregroundStyle(theme.primaryText)
                        iconSubtitle
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                .padding(.horizontal, theme.small + 4)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(NotePressButtonStyle())

            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.75)
                .padding(.leading, 56)

            NavigationLink(value: NoteOptionsDestination.folder) {
                HStack(spacing: theme.small + 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: theme.smallRadius - 2, style: .continuous)
                            .fill(theme.accent.opacity(0.12))
                        Image(systemName: "folder")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.accent)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(.notesKit("Folder"))
                            .font(theme.rowFont)
                            .foregroundStyle(theme.primaryText)
                        if let folder {
                            Text(verbatim: folder)
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                        } else {
                            Text(.notesKit("No folder"))
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                .padding(.horizontal, theme.small + 4)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(NotePressButtonStyle())
        }
        .background {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .fill(theme.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 0.75)
        }
    }

    private func iconBadge(icon: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.smallRadius - 2, style: .continuous)
                .fill(theme.accent.opacity(0.12))
            if let icon, let parsed = NoteIcon.parse(icon) {
                switch parsed {
                case .emoji(let emoji):
                    Text(verbatim: emoji)
                        .font(.system(size: 16))
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.accent)
                }
            } else {
                Image(systemName: "textformat")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .frame(width: 32, height: 32)
    }

    @ViewBuilder
    private var iconSubtitle: some View {
        if let icon, let parsed = NoteIcon.parse(icon) {
            switch parsed {
            case .emoji(let emoji):
                Text(verbatim: emoji)
            case .symbol(let name):
                Text(verbatim: name)
            }
        } else {
            Text(.notesKit("Monogram"))
        }
    }

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: theme.xs + 2) {
            Text(.notesKit("Security"))
                .font(theme.metadataFont)
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, theme.xs)
                .accessibilityAddTraits(.isHeader)

            securityCard
        }
    }

    private var securityCard: some View {
        VStack(spacing: 0) {
            toggleRow(
                icon: isLocked ? "lock.fill" : "lock.open",
                tone: isLocked ? theme.success : theme.secondaryText,
                title: .notesKit("Lock this note"),
                caption: .notesKit("Even inside an unlocked vault, this note asks to unlock again before it opens."),
                isOn: isLocked,
                action: onToggleLock
            )

            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.75)
                .padding(.leading, 56)

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
        .background {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .fill(theme.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 0.75)
        }
    }

    private var actionsCard: some View {
        VStack(spacing: 0) {
            if onExport != nil {
                NavigationLink(value: NoteOptionsDestination.export) {
                    HStack(spacing: theme.small + 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: theme.smallRadius - 2, style: .continuous)
                                .fill(theme.accent.opacity(0.12))
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(theme.accent)
                        }
                        .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(.notesKit("Export note"))
                                .font(theme.rowFont)
                                .foregroundStyle(theme.primaryText)
                            Text(.notesKit("Export as Markdown"))
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(.horizontal, theme.small + 4)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NotePressButtonStyle())
            }

            if metrics != nil {
                if onExport != nil {
                    Rectangle()
                        .fill(theme.separator)
                        .frame(height: 0.75)
                        .padding(.leading, 56)
                }

                NavigationLink(value: NoteOptionsDestination.details) {
                    HStack(spacing: theme.small + 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: theme.smallRadius - 2, style: .continuous)
                                .fill(theme.accent.opacity(0.12))
                            Image(systemName: "info.circle")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(theme.accent)
                        }
                        .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(.notesKit("Note info"))
                                .font(theme.rowFont)
                                .foregroundStyle(theme.primaryText)
                            Text(.notesKit("Details"))
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(.horizontal, theme.small + 4)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NotePressButtonStyle())
            }
        }
        .background {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .fill(theme.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 0.75)
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
            withAnimation(NoteMotion.selection(reduceMotion: reduceMotion)) {
                action()
            }
        } label: {
            HStack(spacing: theme.small + 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: theme.smallRadius - 2, style: .continuous)
                        .fill(tone.opacity(isOn ? 0.18 : 0.08))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tone)
                }
                .frame(width: 32, height: 32)

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
            .padding(.horizontal, theme.small + 4)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotePressButtonStyle())
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - Subviews

struct NoteIconPickerView: View {
    let icon: String?
    let theme: NoteTheme
    let haptic: @MainActor @Sendable () -> Void
    let onIcon: (String?) -> Void
    let onDismiss: @MainActor @Sendable () -> Void

    @State private var selectedCategory: NoteIconLibrary.Category = .general
    @State private var customEmojiInput = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.small) {
                categoryPicker
                iconGrid
                if selectedCategory == .emoji {
                    customEmojiField
                }
            }
            .padding(.horizontal, theme.medium)
            .padding(.top, theme.small)
            .padding(.bottom, theme.large)
        }
        .scrollIndicators(.hidden)
        .background(theme.sheet)
        .onAppear {
            selectedCategory = NoteIconLibrary.category(for: icon)
            if let icon, NoteIcon.parse(icon)?.emoji != nil && !NoteIconLibrary.curatedEmojis.contains(icon) {
                customEmojiInput = icon
            }
        }
        .navigationTitle("")
        .noteInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(.notesKit("Icon"))
                    .font(theme.sectionFont)
                    .textCase(.uppercase)
                    .tracking(1.8)
                    .foregroundStyle(theme.primaryText)
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) { doneButton }
            #else
            ToolbarItem { doneButton }
            #endif
        }
    }

    private var doneButton: some View {
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
}

struct NoteFolderPickerView: View {
    let folder: String?
    let folders: [String]
    let theme: NoteTheme
    let haptic: @MainActor @Sendable () -> Void
    let onFolder: (String?) -> Void
    let onDismiss: @MainActor @Sendable () -> Void

    @State private var newFolder = ""
    @FocusState private var isNamingFolder: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.medium) {
                folderListCard
                newFolderField
            }
            .padding(.horizontal, theme.medium)
            .padding(.top, theme.small)
            .padding(.bottom, theme.large)
        }
        .scrollIndicators(.hidden)
        .background(theme.sheet)
        .navigationTitle("")
        .noteInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(.notesKit("Folder"))
                    .font(theme.sectionFont)
                    .textCase(.uppercase)
                    .tracking(1.8)
                    .foregroundStyle(theme.primaryText)
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) { doneButton }
            #else
            ToolbarItem { doneButton }
            #endif
        }
    }

    private var doneButton: some View {
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

    private var folderListCard: some View {
        VStack(spacing: 0) {
            folderRow(
                title: Text(.notesKit("No folder")),
                isSelected: folder == nil
            ) {
                onFolder(nil)
            }

            ForEach(folders, id: \.self) { name in
                Rectangle()
                    .fill(theme.separator)
                    .frame(height: 0.75)
                    .padding(.leading, 56)

                folderRow(
                    title: Text(verbatim: name),
                    isSelected: folder == name
                ) {
                    onFolder(name)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .fill(theme.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 0.75)
        }
    }

    private func folderRow(
        title: Text,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            haptic()
            withAnimation(NoteMotion.selection(reduceMotion: reduceMotion)) {
                action()
            }
        } label: {
            HStack(spacing: theme.small + 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: theme.smallRadius - 2, style: .continuous)
                        .fill(isSelected ? theme.accent.opacity(0.18) : theme.card)
                    Image(systemName: isSelected ? "folder.fill" : "folder")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isSelected ? theme.accent : theme.secondaryText)
                }
                .frame(width: 32, height: 32)

                title
                    .font(theme.rowFont)
                    .foregroundStyle(theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, theme.small + 4)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotePressButtonStyle())
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
}

struct NoteExportOptionView: View {
    let theme: NoteTheme
    var haptic: @MainActor @Sendable () -> Void = {}
    let onSelect: @MainActor @Sendable (NoteExportFormat) -> Void
    let onDismiss: @MainActor @Sendable () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.medium) {
                warningCard
                formatCards
            }
            .padding(.horizontal, theme.medium)
            .padding(.top, theme.small)
            .padding(.bottom, theme.large)
        }
        .scrollIndicators(.hidden)
        .background(theme.sheet)
        .navigationTitle("")
        .noteInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(.notesKit("Export note"))
                    .font(theme.sectionFont)
                    .textCase(.uppercase)
                    .tracking(1.8)
                    .foregroundStyle(theme.primaryText)
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) { doneButton }
            #else
            ToolbarItem { doneButton }
            #endif
        }
    }

    private var doneButton: some View {
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

    private var warningCard: some View {
        HStack(alignment: .top, spacing: theme.small + 2) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.warning)
                .frame(width: 24, height: 24)

            Text(.notesKit("The exported file will not be encrypted. Anyone with access to this file can read its contents."))
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(theme.small + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .fill(theme.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .strokeBorder(theme.warning.opacity(0.35), lineWidth: 0.75)
        }
    }

    private var formatCards: some View {
        VStack(spacing: 0) {
            formatRow(
                title: .notesKit("Export as Markdown"),
                badge: ".md",
                icon: "doc.text",
                format: .markdown
            )

            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.75)
                .padding(.leading, 56)

            formatRow(
                title: .notesKit("Export as Plain Text"),
                badge: ".txt",
                icon: "text.alignleft",
                format: .plainText
            )
        }
        .background {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .fill(theme.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 0.75)
        }
    }

    private func formatRow(
        title: LocalizedStringResource,
        badge: String,
        icon: String,
        format: NoteExportFormat
    ) -> some View {
        Button {
            haptic()
            onSelect(format)
        } label: {
            HStack(spacing: theme.small + 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: theme.smallRadius - 2, style: .continuous)
                        .fill(theme.accent.opacity(0.12))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.accent)
                }
                .frame(width: 32, height: 32)

                Text(title)
                    .font(theme.rowFont)
                    .foregroundStyle(theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(verbatim: badge)
                    .font(theme.monoFont)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.elevatedCard, in: Capsule())

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, theme.small + 4)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotePressButtonStyle())
    }
}

struct NoteInspectorDetailView: View {
    let metrics: NoteMetrics
    let theme: NoteTheme
    let onDismiss: @MainActor @Sendable () -> Void

    var body: some View {
        ScrollView {
            NoteInspectorView(metrics: metrics, theme: theme)
                .padding(.horizontal, theme.medium)
                .padding(.top, theme.small)
                .padding(.bottom, theme.large)
        }
        .scrollIndicators(.hidden)
        .background(theme.sheet)
        .navigationTitle("")
        .noteInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(.notesKit("Details"))
                    .font(theme.sectionFont)
                    .textCase(.uppercase)
                    .tracking(1.8)
                    .foregroundStyle(theme.primaryText)
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) { doneButton }
            #else
            ToolbarItem { doneButton }
            #endif
        }
    }

    private var doneButton: some View {
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
}

private struct LockSwitch: View {
    let isOn: Bool
    let theme: NoteTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(isOn ? theme.success : theme.elevatedCard)
            .frame(width: 48, height: 28)
            .overlay {
                Capsule()
                    .strokeBorder(theme.separator, lineWidth: isOn ? 0 : 0.75)
            }
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(theme.onAccent)
                    .frame(width: 22, height: 22)
                    .padding(3)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
            .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: isOn)
            .accessibilityHidden(true)
    }
}

#Preview {
    NoteOptionsSheet(
        icon: "🔑",
        folder: "Work",
        folders: ["Work", "Personal", "Finance"],
        isLocked: false,
        hidesPreview: false,
        metrics: nil,
        theme: .preview,
        haptic: {},
        onIcon: { _ in },
        onFolder: { _ in },
        onToggleLock: {},
        onToggleHiddenPreview: {},
        onDismiss: {}
    )
}
