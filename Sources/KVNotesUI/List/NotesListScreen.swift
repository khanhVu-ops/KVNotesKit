import KVNotesCore
import SwiftUI

public struct NotesListScreen: View {
    @State private var viewModel: NotesListViewModel
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    private let theme: NoteTheme
    private let onClose: @MainActor @Sendable () -> Void
    private let onOpenNote: @MainActor @Sendable (NoteDigest) -> Void
    private let onCreateNote: @MainActor @Sendable () -> Void
    private let haptic: @MainActor @Sendable () -> Void

    public init(
        store: any NoteStore,
        theme: NoteTheme,
        onClose: @escaping @MainActor @Sendable () -> Void,
        onOpenNote: @escaping @MainActor @Sendable (NoteDigest) -> Void,
        onCreateNote: @escaping @MainActor @Sendable () -> Void,
        onChange: @escaping @MainActor @Sendable () -> Void = {},
        haptic: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        _viewModel = State(initialValue: NotesListViewModel(store: store, onChange: onChange))
        self.theme = theme
        self.onClose = onClose
        self.onOpenNote = onOpenNote
        self.onCreateNote = onCreateNote
        self.haptic = haptic
    }

    public var body: some View {
        let state = viewModel.state
        Group {
            switch state.phase {
            case .idle, .loading: skeleton
            case .failed: failure
            case .loaded where state.isEmptyBecauseStoreIsEmpty: empty
            case .loaded where state.isEmptyBecauseOfFilter: noMatches
            case .loaded: list(state.visibleNotes)
            }
        }
        .background(theme.background)
        .safeAreaInset(edge: .top, spacing: 0) { chrome }
        .noteNavigationChrome()
        .onAppear { viewModel.send(.onAppear) }
        .onChange(of: searchText) { _, query in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                viewModel.send(.updateSearchQuery(query))
            }
        }
        .confirmationDialog(
            Text(.notesKit("Move this note to Recently Deleted?")),
            isPresented: Binding(
                get: { viewModel.state.pendingDiscard != nil },
                set: { if !$0 { viewModel.send(.cancelDiscard) } }
            )
        ) {
            Button(.notesKit("Move to Trash"), role: .destructive) { viewModel.send(.confirmDiscard) }
            Button(.notesKit("Cancel"), role: .cancel) { viewModel.send(.cancelDiscard) }
        }
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel(Text(.notesKit("Back")))
                Text(.notesKit("Private notes")).font(theme.sectionFont).textCase(.uppercase).tracking(2.2)
                Spacer()
                Button(action: onCreateNote) {
                    Image(systemName: "plus")
                        .foregroundStyle(theme.onAccent)
                        .frame(width: 32, height: 32)
                        .background(theme.accent, in: Circle())
                }.accessibilityLabel(Text(.notesKit("New note")))
            }
            .foregroundStyle(theme.primaryText).padding(.horizontal, theme.small)
            searchField
            if !viewModel.state.folderChips.isEmpty { folders }
            Rectangle().fill(theme.separator).frame(height: 0.75)
        }
        .background(theme.background)
    }

    private var searchField: some View {
        HStack(spacing: theme.small) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryText)
            TextField(text: $searchText, prompt: Text(.notesKit("Search notes"))) { EmptyView() }
                .textFieldStyle(.plain).font(theme.monoFont)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, theme.small + 4).frame(height: 36)
        .background(theme.card, in: Capsule()).overlay { Capsule().stroke(theme.separator, lineWidth: 0.75) }
        .padding(.horizontal, theme.medium).padding(.bottom, theme.small)
    }

    private var folders: some View {
        ScrollView(.horizontal) {
            HStack(spacing: theme.xs + 2) {
                chip(Text(.notesKit("All")), count: viewModel.state.index.notes.count, selected: viewModel.state.selectedFolder == nil) {
                    viewModel.send(.selectFolder(nil))
                }
                ForEach(viewModel.state.folderChips) { folder in
                    chip(Text(verbatim: folder.name), count: folder.count, selected: viewModel.state.selectedFolder == folder.name) {
                        viewModel.send(.selectFolder(folder.name))
                    }
                }
            }.padding(.horizontal, theme.medium)
        }.scrollIndicators(.hidden)
    }

    private func chip(_ title: Text, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { haptic(); action() } label: {
            HStack(spacing: 5) { title; Text(count, format: .number) }
                .font(theme.modeFont).textCase(.uppercase).padding(.horizontal, theme.small + 4).frame(height: 31)
                .foregroundStyle(selected ? theme.onAccent : theme.secondaryText)
                .background(selected ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.separator), in: Capsule())
        }.buttonStyle(.plain).frame(minHeight: 44)
    }

    private func list(_ notes: [NoteDigest]) -> some View {
        List {
            ForEach(notes) { note in
                NoteRowCard(note: note, theme: theme, haptic: haptic) { onOpenNote(note) }
                    .listRowInsets(EdgeInsets(top: theme.xs, leading: theme.medium, bottom: theme.xs, trailing: theme.medium))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { viewModel.send(.requestDiscard(note)) } label: {
                            Label(.notesKit("Move to Trash"), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button { viewModel.send(.toggleFavorite(note.id)) } label: {
                            Label(
                                note.isFavorite
                                    ? .notesKit("Remove from Favorites")
                                    : .notesKit("Add to Favorites"),
                                systemImage: "heart"
                            )
                        }.tint(theme.error)
                    }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).refreshable { viewModel.send(.refresh) }
    }

    private var skeleton: some View { placeholder(icon: "note.text", title: .notesKit("Private notes")) }
    private var failure: some View { placeholder(icon: "exclamationmark.triangle", title: .notesKit("Something went wrong.")) }
    private var empty: some View { placeholder(icon: "note.text", title: .notesKit("No notes yet"), message: .notesKit("Notes you write here are sealed in the vault with AES-256.")) }
    private var noMatches: some View { placeholder(icon: "magnifyingglass", title: .notesKit("No matching notes"), message: .notesKit("Titles and previews are searchable. The body of a note is not.")) }

    private func placeholder(
        icon: String,
        title: LocalizedStringResource,
        message: LocalizedStringResource? = nil
    ) -> some View {
        VStack(spacing: theme.medium) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(theme.primaryText)
            Text(title).font(theme.titleFont).textCase(.uppercase).foregroundStyle(theme.primaryText)
            if let message {
                Text(message).font(theme.bodyFont).multilineTextAlignment(.center).foregroundStyle(theme.secondaryText)
            }
        }.padding(theme.large).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
