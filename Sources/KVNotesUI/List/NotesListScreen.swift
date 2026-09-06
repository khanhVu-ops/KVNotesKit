import KVNotesCore
import SwiftUI

public struct NotesListScreen: View {
    @State private var viewModel: NotesListViewModel
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    /// How far the header has folded, from 0 to 1.
    ///
    /// The title and the count line fold away as the list is scrolled — on a phone the header was
    /// eating a third of the screen before the first note. An object and not `@State`: progress is
    /// written on every frame of every scroll, and writing `@State` at 120 Hz rebuilds this body
    /// 120 times a second. Only `NotesListHeader` reads it.
    @State private var collapse = NotesHeaderCollapse()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let theme: NoteTheme
    private let refreshToken: Int
    private let onOpenNote: @MainActor @Sendable (NoteDigest) -> Void
    private let onCreateNote: @MainActor @Sendable (NoteTemplate) -> Void
    private let onSelectionChange: @MainActor @Sendable (Bool) -> Void
    private let haptic: @MainActor @Sendable () -> Void

    public init(
        store: any NoteStore,
        theme: NoteTheme,
        preferences: (any NoteListPreferencesStore)? = nil,
        refreshToken: Int = 0,
        onOpenNote: @escaping @MainActor @Sendable (NoteDigest) -> Void,
        onCreateNote: @escaping @MainActor @Sendable (NoteTemplate) -> Void = { _ in },
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
        self.onOpenNote = onOpenNote
        self.onCreateNote = onCreateNote
        self.onSelectionChange = onSelectionChange
        self.haptic = haptic
    }

    public init(
        store: any NoteStore,
        theme: NoteTheme,
        preferences: (any NoteListPreferencesStore)? = nil,
        refreshToken: Int = 0,
        onOpenNote: @escaping @MainActor @Sendable (NoteDigest) -> Void,
        onCreateNote: @escaping @MainActor @Sendable () -> Void,
        onChange: @escaping @MainActor @Sendable () -> Void = {},
        onSelectionChange: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
        haptic: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.init(
            store: store,
            theme: theme,
            preferences: preferences,
            refreshToken: refreshToken,
            onOpenNote: onOpenNote,
            onCreateNote: { _ in onCreateNote() },
            onChange: onChange,
            onSelectionChange: onSelectionChange,
            haptic: haptic
        )
    }

    public var body: some View {
        content
            .background(theme.background)
            // The navigation bar is shown, not hidden, and that is what buys the system back
            // swipe — see `NotesListToolbar`. The title stays empty: the large one scrolls in the
            // content and the inline one is a `.principal` item that fades in behind it.
            .navigationTitle("")
            .noteInlineNavigationTitle()
            // Only while selecting, where Cancel takes that corner. Hiding it costs the back
            // swipe for as long as a selection is live, which is the intended trade.
            .noteHidesBackButton(viewModel.state.isSelecting)
            .toolbar { toolbar }
            .onAppear { viewModel.send(.onAppear) }
            .onChange(of: refreshToken) { viewModel.send(.refresh) }
            .onChange(of: viewModel.state.isSelecting) { _, isSelecting in
                onSelectionChange(isSelecting)
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
                // The dock's animation belongs to the dock. It used to be a screen-wide
                // `.animation(_:value:)` on this chain, which is the modifier that clears the
                // transaction for everything beneath it whenever its own value did not change —
                // so every `withAnimation` in `listChange`, the layout swap included, arrived at
                // the list with no animation left in it. Scoping it here is what gives those back.
                ZStack {
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
            }
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

    /// One scroll view, for every state the screen can be in.
    ///
    /// It used to be five — a `scroller` per placeholder and the board's own — and each of them
    /// had to be told about the header separately. One is not tidiness: the title block at the top
    /// is the part of the header that scrolls away, so it has to be inside whichever scroll view
    /// the reader is actually touching, and "whichever" is a word worth designing out.
    private var content: some View {
        ScrollView {
            // `pinnedViews` on this stack and not on the grid inside it: pinning is per container,
            // and the grid's own "Pinned"/"All notes" headers are captions over cards rather than
            // a table's index — sticking them to the top would stack two of them under the search.
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                if !viewModel.state.isSelecting {
                    NotesListTitleBlock(
                        theme: theme,
                        noteCount: viewModel.state.index.notes.count,
                        progress: collapse.progress
                    )
                }
                Section {
                    phaseContent
                        .padding(.bottom, theme.extraLarge)
                } header: {
                    if !viewModel.state.isSelecting { filterBar }
                }
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { viewModel.send(.refresh) }
        .notesHeaderCollapse(collapse)
        // No `.animation(value:)` here. That modifier sets the animation for this whole subtree
        // when its value changes and clears it when it does not, so one placed here would wipe
        // the transaction `listChange` opens for a card leaving or moving. The layout switch and
        // every card change arrive inside their own `withAnimation`, which is the granularity
        // that matters, and a reload from the store is left alone.
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.state.phase {
        case .idle, .loading:
            placeholder { skeleton }
        case .failed:
            placeholder { failure }
        case .loaded where viewModel.state.isEmptyBecauseStoreIsEmpty:
            placeholder { emptyVault }
        case .loaded where viewModel.state.isEmptyBecauseOfFilter:
            placeholder { emptyFilter }
        case .loaded:
            // One view for both layouts. Not a `switch` on `layout`: two branches would be two
            // views in one slot, and the switch between them could only ever cross-fade.
            noteBoard
        }
    }

    /// Sends an action that moves, adds or removes rows, inside an animated transaction.
    ///
    /// The animation belongs to the change, not to the view: `List` knows how to slide one row
    /// out and close the gap, and only needs to be told the change is animated.
    private func listChange(_ action: NotesListViewModel.Action) {
        // No guard against the header reacting to this. A card leaving shifts the list's content
        // offset, and progress is a function of that offset, so the header simply follows it by
        // the right amount — which is the correct answer and used to need a 400ms hold to fake,
        // back when the fold was inferred from the direction of travel.
        withAnimation(NoteMotion.reorder(reduceMotion: reduceMotion)) {
            viewModel.send(action)
        }
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(.horizontal, theme.medium)
    }

    /// The chrome, and the one place `collapse` is handed to anything.
    ///
    /// Items in the host's navigation bar rather than a header this screen draws: values and
    /// closures in, UIKit owning the bar, the back button and the swipe.
    private var toolbar: some ToolbarContent {
        NotesListToolbar(
            collapse: collapse,
            theme: theme,
            isSelecting: viewModel.state.isSelecting,
            isEverythingSelected: viewModel.state.isEverythingSelected,
            selectionCount: viewModel.state.selection.count,
            hasVisibleNotes: !viewModel.state.visibleNotes.isEmpty,
            isNarrowed: viewModel.state.isNarrowed,
            layout: viewModel.state.layout,
            haptic: haptic,
            onCreateNote: { viewModel.send(.openOptions(.templates)) },
            onStartSelecting: {
                withAnimation(NoteMotion.mode(reduceMotion: reduceMotion)) {
                    viewModel.send(.startSelecting)
                }
            },
            onStopSelecting: {
                withAnimation(NoteMotion.mode(reduceMotion: reduceMotion)) {
                    viewModel.send(.stopSelecting)
                }
            },
            onSelectAllOrNone: {
                withAnimation(NoteMotion.selection(reduceMotion: reduceMotion)) {
                    viewModel.send(.selectAllOrNone)
                }
            },
            onOpenSortAndFilter: { viewModel.send(.openOptions(.sortAndFilter)) },
            onToggleLayout: {
                let next: NoteListLayout = viewModel.state.layout == .grid ? .list : .grid
                // Its own curve, not `reorder`: nothing is moving anywhere, one view is becoming
                // another one.
                withAnimation(NoteMotion.layout(reduceMotion: reduceMotion)) {
                    viewModel.send(.setLayout(next))
                }
            }
        )
    }

    /// Pinned from inside the scroll view, not from the `safeAreaInset`.
    ///
    /// A `safeAreaInset` sits above everything in the scroll view, and the title has to sit
    /// between the control row and the search field — where it has always been. Pinning this as a
    /// section header is what lets the title scroll up past it and away.
    private var filterBar: some View {
        NotesListFilterBar(
            theme: theme,
            searchText: $searchText,
            noteCount: viewModel.state.index.notes.count,
            folderChips: viewModel.state.folderChips,
            folderTints: viewModel.state.index.folderTints,
            selectedFolder: viewModel.state.selectedFolder,
            progress: collapse.progress,
            haptic: haptic,
            onSelectFolder: { viewModel.send(.selectFolder($0)) },
            onOpenFolderManager: { viewModel.send(.openFolderManager) }
        )
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

    /// Both layouts, one container.
    ///
    /// A `List` for rows and a `ScrollView` for cards meant the switch between them could only
    /// ever be a cross-fade: two different views in the same slot, one leaving as the other
    /// arrives. In one `LazyVGrid` the switch is a change of *column count*, the cards keep their
    /// identity across it, and SwiftUI animates each one from the row it was to the card it
    /// becomes. That is the whole reason the `List` is gone.
    ///
    /// What went with it is `.swipeActions`. Pin and Trash are on the corner button and the long
    /// press in both layouts now — see `NoteCard`, which explains why they were not rebuilt as a
    /// `DragGesture`.
    ///
    /// Sections rather than a flat sequence with header rows: a header in a two-column grid has
    /// to span both columns, and a flat sequence would hand it one cell.
    private var noteBoard: some View {
        LazyVGrid(columns: columns, spacing: theme.small) {
            if viewModel.state.pinnedCount > 0 {
                Section {
                    ForEach(entries(viewModel.state.pinnedNotes, group: .pinned)) { entry in
                        noteCard(entry.note)
                    }
                } header: {
                    sectionHeader(Text(.notesKit("Pinned")), icon: "pin.fill")
                }

                if viewModel.state.pinnedCount < viewModel.state.visibleNotes.count {
                    Section {
                        ForEach(entries(viewModel.state.timelineNotes, group: .timeline)) { entry in
                            noteCard(entry.note)
                        }
                    } header: {
                        sectionHeader(
                            Text(.notesKit("All notes")),
                            icon: nil,
                            topPadding: theme.small + 4
                        )
                    }
                }
            } else {
                ForEach(entries(viewModel.state.visibleNotes[...], group: .timeline)) { entry in
                    noteCard(entry.note)
                }
            }
        }
        .padding(.horizontal, theme.medium)
        .padding(.top, theme.xs)
    }

    /// One column or two. The only difference between the two layouts, as far as this screen is
    /// concerned — everything else about the change is `NoteCard` reading `layout`.
    private var columns: [GridItem] {
        let spacing = theme.small
        let column = GridItem(.flexible(), spacing: spacing, alignment: .top)
        return viewModel.state.layout == .grid ? [column, column] : [column]
    }

    /// A note together with the group it is currently drawn in.
    ///
    /// The group is half the identity on purpose. `LazyVGrid` flattens its sections into one list
    /// of items, so a card that moves from the pinned group to the timeline keeps its note id and
    /// the move is diffed as a reorder rather than a removal and an insertion — and a lazy
    /// container does not rebuild the body of an item it believes only moved. A card unpinned
    /// from its own menu went on wearing its pin for exactly that reason, until something else
    /// forced the grid to rebuild. Qualifying the id makes the change what it actually is.
    private struct GridEntry: Identifiable {
        enum Group: String { case pinned, timeline }

        let group: Group
        let note: NoteDigest
        var id: String { "\(group.rawValue).\(note.id.rawValue.uuidString)" }
    }

    private func entries(_ notes: ArraySlice<NoteDigest>, group: GridEntry.Group) -> [GridEntry] {
        notes.map { GridEntry(group: group, note: $0) }
    }

    private func noteCard(_ note: NoteDigest) -> some View {
        let isSelecting = viewModel.state.isSelecting
        return NoteCard(
            note: note,
            theme: theme,
            layout: viewModel.state.layout,
            isSelecting: isSelecting,
            isSelected: viewModel.state.selection.contains(note.id),
            haptic: haptic,
            onOpen: {
                // While selecting, a tap ticks the card. Opening a note from here would lose the
                // selection the user is halfway through building.
                if isSelecting {
                    withAnimation(NoteMotion.selection(reduceMotion: reduceMotion)) {
                        viewModel.send(.toggleSelection(note.id))
                    }
                } else {
                    onOpenNote(note)
                }
            },
            onOptions: { viewModel.send(.openOptions(.note(note.id))) }
        )
        // Cards get a floor so a one-line note is still a card and three lines of preview do not
        // have to fight for the space; a taller neighbour still wins the row. Rows have no floor
        // — a row is as tall as what is in it.
        .frame(minHeight: viewModel.state.layout == .grid ? 158 : nil)
        .simultaneousGesture(optionsLongPress(note, isSelecting: isSelecting))
    }

    /// Deliberately not a `.headerProminence` default: the header has to read as the same
    /// typographic family as the count line above the list, not as a grouped-table caption.
    ///
    /// No horizontal padding of its own: the grid pads its gutter, and a header inside it must
    /// not pay for it twice.
    private func sectionHeader(
        _ title: Text,
        icon: String?,
        topPadding: CGFloat = 0
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
        .padding(.top, topPadding)
        .padding(.bottom, theme.xs)
        .accessibilityAddTraits(.isHeader)
    }

    /// Opens a row or card's options without stealing its tap.
    ///
    /// `simultaneousGesture` rather than `.onLongPressGesture`, which would swallow the tap that
    /// opens the note; and 0.45s rather than the 0.5s default, which is long enough that people
    /// let go first. With the swipes gone this and the corner button are the two ways in, so it
    /// covers the whole card rather than a menu affordance somewhere on it.
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
        case .templates:
            sheet(
                title: .notesKit("New note"),
                subtitle: nil,
                groups: templateOptionGroups
            )
        case nil:
            sheet(title: .notesKit("Note options"), subtitle: nil, groups: [])
        }
    }

    private var templateOptionGroups: [NoteOptionGroup] {
        [
            NoteOptionGroup(
                id: "templates",
                items: NoteTemplate.allCases.map { template in
                    NoteOptionItem(
                        id: "template.\(template.rawValue)",
                        title: .localized(template.title),
                        systemImage: template.iconSymbol
                    ) {
                        onCreateNote(template)
                    }
                }
            )
        ]
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
            Button {
                haptic()
                viewModel.send(.openOptions(.templates))
            } label: {
                Text(.notesKit("New note"))
                    .font(theme.modeFont).textCase(.uppercase).tracking(1.4)
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, theme.large).frame(height: 44)
                    .background(theme.accent, in: Capsule())
            }
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
