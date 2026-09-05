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

    /// Ties the large title and the folded one together so the words travel between them
    /// instead of one disappearing while the other appears somewhere else.
    @Namespace private var headerTitle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let titleGeometry = "notes.title"

    /// Everything about the header that is allowed to animate, behind one value.
    ///
    /// One `.animation(_:value:)` for the whole header and not six scattered through it, which
    /// is not tidiness. The modifier sets the animation for its subtree when its own value
    /// changed and clears it when it did not, so a second one nested underneath cancels the
    /// first for its own subtree: the header carried one watching the selection and one watching
    /// the fold, and each folded change had its animation wiped by the other. That is why the
    /// fold arrived as a jump. Collecting the facts into one value is what makes the whole
    /// header move on one curve.
    private struct Shape: Equatable {
        let isSelecting: Bool
        let isCollapsed: Bool
        let isNarrowed: Bool
        let selectedFolder: String?
        let noteCount: Int
        let selectionCount: Int
        let hasSearchText: Bool
    }

    private var shape: Shape {
        Shape(
            isSelecting: isSelecting,
            isCollapsed: isCollapsed,
            isNarrowed: isNarrowed,
            selectedFolder: selectedFolder,
            noteCount: noteCount,
            selectionCount: selectionCount,
            hasSearchText: !searchText.isEmpty
        )
    }

    private var isCollapsed: Bool { collapse.isCollapsed }

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
                if !isCollapsed {
                    title
                    countLine
                }
                searchField
                if !folderChips.isEmpty, !isCollapsed { folderRow }
            } else {
                selectionCountLine
            }

            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.75)
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

            if isCollapsed { foldedTitle }

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

    /// The screen's name, on its own line and at title size.
    ///
    /// It used to sit between the back button and three controls, which capped it at a caption
    /// and left the row looking like a toolbar with a label wedged into it. A title has the width
    /// of the screen here, and the controls keep their own row.
    private var title: some View {
        Text(.notesKit("Private notes"))
            .font(theme.titleFont)
            .foregroundStyle(theme.primaryText)
            // On the Text itself, not on the padded row: the anchor has to be where the glyphs
            // start, or the title lands a `medium` short of the back button.
            .matchedGeometryEffect(
                id: Self.titleGeometry,
                in: headerTitle,
                properties: .position,
                anchor: .leading,
                isSource: !isCollapsed
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.medium)
            .padding(.top, theme.xs)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
            // Position comes from the geometry match, so the transition only has to cross-fade
            // the two sizes. A `move` on top of it would pull the title off its own path.
            .transition(.opacity)
    }

    /// The title once the header has folded: same words, row size, beside the back button.
    ///
    /// The geometry match carries the position and not the frame. Matching the frame as well
    /// squeezes the large title's glyphs into this one's box on the way up, and the two type
    /// sizes are exactly what the cross-fade is for.
    private var foldedTitle: some View {
        Text(.notesKit("Private notes"))
            .font(theme.sectionFont)
            .foregroundStyle(theme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .matchedGeometryEffect(
                id: Self.titleGeometry,
                in: headerTitle,
                properties: .position,
                anchor: .leading,
                isSource: isCollapsed
            )
            .padding(.leading, theme.xs)
            .accessibilityAddTraits(.isHeader)
            .transition(.opacity)
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
        // Nothing catches this line on the way out, so it leaves the way the header folds:
        // upward, behind the row that is taking the title.
        .transition(.move(edge: .top).combined(with: .opacity))
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
        // The chips leave with the rest of the fold rather than on their own curve; a second
        // animation here would be a second `.animation(_:value:)` cancelling the first.
        .transition(.move(edge: .top).combined(with: .opacity))
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

    VStack(spacing: 0) {
        NotesListHeader(
            collapse: NotesHeaderCollapse(),
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
