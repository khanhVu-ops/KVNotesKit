import KVNotesCore
import SwiftUI

public struct NotesListScreen: View {
    @State private var viewModel: NotesListViewModel
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    /// True once the list has been scrolled past the first few points.
    ///
    /// The title, the count line and the folder chips fold away while reading and come back on
    /// the way up — on a phone the header was eating a third of the screen before the first note.
    @State private var isHeaderCollapsed = false
    @State private var lastScrollOffset: CGFloat = 0
    /// Geometry reported while the header is still resizing is about the header, not about the
    /// finger; folding changes the list's top inset, and reacting to that is how a header ends up
    /// flapping between the two states.
    @State private var headerSettlesAt: Date = .distantPast
    /// Ties the large title and the folded one together so the words travel between them instead
    /// of one disappearing while the other appears somewhere else.
    @Namespace private var headerTitle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let titleGeometry = "notes.title"

    private let theme: NoteTheme
    private let refreshToken: Int
    private let onClose: @MainActor @Sendable () -> Void
    private let onOpenNote: @MainActor @Sendable (NoteDigest) -> Void
    private let onCreateNote: @MainActor @Sendable () -> Void
    private let onSelectionChange: @MainActor @Sendable (Bool) -> Void
    private let haptic: @MainActor @Sendable () -> Void

    public init(
        store: any NoteStore,
        theme: NoteTheme,
        preferences: (any NoteListPreferencesStore)? = nil,
        refreshToken: Int = 0,
        onClose: @escaping @MainActor @Sendable () -> Void,
        onOpenNote: @escaping @MainActor @Sendable (NoteDigest) -> Void,
        onCreateNote: @escaping @MainActor @Sendable () -> Void,
        onChange: @escaping @MainActor @Sendable () -> Void = {},
        /// The host hides its dock while a selection is live; the package cannot reach that
        /// modifier, and should not know it exists.
        onSelectionChange: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
        haptic: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        _viewModel = State(initialValue: NotesListViewModel(
            store: store,
            preferences: preferences,
            onChange: onChange
        ))
        self.theme = theme
        self.refreshToken = refreshToken
        self.onClose = onClose
        self.onOpenNote = onOpenNote
        self.onCreateNote = onCreateNote
        self.onSelectionChange = onSelectionChange
        self.haptic = haptic
    }

    public var body: some View {
        content
            .background(theme.background)
            .safeAreaInset(edge: .top, spacing: 0) { chrome }
            .noteNavigationChrome()
            .onAppear { viewModel.send(.onAppear) }
            .onChange(of: refreshToken) { viewModel.send(.refresh) }
            .onChange(of: viewModel.state.isSelecting) { _, isSelecting in
                onSelectionChange(isSelecting)
            }
            // Swapping the `List` for the grid throws away the scroll view that was reporting
            // offsets, and the first reading from the new one is measured against the old one's
            // last. Left alone that difference reads as a flick and folds the header.
            .onChange(of: viewModel.state.layout) { _, _ in
                lastScrollOffset = 0
                headerSettlesAt = Date().addingTimeInterval(0.6)
            }
            .onDisappear { onSelectionChange(false) }
            .onChange(of: searchText) { _, query in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    viewModel.send(.updateSearchQuery(query))
                }
            }
            .onDisappear { searchTask?.cancel() }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showsFolderManager },
                set: { if !$0 { viewModel.send(.closeFolderManager) } }
            )) {
                NoteFolderManagerSheet(
                    folders: viewModel.state.index.folders,
                    counts: viewModel.state.folderChips.reduce(into: [:]) { $0[$1.name] = $1.count },
                    tints: viewModel.state.index.folderTints,
                    isBusy: viewModel.state.isBusy,
                    theme: theme,
                    haptic: haptic,
                    onRename: { viewModel.send(.renameFolder($0, to: $1)) },
                    onTint: { viewModel.send(.tintFolder($0, $1)) },
                    onRemove: { viewModel.send(.removeFolder($0)) },
                    onDismiss: { viewModel.send(.closeFolderManager) }
                )
                .presentationDetents([.medium, .large])
                // Two detents make the system draw a grabber by default. This sheet has its own
                // title and its own Done button, and the grabber only competes with them.
                .presentationDragIndicator(.hidden)
            }
            .overlay(alignment: .bottom) {
                if viewModel.state.isSelecting {
                    NoteBatchToolbar(
                        selectionCount: viewModel.state.selection.count,
                        wouldPin: viewModel.state.batchWouldPin,
                        wouldLock: viewModel.state.batchWouldLock,
                        isBusy: viewModel.state.isBusy,
                        theme: theme,
                        onPin: { haptic(); listChange(.batchPin) },
                        onLock: { haptic(); listChange(.batchLock) },
                        onMore: { viewModel.send(.openOptions(.batch)) }
                    )
                    .padding(.horizontal, theme.medium)
                    .padding(.bottom, theme.small)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(
                NoteMotion.mode(reduceMotion: reduceMotion),
                value: viewModel.state.isSelecting
            )
            .noteOptionSheet(
                isPresented: Binding(
                    get: { viewModel.state.optionSheet != nil },
                    set: { if !$0 { viewModel.send(.closeOptions) } }
                ),
                sheet: optionSheet
            )
            .noteConfirmSheet(
                isPresented: Binding(
                    get: { viewModel.state.pendingBatchDiscard },
                    set: { if !$0 { viewModel.send(.cancelBatchDiscard) } }
                ),
                title: .notesKit("Move these notes to Recently Deleted?"),
                message: .notesKit("They stay in the vault's trash until you empty it."),
                confirmTitle: .notesKit("Move to Trash"),
                theme: theme,
                onConfirm: { listChange(.confirmBatchDiscard) },
                onCancel: { viewModel.send(.cancelBatchDiscard) }
            )
            .noteConfirmSheet(
                isPresented: Binding(
                    get: { viewModel.state.pendingDiscard != nil },
                    set: { if !$0 { viewModel.send(.cancelDiscard) } }
                ),
                title: .notesKit("Move this note to Recently Deleted?"),
                message: .notesKit("It stays in the vault's trash until you empty it."),
                confirmTitle: .notesKit("Move to Trash"),
                theme: theme,
                onConfirm: { listChange(.confirmDiscard) },
                onCancel: { viewModel.send(.cancelDiscard) }
            )
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state.phase {
        case .idle, .loading:
            scroller { skeleton }
        case .failed:
            scroller { failure }
        case .loaded where viewModel.state.isEmptyBecauseStoreIsEmpty:
            scroller { emptyVault }
        case .loaded where viewModel.state.isEmptyBecauseOfFilter:
            scroller { emptyFilter }
        case .loaded:
            switch viewModel.state.layout {
            case .list: rowList
            case .grid: cardGrid
            }
        }
    }

    /// Sends an action that moves, adds or removes rows, inside an animated transaction.
    ///
    /// The animation belongs to the change, not to the view: `List` knows how to slide one row
    /// out and close the gap, and only needs to be told the change is animated.
    private func listChange(_ action: NotesListViewModel.Action) {
        // Rows moving or leaving shifts the list's own content offset, and the header decides to
        // fold from offset deltas. Without this a pinned row sliding to the top folded the header
        // underneath it, which resizes the list mid-move — the jump the animation exists to avoid.
        headerSettlesAt = Date().addingTimeInterval(0.6)
        withAnimation(NoteMotion.reorder(reduceMotion: reduceMotion)) {
            viewModel.send(action)
        }
    }

    private func scroller<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, theme.medium)
                .padding(.bottom, theme.extraLarge)
        }
        .scrollIndicators(.hidden)
        .refreshable { viewModel.send(.refresh) }
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                if viewModel.state.isSelecting {
                    selectionChrome
                } else {
                    browsingChrome
                }
            }
            .frame(height: 44)
            .padding(.horizontal, theme.small)

            if !viewModel.state.isSelecting {
                if !isHeaderCollapsed {
                    title
                    countLine
                }
                searchField
                if !viewModel.state.folderChips.isEmpty, !isHeaderCollapsed { folderRow }
            } else {
                selectionCount
            }

            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.75)
                .padding(.top, theme.xs)
        }
        .background(theme.background)
        .animation(NoteMotion.mode(reduceMotion: reduceMotion), value: viewModel.state.isSelecting)
        .animation(NoteMotion.mode(reduceMotion: reduceMotion), value: isHeaderCollapsed)
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

                if isHeaderCollapsed { foldedTitle }

                Spacer(minLength: theme.xs)

                sortButton

                layoutToggle

                Button {
                    haptic()
                    viewModel.send(.startSelecting)
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
                .disabled(viewModel.state.visibleNotes.isEmpty)
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
            Button { viewModel.send(.stopSelecting) } label: {
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
                viewModel.send(.selectAllOrNone)
            } label: {
                Text(viewModel.state.isEverythingSelected
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

    private var selectionCount: some View {
        Text(.notesKit(count: "\(viewModel.state.selection.count) selected"))
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
            viewModel.send(.openOptions(.sortAndFilter))
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(viewModel.state.isNarrowed ? theme.onAccent : theme.primaryText)
                .frame(width: 32, height: 32)
                .background(viewModel.state.isNarrowed ? theme.accent : theme.card, in: Circle())
                .overlay {
                    Circle().strokeBorder(
                        viewModel.state.isNarrowed ? .clear : theme.separator,
                        lineWidth: 0.75
                    )
                }
        }
        .buttonStyle(NotePressButtonStyle())
        .frame(width: 44, height: 44)
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: viewModel.state.isNarrowed)
        .accessibilityLabel(Text(.notesKit("Sort and filter")))
    }

    /// Rows or cards, one tap either way.
    ///
    /// The icon names the layout the tap will *produce*, not the one on screen — the same
    /// grammar as the Photos grid density control, and the reason it needs no label beside it.
    private var layoutToggle: some View {
        let isGrid = viewModel.state.layout == .grid
        return Button {
            haptic()
            listChange(.setLayout(isGrid ? .list : .grid))
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

    private static func sortTitle(_ order: NoteSortOrder) -> LocalizedStringResource {
        switch order {
        case .lastEditedNewest: .notesKit("Last edited")
        case .lastEditedOldest: .notesKit("Oldest edit first")
        case .createdNewest: .notesKit("Date created")
        case .title: .notesKit("Title")
        }
    }

    private static func filterTitle(_ filter: NoteFilter) -> LocalizedStringResource {
        switch filter {
        case .all: .notesKit("All notes")
        case .locked: .notesKit("Locked only")
        case .hasChecklist: .notesKit("With a checklist")
        }
    }

    /// Rows in a sheet have room for an icon where a menu's tick took the same slot. The icon says
    /// what the choice is; the tick on the right says whether it is the one in force.
    ///
    /// Spelled with `return` rather than as expressions: `check-l10n.sh` reads `title: "…"` as a
    /// piece of user-facing copy, and `case .title: "textformat.abc"` is exactly that shape.
    private static func sortIcon(_ order: NoteSortOrder) -> String {
        switch order {
        case .lastEditedNewest: return "clock.arrow.circlepath"
        case .lastEditedOldest: return "clock.arrow.2.circlepath"
        case .createdNewest: return "calendar"
        case .title: return "textformat.abc"
        }
    }

    private static func filterIcon(_ filter: NoteFilter) -> String {
        switch filter {
        case .all: "tray.full"
        case .locked: "lock"
        case .hasChecklist: "checklist"
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
            // On the Text itself, not on the padded row: the anchor has to be where the glyphs
            // start, or the title lands a `medium` short of the back button.
            .matchedGeometryEffect(
                id: Self.titleGeometry,
                in: headerTitle,
                properties: .position,
                anchor: .leading,
                isSource: !isHeaderCollapsed
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
                isSource: isHeaderCollapsed
            )
            .padding(.leading, theme.xs)
            .accessibilityAddTraits(.isHeader)
            .transition(.opacity)
    }

    private var countLine: some View {
        HStack(spacing: theme.small) {
            Text(.notesKit(count: "\(viewModel.state.index.notes.count) notes"))
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
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: viewModel.state.index.notes.count)
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
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: searchText.isEmpty)
    }

    private var folderRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: theme.xs + 2) {
                chip(
                    title: Text(.notesKit("All")),
                    count: viewModel.state.index.notes.count,
                    isSelected: viewModel.state.selectedFolder == nil
                ) { viewModel.send(.selectFolder(nil)) }
                ForEach(viewModel.state.folderChips) { folder in
                    chip(
                        title: Text(verbatim: folder.name),
                        count: folder.count,
                        isSelected: viewModel.state.selectedFolder == folder.name,
                        tint: viewModel.state.index.folderTints[folder.name] ?? .neutral
                    ) { viewModel.send(.selectFolder(folder.name)) }
                }

                // Managing folders belongs where the folders are, not in a header that already
                // carries four controls and a title — on a small phone that row runs out of
                // width before the title does.
                Button {
                    haptic()
                    viewModel.send(.openFolderManager)
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
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Folds on the way down and unfolds on the way up, from the direction of travel rather than
    /// from a fixed offset.
    ///
    /// An absolute threshold cannot work here: the header lives in a `safeAreaInset`, so folding
    /// it changes the list's own top inset, which changes the offset that decided to fold it. The
    /// first version latched collapsed for that reason. Direction is immune to the resize, and a
    /// short settling window keeps the resize itself from being read as a scroll.
    private func updateHeaderCollapse(for offset: CGFloat) {
        defer { lastScrollOffset = offset }
        // The top is the one place direction cannot decide. A flick that ends at the first row
        // travels upward the whole way and still leaves the last delta pointing down, or gets
        // absorbed by the rubber band entirely — either way the header stayed folded over a list
        // that had nothing above it, which is the state it is supposed to fold *out* of.
        if offset <= 4 {
            guard isHeaderCollapsed else { return }
            isHeaderCollapsed = false
            headerSettlesAt = Date().addingTimeInterval(0.35)
            return
        }
        guard Date() >= headerSettlesAt else { return }
        let delta = offset - lastScrollOffset
        guard abs(delta) > 8 else { return }
        let collapsed = delta > 0
        guard collapsed != isHeaderCollapsed else { return }
        isHeaderCollapsed = collapsed
        headerSettlesAt = Date().addingTimeInterval(0.35)
    }

    /// The whole list as one flat sequence, headers included.
    ///
    /// Not two `Section`s, and that is the difference between a pinned row sliding and a pinned
    /// row blinking. Across sections a pin is a delete on one side and an insert on the other, so
    /// `List` cross-fades it; worse, the first pin in an unpinned vault swapped a bare `ForEach`
    /// for two sections, which rebuilt every row on screen. In one `ForEach` the same change is a
    /// move of a row that keeps its identity, which is the animation `List` does properly.
    ///
    /// The cost is that the headers scroll away instead of pinning to the top. They are two words
    /// of metadata over cards on a plain background, not a table's index.
    private enum ListRow: Identifiable {
        case pinnedHeader
        case timelineHeader
        case note(NoteDigest)

        var id: AnyHashable {
            switch self {
            case .pinnedHeader: AnyHashable("notes.header.pinned")
            case .timelineHeader: AnyHashable("notes.header.timeline")
            case .note(let note): AnyHashable(note.id)
            }
        }
    }

    private var listRows: [ListRow] {
        let state = viewModel.state
        guard state.pinnedCount > 0 else { return state.visibleNotes.map(ListRow.note) }
        var rows: [ListRow] = [.pinnedHeader]
        rows += state.pinnedNotes.map(ListRow.note)
        if state.pinnedCount < state.visibleNotes.count {
            rows.append(.timelineHeader)
            rows += state.timelineNotes.map(ListRow.note)
        }
        return rows
    }

    private var rowList: some View {
        List {
            ForEach(listRows) { item in
                switch item {
                case .pinnedHeader:
                    sectionHeader(Text(.notesKit("Pinned")), icon: "pin.fill")
                case .timelineHeader:
                    sectionHeader(Text(.notesKit("All notes")), icon: nil, topPadding: theme.small + 4)
                case .note(let note):
                    row(note)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable { viewModel.send(.refresh) }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            updateHeaderCollapse(for: offset)
        }
        // No `.animation(value:)` here. That modifier animates the whole `List` as one view, and
        // a row leaving on a swipe then cross-faded against everything around it instead of the
        // row sliding out and its neighbours closing the gap. `List` animates its own rows
        // correctly when the change arrives inside a transaction — `listChange` below wraps the
        // sends that move or remove a row, which is exactly the set of changes that should
        // animate, and leaves a reload from the store alone.
    }

    /// The same notes, two columns wide.
    ///
    /// `LazyVGrid` rather than a second `List`: a `List` cannot lay two cells side by side, and
    /// that is the whole point of this layout — twice the notes on screen and three lines of
    /// preview instead of one, for when the user is looking *for* a note rather than working
    /// through one. Sections here rather than the flat `ForEach` the rows use, because a header
    /// in a grid has to span both columns and a flat sequence would give it one cell.
    private var cardGrid: some View {
        ScrollView {
            LazyVGrid(columns: Self.gridColumns(spacing: theme.small), spacing: theme.small) {
                if viewModel.state.pinnedCount > 0 {
                    Section {
                        ForEach(entries(viewModel.state.pinnedNotes, group: .pinned)) { entry in
                            gridCard(entry.note)
                        }
                    } header: {
                        sectionHeader(
                            Text(.notesKit("Pinned")),
                            icon: "pin.fill",
                            horizontalPadding: 0
                        )
                    }

                    if viewModel.state.pinnedCount < viewModel.state.visibleNotes.count {
                        Section {
                            ForEach(entries(viewModel.state.timelineNotes, group: .timeline)) { entry in
                                gridCard(entry.note)
                            }
                        } header: {
                            sectionHeader(
                                Text(.notesKit("All notes")),
                                icon: nil,
                                topPadding: theme.small + 4,
                                horizontalPadding: 0
                            )
                        }
                    }
                } else {
                    ForEach(entries(viewModel.state.visibleNotes[...], group: .timeline)) { entry in
                        gridCard(entry.note)
                    }
                }
            }
            .padding(.horizontal, theme.medium)
            .padding(.top, theme.xs)
            .padding(.bottom, theme.extraLarge)
        }
        .scrollIndicators(.hidden)
        .refreshable { viewModel.send(.refresh) }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            updateHeaderCollapse(for: offset)
        }
    }

    /// A note together with the group it is currently drawn in.
    ///
    /// The group is half the identity on purpose. `LazyVGrid` flattens its sections into one list
    /// of items, so a card that moves from the pinned grid to the timeline keeps its note id and
    /// the move is diffed as a reorder rather than a removal and an insertion — and a lazy
    /// container does not rebuild the body of an item it believes only moved. A card unpinned
    /// from its own menu went on wearing its pin for exactly that reason, until something else
    /// forced the grid to rebuild. Qualifying the id makes the change what it actually is.
    ///
    /// The rows do not need this: they are one flat `ForEach` with no sections to move between.
    private struct GridEntry: Identifiable {
        enum Group: String { case pinned, timeline }

        let group: Group
        let note: NoteDigest
        var id: String { "\(group.rawValue).\(note.id.rawValue.uuidString)" }
    }

    private func entries(_ notes: ArraySlice<NoteDigest>, group: GridEntry.Group) -> [GridEntry] {
        notes.map { GridEntry(group: group, note: $0) }
    }

    private static func gridColumns(spacing: CGFloat) -> [GridItem] {
        [
            GridItem(.flexible(), spacing: spacing, alignment: .top),
            GridItem(.flexible(), spacing: spacing, alignment: .top)
        ]
    }

    private func gridCard(_ note: NoteDigest) -> some View {
        let isSelecting = viewModel.state.isSelecting
        return NoteGridCard(
            note: note,
            theme: theme,
            isSelecting: isSelecting,
            isSelected: viewModel.state.selection.contains(note.id),
            haptic: haptic,
            onOpen: {
                if isSelecting {
                    viewModel.send(.toggleSelection(note.id))
                } else {
                    onOpenNote(note)
                }
            },
            onOptions: { viewModel.send(.openOptions(.note(note.id))) }
        )
        // Short enough that a one-line note is still a card, tall enough that three lines of
        // preview do not have to fight for the space; a taller neighbour still wins the row.
        .frame(minHeight: 158)
        .simultaneousGesture(optionsLongPress(note, isSelecting: isSelecting))
    }

    /// Deliberately not a `.headerProminence` default: the header has to read as the same
    /// typographic family as the count line above the list, not as a grouped-table caption.
    private func sectionHeader(
        _ title: Text,
        icon: String?,
        topPadding: CGFloat = 0,
        // The grid pads its own gutter, so a header inside it must not pay for it twice.
        horizontalPadding: CGFloat? = nil
    ) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            }
            title.textCase(.uppercase).tracking(1.4)
        }
        .font(theme.metadataFont)
        .foregroundStyle(theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding ?? theme.medium)
        .padding(.top, topPadding)
        .padding(.bottom, theme.xs)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ note: NoteDigest) -> some View {
        let isSelecting = viewModel.state.isSelecting
        return NoteRowCard(
            note: note,
            theme: theme,
            isSelecting: isSelecting,
            isSelected: viewModel.state.selection.contains(note.id),
            haptic: haptic
        ) {
            // While selecting, a tap ticks the row. Opening a note from here would lose the
            // selection the user is halfway through building.
            if isSelecting {
                viewModel.send(.toggleSelection(note.id))
            } else {
                onOpenNote(note)
            }
        }
            .listRowInsets(EdgeInsets(
                top: theme.xs,
                leading: theme.medium,
                bottom: theme.xs,
                trailing: theme.medium
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            // Swipes and the context menu are off while selecting: a swipe that acts on one row
            // in the middle of building a selection of five is an action nobody asked for.
            .swipeActions(edge: .trailing) {
                if !isSelecting {
                    Button(role: .destructive) { viewModel.send(.requestDiscard(note)) } label: {
                        Label(.notesKit("Move to Trash"), systemImage: "trash")
                    }
                }
            }
            .swipeActions(edge: .leading) { if !isSelecting { pinSwipeButton(note) } }
            // A long press instead of `.contextMenu`: the sheet it opens is the same one the grid
            // card's button opens, and the row keeps the two verbs worth a swipe on either edge.
            .simultaneousGesture(optionsLongPress(note, isSelecting: isSelecting))
    }

    /// Opens a row or card's options without stealing its tap.
    ///
    /// `simultaneousGesture` rather than `.onLongPressGesture`, which would swallow the tap that
    /// opens the note; and 0.45s rather than the 0.5s default, which is long enough that people
    /// let go first.
    private func optionsLongPress(_ note: NoteDigest, isSelecting: Bool) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            guard !isSelecting else { return }
            haptic()
            viewModel.send(.openOptions(.note(note.id)))
        }
    }

    /// Everything that can be done to one note, in the one place both layouts read it from.
    ///
    /// The grid has no swipe to hang these on, so this is not a convenience — it is where the
    /// actions live once a card replaces a row. Written once so the two layouts cannot drift into
    /// offering different verbs.
    ///
    /// Folders sit in the same sheet rather than behind a "Move to folder" step. A sheet opened
    /// from a sheet replaces the one under it, and one extra tap to reach four folder names buys
    /// nothing — the list scrolls when a vault has more.
    /// The one sheet all three option lists are drawn by.
    ///
    /// It is always built, presented or not: `.sheet` needs its content before it animates in, and
    /// a nil case that renders nothing is cheaper than three separate sheet modifiers racing each
    /// other for the one presentation slot SwiftUI gives a view.
    private var optionSheet: NoteOptionSheetView {
        switch viewModel.state.optionSheet {
        case .sortAndFilter:
            sheet(
                title: .notesKit("Sort and filter"),
                subtitle: nil,
                groups: sortAndFilterGroups,
                // Sort and filter are two questions. Closing after the first answer means opening
                // the sheet twice to change how the list is shown.
                dismissesOnSelection: false
            )
        case .note:
            // Nil once the note has gone — trashed from this very sheet, or by a reload. The
            // sheet is on its way out by then and an empty body is what should be behind it.
            if let note = viewModel.state.optionSheetNote {
                sheet(
                    title: .notesKit("Note options"),
                    subtitle: .verbatim(note.title.isEmpty ? "" : note.title),
                    groups: noteOptionGroups(note)
                )
            } else {
                sheet(title: .notesKit("Note options"), subtitle: nil, groups: [])
            }
        case .batch:
            sheet(
                title: .notesKit("Note options"),
                subtitle: .localized(.notesKit(count: "\(viewModel.state.selection.count) selected")),
                groups: batchOptionGroups
            )
        case nil:
            sheet(title: .notesKit("Note options"), subtitle: nil, groups: [])
        }
    }

    private func sheet(
        title: LocalizedStringResource,
        subtitle: NoteOptionTitle?,
        groups: [NoteOptionGroup],
        dismissesOnSelection: Bool = true
    ) -> NoteOptionSheetView {
        NoteOptionSheetView(
            title: title,
            subtitle: subtitle,
            groups: groups,
            dismissesOnSelection: dismissesOnSelection,
            theme: theme,
            haptic: haptic,
            onDismiss: { viewModel.send(.closeOptions) }
        )
    }

    private var sortAndFilterGroups: [NoteOptionGroup] {
        [
            NoteOptionGroup(id: "sort", heading: .notesKit("Sort by"), items: NoteSortOrder.allCases.map { order in
                NoteOptionItem(
                    id: "sort.\(order.rawValue)",
                    title: .localized(Self.sortTitle(order)),
                    systemImage: Self.sortIcon(order),
                    isSelected: viewModel.state.sortOrder == order
                ) { listChange(.setSortOrder(order)) }
            }),
            NoteOptionGroup(id: "filter", heading: .notesKit("Show"), items: NoteFilter.allCases.map { filter in
                NoteOptionItem(
                    id: "filter.\(filter.rawValue)",
                    title: .localized(Self.filterTitle(filter)),
                    systemImage: Self.filterIcon(filter),
                    isSelected: viewModel.state.filter == filter
                ) { listChange(.setFilter(filter)) }
            })
        ]
    }

    /// What the batch dock's third button opens, now that it is a sheet and not a menu.
    private var batchOptionGroups: [NoteOptionGroup] {
        var items = [
            NoteOptionItem(
                id: "folder.none",
                title: .localized(.notesKit("No folder")),
                systemImage: "tray"
            ) { listChange(.batchMoveToFolder(nil)) }
        ]
        items += viewModel.state.index.folders.map { name in
            NoteOptionItem(id: "folder.\(name)", title: .verbatim(name), systemImage: "folder") {
                listChange(.batchMoveToFolder(name))
            }
        }
        return [
            NoteOptionGroup(id: "actions", items: [
                NoteOptionItem(
                    id: "trash",
                    title: .localized(.notesKit("Move to Trash")),
                    systemImage: "trash",
                    isDestructive: true
                ) { viewModel.send(.requestBatchDiscard) }
            ]),
            NoteOptionGroup(id: "folders", heading: .notesKit("Move to folder"), items: items)
        ]
    }

    private func noteOptionGroups(_ note: NoteDigest) -> [NoteOptionGroup] {
        var groups = [
            NoteOptionGroup(id: "actions", items: [
                NoteOptionItem(
                    id: "pin",
                    title: .localized(note.isPinned ? .notesKit("Unpin") : .notesKit("Pin")),
                    systemImage: note.isPinned ? "pin.slash" : "pin"
                ) { listChange(.togglePin(note.id)) },
                NoteOptionItem(
                    id: "trash",
                    title: .localized(.notesKit("Move to Trash")),
                    systemImage: "trash",
                    isDestructive: true
                ) { viewModel.send(.requestDiscard(note)) }
            ])
        ]

        if !viewModel.state.index.folders.isEmpty || note.folder != nil {
            var items = [
                NoteOptionItem(
                    id: "folder.none",
                    title: .localized(.notesKit("No folder")),
                    systemImage: "tray",
                    isSelected: note.folder == nil
                ) { viewModel.send(.moveToFolder(note.id, nil)) }
            ]
            items += viewModel.state.index.folders.map { name in
                NoteOptionItem(
                    id: "folder.\(name)",
                    title: .verbatim(name),
                    systemImage: "folder",
                    isSelected: note.folder == name
                ) { viewModel.send(.moveToFolder(note.id, name)) }
            }
            groups.append(
                NoteOptionGroup(id: "folders", heading: .notesKit("Move to folder"), items: items)
            )
        }

        return groups
    }

    private func pinSwipeButton(_ note: NoteDigest) -> some View {
        Button {
            haptic()
            // A swipe action's row is still collapsing when the action runs, and `List` will not
            // move a cell that is mid-gesture: the gap opened above immediately while the row
            // itself stayed put, then snapped up when the collapse finished. Let the collapse
            // finish first, then animate the move — the wait is the animation the user is already
            // watching, not an added delay. The number is the system's own swipe-close duration;
            // there is no callback for it, and undershooting it is what the jump looked like.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                listChange(.togglePin(note.id))
            }
        } label: {
            Label(
                note.isPinned ? .notesKit("Unpin") : .notesKit("Pin"),
                systemImage: note.isPinned ? "pin.slash" : "pin"
            )
        }
        .tint(theme.accent)
    }

    private var skeleton: some View {
        VStack(spacing: theme.small) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: theme.small + 4) {
                    RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous)
                        .fill(theme.elevatedCard)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: theme.small) {
                        RoundedRectangle(cornerRadius: 3).fill(theme.elevatedCard).frame(height: 11)
                        RoundedRectangle(cornerRadius: 3).fill(theme.elevatedCard).frame(width: 160, height: 9)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .noteCard(theme: theme, padding: theme.small + 4)
            }
        }
        .noteShimmer(theme: theme)
        .padding(.top, theme.small)
    }

    private var failure: some View {
        VStack(spacing: theme.medium) {
            stateMark(icon: "exclamationmark.triangle", tone: theme.error)
            Text(.notesKit("Something went wrong."))
                .font(theme.titleFont).textCase(.uppercase).tracking(1.4).foregroundStyle(theme.primaryText)
            Button(.notesKit("Try again")) { viewModel.send(.refresh) }
                .font(theme.modeFont).textCase(.uppercase).tracking(1.4)
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, theme.large).frame(height: 44)
                .background(theme.accent, in: Capsule())
                .buttonStyle(NotePressButtonStyle())
        }
        .frame(minHeight: 380)
    }

    private var emptyVault: some View {
        VStack(spacing: theme.medium) {
            stateMark(icon: "note.text", tone: theme.primaryText)
            VStack(spacing: theme.xs) {
                Text(.notesKit("No notes yet"))
                    .font(theme.titleFont).textCase(.uppercase).tracking(1.4).foregroundStyle(theme.primaryText)
                Text(.notesKit("Notes you write here are sealed in the vault with AES-256."))
                    .font(theme.bodyFont).multilineTextAlignment(.center).foregroundStyle(theme.secondaryText)
            }
            Button(.notesKit("New note"), action: onCreateNote)
                .font(theme.modeFont).textCase(.uppercase).tracking(1.4)
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, theme.large).frame(height: 44)
                .background(theme.accent, in: Capsule())
                .buttonStyle(NotePressButtonStyle())
                .padding(.top, theme.xs)
        }
        .padding(.horizontal, theme.large)
        .frame(minHeight: 380)
    }

    /// Two different dead ends, and saying which one this is decides what the user does next.
    /// A filter that hides everything is undone with one tap; a search that finds nothing is not.
    @ViewBuilder
    private var emptyFilter: some View {
        let isFiltered = viewModel.state.filter != .all
        VStack(spacing: theme.medium) {
            stateMark(
                icon: isFiltered ? "line.3.horizontal.decrease" : "magnifyingglass",
                tone: theme.secondaryText
            )
            VStack(spacing: theme.xs) {
                Text(.notesKit("No matching notes"))
                    .font(theme.titleFont).textCase(.uppercase).tracking(1.4).foregroundStyle(theme.primaryText)
                Text(isFiltered
                    ? .notesKit("No note in this vault matches the filter you have on.")
                    : .notesKit("Titles and previews are searchable. The body of a note is not."))
                    .font(theme.bodyFont).multilineTextAlignment(.center).foregroundStyle(theme.secondaryText)
            }
            if isFiltered {
                Button(.notesKit("Show all notes")) { listChange(.setFilter(.all)) }
                    .font(theme.modeFont).textCase(.uppercase).tracking(1.4)
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, theme.large).frame(height: 44)
                    .background(theme.accent, in: Capsule())
                    .buttonStyle(NotePressButtonStyle())
                    .padding(.top, theme.xs)
            }
        }
        .padding(.horizontal, theme.large)
        .frame(minHeight: 380)
    }

    private func stateMark(icon: String, tone: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 34, weight: .light))
            .foregroundStyle(tone)
            .frame(width: 76, height: 76)
            .overlay { Circle().stroke(theme.separator, lineWidth: 0.75) }
    }
}
