import KVNotesCore
import SwiftUI

public struct NotesListScreen: View {
    @State private var viewModel: NotesListViewModel
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let theme: NoteTheme
    private let refreshToken: Int
    private let onClose: @MainActor @Sendable () -> Void
    private let onOpenNote: @MainActor @Sendable (NoteDigest) -> Void
    private let onCreateNote: @MainActor @Sendable () -> Void
    private let haptic: @MainActor @Sendable () -> Void

    public init(
        store: any NoteStore,
        theme: NoteTheme,
        refreshToken: Int = 0,
        onClose: @escaping @MainActor @Sendable () -> Void,
        onOpenNote: @escaping @MainActor @Sendable (NoteDigest) -> Void,
        onCreateNote: @escaping @MainActor @Sendable () -> Void,
        onChange: @escaping @MainActor @Sendable () -> Void = {},
        haptic: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        _viewModel = State(initialValue: NotesListViewModel(store: store, onChange: onChange))
        self.theme = theme
        self.refreshToken = refreshToken
        self.onClose = onClose
        self.onOpenNote = onOpenNote
        self.onCreateNote = onCreateNote
        self.haptic = haptic
    }

    public var body: some View {
        content
            .background(theme.background)
            .safeAreaInset(edge: .top, spacing: 0) { chrome }
            .noteNavigationChrome()
            .onAppear { viewModel.send(.onAppear) }
            .onChange(of: refreshToken) { viewModel.send(.refresh) }
            .onChange(of: searchText) { _, query in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    viewModel.send(.updateSearchQuery(query))
                }
            }
            .onDisappear { searchTask?.cancel() }
            .confirmationDialog(
                Text(.notesKit("Move this note to Recently Deleted?")),
                isPresented: Binding(
                    get: { viewModel.state.pendingDiscard != nil },
                    set: { if !$0 { viewModel.send(.cancelDiscard) } }
                ),
                titleVisibility: .visible
            ) {
                Button(.notesKit("Move to Trash"), role: .destructive) {
                    viewModel.send(.confirmDiscard)
                }
                Button(.notesKit("Cancel"), role: .cancel) {
                    viewModel.send(.cancelDiscard)
                }
            }
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
            rowList
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
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 32, height: 32)
                        .background(theme.card, in: Circle())
                        .overlay { Circle().strokeBorder(theme.separator, lineWidth: 0.75) }
                }
                .buttonStyle(NotePressButtonStyle())
                .frame(width: 44, height: 44)
                .accessibilityLabel(Text(.notesKit("Back")))

                Text(.notesKit("Private notes"))
                    .font(theme.sectionFont)
                    .textCase(.uppercase)
                    .tracking(2.2)
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: theme.small)

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
            .frame(height: 44)
            .padding(.horizontal, theme.small)

            countLine
            searchField
            if !viewModel.state.folderChips.isEmpty { folderRow }

            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.75)
                .padding(.top, theme.xs)
        }
        .background(theme.background)
    }

    private var countLine: some View {
        HStack(spacing: theme.small) {
            HStack(spacing: 4) {
                Text(viewModel.state.index.notes.count, format: .number)
                    .contentTransition(.numericText())
                Text(.notesKit("Notes")).textCase(.uppercase)
            }
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
                        isSelected: viewModel.state.selectedFolder == folder.name
                    ) { viewModel.send(.selectFolder(folder.name)) }
                }
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
        action: @escaping () -> Void
    ) -> some View {
        Button {
            haptic()
            action()
        } label: {
            HStack(spacing: 5) {
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

    private var rowList: some View {
        List {
            if viewModel.state.pinnedCount > 0 {
                Section {
                    ForEach(viewModel.state.pinnedNotes) { note in row(note) }
                } header: {
                    sectionHeader(Text(.notesKit("Pinned")), icon: "pin.fill")
                }

                if viewModel.state.pinnedCount < viewModel.state.visibleNotes.count {
                    Section {
                        ForEach(viewModel.state.timelineNotes) { note in row(note) }
                    } header: {
                        sectionHeader(Text(.notesKit("All notes")), icon: nil)
                    }
                }
            } else {
                ForEach(viewModel.state.visibleNotes) { note in row(note) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable { viewModel.send(.refresh) }
        .animation(NoteMotion.content(reduceMotion: reduceMotion), value: viewModel.state.visibleNotes.map(\.id))
    }

    /// Deliberately not a `.headerProminence` default: the header has to read as the same
    /// typographic family as the count line above the list, not as a grouped-table caption.
    private func sectionHeader(_ title: Text, icon: String?) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            }
            title.textCase(.uppercase).tracking(1.4)
        }
        .font(theme.metadataFont)
        .foregroundStyle(theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.medium)
        .padding(.top, theme.small)
        .padding(.bottom, theme.xs)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ note: NoteDigest) -> some View {
        NoteRowCard(note: note, theme: theme, haptic: haptic) { onOpenNote(note) }
            .listRowInsets(EdgeInsets(
                top: theme.xs,
                leading: theme.medium,
                bottom: theme.xs,
                trailing: theme.medium
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { viewModel.send(.requestDiscard(note)) } label: {
                    Label(.notesKit("Move to Trash"), systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) { pinButton(note) }
            .contextMenu {
                pinButton(note)
                if !viewModel.state.index.folders.isEmpty || note.folder != nil {
                    Menu {
                        Button { viewModel.send(.moveToFolder(note.id, nil)) } label: {
                            Label(.notesKit("No folder"), systemImage: note.folder == nil ? "checkmark" : "tray")
                        }
                        ForEach(viewModel.state.index.folders, id: \.self) { name in
                            Button { viewModel.send(.moveToFolder(note.id, name)) } label: {
                                Label(name, systemImage: note.folder == name ? "checkmark" : "folder")
                            }
                        }
                    } label: {
                        Label(.notesKit("Move to folder"), systemImage: "folder")
                    }
                }
                Button(role: .destructive) { viewModel.send(.requestDiscard(note)) } label: {
                    Label(.notesKit("Move to Trash"), systemImage: "trash")
                }
            }
    }

    private func pinButton(_ note: NoteDigest) -> some View {
        Button {
            haptic()
            viewModel.send(.togglePin(note.id))
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

    private var emptyFilter: some View {
        VStack(spacing: theme.medium) {
            stateMark(icon: "magnifyingglass", tone: theme.secondaryText)
            VStack(spacing: theme.xs) {
                Text(.notesKit("No matching notes"))
                    .font(theme.titleFont).textCase(.uppercase).tracking(1.4).foregroundStyle(theme.primaryText)
                Text(.notesKit("Titles and previews are searchable. The body of a note is not."))
                    .font(theme.bodyFont).multilineTextAlignment(.center).foregroundStyle(theme.secondaryText)
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
