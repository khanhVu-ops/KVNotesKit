import KVNotesCore
import SwiftUI

/// Everything above the notes list: the control row, the title, the count line, the search
/// field and the folder chips.
///
/// Its own view rather than a `@ViewBuilder` on the screen, and the reason is the fold. The
/// header is the one part of this screen that changes while the list is being scrolled, and a
/// property on the screen changes the screen — every row, every sheet, the whole body. Reading
/// the fold here means a fold redraws a header.
///
/// Values and closures, never the ViewModel: the header is drawn from eleven facts, and taking
/// them one by one is what makes it previewable in both states without a store behind it.
struct NotesListHeader: View {
    /// The one reference the header holds, and the one thing it is allowed to read while the
    /// list is moving.
    let collapse: NotesHeaderCollapse
    let theme: NoteTheme
    @Binding var searchText: String
    let isSelecting: Bool
    let isEverythingSelected: Bool
    let selectionCount: Int
    let noteCount: Int
    let hasVisibleNotes: Bool
    let isNarrowed: Bool
    let layout: NoteListLayout
    let folderChips: [NotesListState.FolderChip]
    let folderTints: [String: NoteFolderTint]
    let selectedFolder: String?
    let haptic: @MainActor @Sendable () -> Void
    let onClose: @MainActor @Sendable () -> Void
    let onCreateNote: @MainActor @Sendable () -> Void
    let onStartSelecting: @MainActor @Sendable () -> Void
    let onStopSelecting: @MainActor @Sendable () -> Void
    let onSelectAllOrNone: @MainActor @Sendable () -> Void
    let onOpenSortAndFilter: @MainActor @Sendable () -> Void
    let onToggleLayout: @MainActor @Sendable () -> Void
    let onSelectFolder: @MainActor @Sendable (String?) -> Void
    let onOpenFolderManager: @MainActor @Sendable () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The natural height of the block that folds away, measured rather than assumed.
    ///
    /// Vault Home can write `18.0 * (1 - p)` because its totals row is one line of a fixed size.
    /// This block is a title and a count line in Dynamic Type fonts, so its height belongs to the
    /// reader, not to the source. `nil` until the first measurement, which is also what tells the
    /// frame below to leave the block at its natural height for that first pass.
    @State private var foldingBlockHeight: CGFloat?

    /// Everything about the header that is allowed to animate, behind one value.
    ///
    /// One `.animation(_:value:)` for the whole header and not six scattered through it, which is
    /// not tidiness. The modifier sets the animation for its subtree when its own value changed
    /// and clears it when it did not, so a second one nested underneath cancels the first for its
    /// own subtree — two of them here used to wipe each other, which is why the fold arrived as a
    /// jump.
    ///
    /// `progress` is deliberately not in here. It must *not* animate: it is already a smooth
    /// function of where the finger is, and putting a curve on top of a value that is being
    /// driven directly is what makes a header lag behind the scroll it is supposed to follow.
    /// Clearing the transaction for everything else is exactly what this modifier does anyway.
    private struct Shape: Equatable {
        let isSelecting: Bool
        let isNarrowed: Bool
        let selectedFolder: String?
        let noteCount: Int
        let selectionCount: Int
        let hasSearchText: Bool
    }

    private var shape: Shape {
        Shape(
            isSelecting: isSelecting,
            isNarrowed: isNarrowed,
            selectedFolder: selectedFolder,
            noteCount: noteCount,
            selectionCount: selectionCount,
            hasSearchText: !searchText.isEmpty
        )
    }

    // MARK: - Interpolation

    private var p: Double { min(max(collapse.progress, 0), 1) }

    /// Gone by 60%, so the words have finished leaving before the row that takes their place
    /// starts arriving. Two titles fading through each other reads as a double image.
    private var foldingOpacity: Double { p >= 0.6 ? 0 : 1 - p / 0.6 }

    /// And the inline one arrives after that, on Vault Home's ramp.
    private var inlineTitleOpacity: Double { min(max((p - 0.55) * 2.3, 0), 1) }

    /// The large title loses a little size on the way out, so it reads as the same words
    /// shrinking into the row rather than as one label swapped for another.
    private var foldingScale: Double { 1 - 0.14 * p }

    private var foldingHeight: CGFloat? {
        guard let foldingBlockHeight else { return nil }
        return foldingBlockHeight * (1 - p)
    }

    /// Invisible at rest and drawn once there is content behind it — a separator over nothing is
    /// a line for its own sake.
    private var hairlineOpacity: Double { p }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                if isSelecting {
                    selectionChrome
                } else {
                    browsingChrome
                }
            }
            .frame(height: 44)
            .padding(.horizontal, theme.small)

            if !isSelecting {
                foldingBlock
                // Both stay. The search field and the folder chips are how the list is narrowed,
                // and a control that leaves the moment you scroll is a control you have to scroll
                // back for — Vault Home keeps its category rail pinned for the same reason.
                searchField
                if !folderChips.isEmpty { folderRow }
            } else {
                selectionCountLine
            }

            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.75)
                .opacity(hairlineOpacity)
                .padding(.top, theme.xs)
        }
        .background(theme.background)
        .animation(NoteMotion.header(reduceMotion: reduceMotion), value: shape)
    }

    @ViewBuilder
    private var browsingChrome: some View {
        Group {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 40, height: 40)
                    .background(theme.card, in: Circle())
                    .overlay { Circle().strokeBorder(theme.separator, lineWidth: 0.75) }
            }
            .buttonStyle(NotePressButtonStyle())
            .frame(width: 44, height: 44)
            .accessibilityLabel(Text(.notesKit("Back")))

            inlineTitle

            Spacer(minLength: theme.xs)

            sortButton

            layoutToggle

            Button {
                haptic()
                onStartSelecting()
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 32, height: 32)
                    .background(theme.card, in: Circle())
                    .overlay { Circle().strokeBorder(theme.separator, lineWidth: 0.75) }
            }
            .buttonStyle(NotePressButtonStyle())
            .frame(width: 44, height: 44)
            .disabled(!hasVisibleNotes)
            .accessibilityLabel(Text(.notesKit("Select notes")))

            Button(action: onCreateNote) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 32, height: 32)
                    .background(theme.accent, in: Circle())
            }
            .buttonStyle(NotePressButtonStyle())
            .frame(width: 44, height: 44)
            .accessibilityLabel(Text(.notesKit("New note")))
        }
    }

    /// Cancel on the left, Select All on the right, count underneath: the same shape Vault Home
    /// and the trash already use, so selecting notes is not a second thing to learn.
    @ViewBuilder
    private var selectionChrome: some View {
        Group {
            Button(action: onStopSelecting) {
                Text(.notesKit("Cancel"))
                    .font(theme.modeFont)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(theme.primaryText)
            }
            .buttonStyle(NotePressButtonStyle())
            .padding(.leading, theme.small)

            Spacer(minLength: theme.small)

            Button {
                haptic()
                onSelectAllOrNone()
            } label: {
                Text(isEverythingSelected
                    ? .notesKit("Deselect All")
                    : .notesKit("Select All"))
                    .font(theme.modeFont)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(theme.primaryText)
            }
            .buttonStyle(NotePressButtonStyle())
            .padding(.trailing, theme.small)
        }
    }

    private var selectionCountLine: some View {
        Text(.notesKit(count: "\(selectionCount) selected"))
            .font(theme.metadataFont)
            .textCase(.uppercase)
            .tracking(1.4)
            .foregroundStyle(theme.secondaryText)
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.medium)
            .padding(.bottom, theme.small)
    }

    /// Sort and filter behind one control rather than two.
    ///
    /// They answer the same question — "show me a different slice of this list" — and the header
    /// has room for one more 32pt circle, not two. The dot marks a list that is narrowed, because
    /// a filter left on looks exactly like a vault that lost its notes.
    private var sortButton: some View {
        Button {
            haptic()
            onOpenSortAndFilter()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isNarrowed ? theme.onAccent : theme.primaryText)
                .frame(width: 32, height: 32)
                .background(isNarrowed ? theme.accent : theme.card, in: Circle())
                .overlay {
                    Circle().strokeBorder(
                        isNarrowed ? .clear : theme.separator,
                        lineWidth: 0.75
                    )
                }
        }
        .buttonStyle(NotePressButtonStyle())
        .frame(width: 44, height: 44)
        .accessibilityLabel(Text(.notesKit("Sort and filter")))
    }

    /// Rows or cards, one tap either way.
    ///
    /// The icon names the layout the tap will *produce*, not the one on screen — the same
    /// grammar as the Photos grid density control, and the reason it needs no label beside it.
    private var layoutToggle: some View {
        let isGrid = layout == .grid
        return Button {
            haptic()
            onToggleLayout()
        } label: {
            Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .frame(width: 32, height: 32)
                .background(theme.card, in: Circle())
                .overlay { Circle().strokeBorder(theme.separator, lineWidth: 0.75) }
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(NotePressButtonStyle())
        .frame(width: 44, height: 44)
        .accessibilityLabel(Text(isGrid ? .notesKit("List view") : .notesKit("Grid view")))
    }

    /// The title and the count line, folding together as one block.
    ///
    /// Height and opacity rather than an `if`, which is the difference between the header
    /// following the finger and the header springing between two states once the finger has
    /// already stopped. `.top` alignment matters as much as the height does: the block has to be
    /// clipped from the bottom as it closes, not slide its baseline upward.
    private var foldingBlock: some View {
        VStack(spacing: 0) {
            title
            countLine
        }
        .frame(height: foldingHeight, alignment: .top)
        .clipped()
        .opacity(foldingOpacity)
        .scaleEffect(foldingScale, anchor: .topLeading)
        .background(alignment: .top) { foldingBlockMeasurement }
    }

    /// A second copy of the block, laid out as if nothing were folded, purely to be measured.
    ///
    /// `fixedSize` is what makes it worth having: a background is offered its host's size, so
    /// without it this would report the folded height back as the natural one and the block would
    /// close itself the moment it started. Backgrounds take no part in layout, so the copy costs
    /// two `Text`s and changes nothing on screen.
    private var foldingBlockMeasurement: some View {
        VStack(spacing: 0) {
            title
            countLine
        }
        .fixedSize(horizontal: false, vertical: true)
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            guard height > 0, abs(height - (foldingBlockHeight ?? 0)) > 0.5 else { return }
            foldingBlockHeight = height
        }
    }

    /// The screen's name, on its own line and at title size.
    ///
    /// It used to sit between the back button and three controls, which capped it at a caption
    /// and left the row looking like a toolbar with a label wedged into it. A title has the width
    /// of the screen here, and the controls keep their own row.
    private var title: some View {
        Text(.notesKit("Private notes"))
            .font(theme.titleFont)
            .foregroundStyle(theme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.medium)
            .padding(.top, theme.xs)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    /// The title once the header has folded: same words, row size, beside the back button.
    ///
    /// Always in the row and never inserted into it, which is what lets it fade in without the
    /// controls beside it jumping to make room. Its width comes out of the `Spacer`, not out of
    /// the buttons, so at rest it is invisible and costs nothing anyone can see. It is hidden
    /// from VoiceOver until it is actually legible — two headers reading the same words is one
    /// too many.
    private var inlineTitle: some View {
        Text(.notesKit("Private notes"))
            .font(theme.sectionFont)
            .foregroundStyle(theme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .opacity(inlineTitleOpacity)
            .padding(.leading, theme.xs)
            .accessibilityHidden(inlineTitleOpacity < 0.5)
            .accessibilityAddTraits(.isHeader)
    }

    private var countLine: some View {
        HStack(spacing: theme.small) {
            Text(.notesKit(count: "\(noteCount) notes"))
                .textCase(.uppercase)
                .contentTransition(.numericText())
            Rectangle().fill(theme.secondaryText).frame(width: 16, height: 0.75)
            HStack(spacing: 4) {
                Image(systemName: "lock").font(.system(size: 10, weight: .semibold))
                Text(verbatim: "AES-256")
            }
        }
        .font(theme.metadataFont)
        .tracking(1.4)
        .foregroundStyle(theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.medium)
        .padding(.bottom, theme.small)
    }

    private var searchField: some View {
        HStack(spacing: theme.small) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            TextField(
                text: $searchText,
                prompt: Text(.notesKit("Search notes")).foregroundStyle(theme.disabledText)
            ) { Text(.notesKit("Search")) }
                .textFieldStyle(.plain)
                .font(theme.monoFont)
                .foregroundStyle(theme.primaryText)
                .autocorrectionDisabled()
                .noteNeverAutocapitalizes()
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.disabledText)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Text(.notesKit("Cancel")))
            }
        }
        .padding(.horizontal, theme.small + 4)
        .frame(height: 36)
        .background(theme.card, in: Capsule())
        .overlay { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
        .padding(.horizontal, theme.medium)
        .padding(.bottom, theme.small)
    }

    private var folderRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: theme.xs + 2) {
                chip(
                    title: Text(.notesKit("All")),
                    count: noteCount,
                    isSelected: selectedFolder == nil
                ) { onSelectFolder(nil) }
                ForEach(folderChips) { folder in
                    chip(
                        title: Text(verbatim: folder.name),
                        count: folder.count,
                        isSelected: selectedFolder == folder.name,
                        tint: folderTints[folder.name] ?? .neutral
                    ) { onSelectFolder(folder.name) }
                }

                // Managing folders belongs where the folders are, not in a header that already
                // carries four controls and a title — on a small phone that row runs out of
                // width before the title does.
                Button {
                    haptic()
                    onOpenFolderManager()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, theme.small + 2)
                        .frame(height: 31)
                        .overlay { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
                        .contentShape(Capsule())
                }
                .buttonStyle(NotePressButtonStyle())
                .frame(minHeight: 44)
                .accessibilityLabel(Text(.notesKit("Folders")))
            }
            .padding(.horizontal, theme.medium)
            .padding(.bottom, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(
        title: Text,
        count: Int,
        isSelected: Bool,
        tint: NoteFolderTint = .neutral,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            haptic()
            action()
        } label: {
            HStack(spacing: 5) {
                if tint != .neutral, !isSelected {
                    Circle().fill(theme.color(for: tint)).frame(width: 6, height: 6)
                }
                title.textCase(.uppercase).tracking(1.3)
                Text(count, format: .number)
                    .foregroundStyle(isSelected ? theme.onAccent.opacity(0.6) : theme.disabledText)
            }
            .font(theme.modeFont)
            .foregroundStyle(isSelected ? theme.onAccent : theme.secondaryText)
            .padding(.horizontal, theme.small + 4)
            .frame(height: 31)
            .background {
                if isSelected { Capsule().fill(theme.accent) }
                else { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(NotePressButtonStyle())
        .frame(minHeight: 44)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Header") {
    @Previewable @State var searchText = ""
    @Previewable @State var collapse = NotesHeaderCollapse()

    VStack(spacing: 0) {
        NotesListHeader(
            collapse: collapse,
            theme: .preview,
            searchText: $searchText,
            isSelecting: false,
            isEverythingSelected: false,
            selectionCount: 0,
            noteCount: 12,
            hasVisibleNotes: true,
            isNarrowed: false,
            layout: .list,
            folderChips: [
                NotesListState.FolderChip(name: "Work", count: 4),
                NotesListState.FolderChip(name: "Travel", count: 2)
            ],
            folderTints: ["Work": .teal],
            selectedFolder: nil,
            haptic: {},
            onClose: {},
            onCreateNote: {},
            onStartSelecting: {},
            onStopSelecting: {},
            onSelectAllOrNone: {},
            onOpenSortAndFilter: {},
            onToggleLayout: {},
            onSelectFolder: { _ in },
            onOpenFolderManager: {}
        )
        Spacer()
    }
    .background(NoteTheme.preview.background)
}
