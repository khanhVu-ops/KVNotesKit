import Foundation
import KVNotesCore
import Observation

public struct NotesListState: Equatable, Sendable {
    private struct SearchHaystackCache: Equatable, Sendable {
        let source: String
        let normalized: String
    }
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, failed }
    /// What the list looks like, as one animatable value.
    public struct Layout: Equatable, Sendable {
        public let order: [NoteID]
        public let pinnedCount: Int

        public init(order: [NoteID], pinnedCount: Int) {
            self.order = order
            self.pinnedCount = pinnedCount
        }
    }
    public struct FolderChip: Identifiable, Equatable, Sendable {
        public let name: String
        public let count: Int
        public var id: String { name }
    }

    public var phase: Phase = .idle
    public var index = NoteIndex()
    public var selectedFolder: String?
    public var searchQuery = ""
    public var sortOrder: NoteSortOrder = .lastEditedNewest
    public var filter: NoteFilter = .all
    /// The filtered list the screen draws, pinned notes first. One array rather than two, so a
    /// note can never be missing from both or present in both.
    public var visibleNotes: [NoteDigest] = []
    /// How many of `visibleNotes` lead it as pinned. The screen slices rather than filters
    /// again, and the count is what tells it whether to draw the pinned header at all.
    public var pinnedCount = 0
    public var folderChips: [FolderChip] = []
    public var pendingDiscard: NoteDigest?
    public var isBusy = false
    private var normalizedSearchHaystacks: [NoteID: SearchHaystackCache] = [:]

    /// Whether anything narrows the list beyond the folder chips, which the header already
    /// shows. Drives the marker on the sort control: a filter left on and forgotten looks
    /// exactly like a vault that lost its notes.
    public var isNarrowed: Bool { filter != .all || sortOrder != .lastEditedNewest }

    public var isEmptyBecauseStoreIsEmpty: Bool { phase == .loaded && index.isEmpty }
    public var isEmptyBecauseOfFilter: Bool {
        phase == .loaded && !index.isEmpty && visibleNotes.isEmpty
    }

    mutating func recompute() {
        let liveIDs = Set(index.notes.map(\.id))
        normalizedSearchHaystacks = normalizedSearchHaystacks.filter { liveIDs.contains($0.key) }
        for note in index.notes {
            let source = note.title + " " + (note.snippet ?? "")
            if normalizedSearchHaystacks[note.id]?.source != source {
                normalizedSearchHaystacks[note.id] = SearchHaystackCache(
                    source: source,
                    normalized: Self.normalize(source)
                )
            }
        }
        let counts = index.notes.reduce(into: [String: Int]()) { result, note in
            if let folder = note.folder { result[folder, default: 0] += 1 }
        }
        folderChips = index.folders.map { FolderChip(name: $0, count: counts[$0, default: 0]) }
        let folderNotes = selectedFolder.map { folder in
            index.notes.filter { $0.folder == folder }
        } ?? index.notes
        let tokens = Self.normalize(searchQuery).split(whereSeparator: \.isWhitespace)
        let searched = tokens.isEmpty ? folderNotes : folderNotes.filter { note in
            let haystack = normalizedSearchHaystacks[note.id]?.normalized ?? ""
            return tokens.allSatisfy(haystack.contains)
        }
        let matched = Self.sorted(searched.filter(passes), by: sortOrder)
        // A stable partition: the store already ordered these by last edit, and pinning must
        // not reshuffle the notes around the one that was pinned.
        let pinned = matched.filter(\.isPinned)
        pinnedCount = pinned.count
        visibleNotes = pinned + matched.filter { !$0.isPinned }
    }

    private func passes(_ note: NoteDigest) -> Bool {
        switch filter {
        case .all: return true
        case .locked: return note.requiresBiometricUnlock
        // A locked note reports `false` whatever it holds (see `withheldWhereLocked`), so this
        // filter never reaches behind the gate.
        case .hasChecklist: return note.hasChecklist
        }
    }

    private static func sorted(_ notes: [NoteDigest], by order: NoteSortOrder) -> [NoteDigest] {
        switch order {
        case .lastEditedNewest: return notes.sorted { $0.lastEditedAt > $1.lastEditedAt }
        case .lastEditedOldest: return notes.sorted { $0.lastEditedAt < $1.lastEditedAt }
        case .createdNewest: return notes.sorted { $0.createdAt > $1.createdAt }
        case .title:
            // `localizedStandardCompare` and not `<`: Vietnamese sorts `Đ` after `D` and before
            // `E`, and a raw String comparison puts every accented title after `Z`.
            return notes.sorted { left, right in
                let comparison = left.title.localizedStandardCompare(right.title)
                return comparison == .orderedSame
                    ? left.lastEditedAt > right.lastEditedAt
                    : comparison == .orderedAscending
            }
        }
    }

    public var pinnedNotes: ArraySlice<NoteDigest> { visibleNotes.prefix(pinnedCount) }
    public var timelineNotes: ArraySlice<NoteDigest> { visibleNotes.dropFirst(pinnedCount) }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "đ", with: "d")
    }
}

@MainActor
@Observable
public final class NotesListViewModel {
    public enum Action: Sendable {
        case onAppear
        case refresh
        case selectFolder(String?)
        case updateSearchQuery(String)
        case setSortOrder(NoteSortOrder)
        case setFilter(NoteFilter)
        case togglePin(NoteID)
        case moveToFolder(NoteID, String?)
        case requestDiscard(NoteDigest)
        case confirmDiscard
        case cancelDiscard
    }

    public private(set) var state = NotesListState()
    @ObservationIgnored private let store: any NoteStore
    @ObservationIgnored private let preferences: (any NoteListPreferencesStore)?
    @ObservationIgnored private let onChange: @MainActor @Sendable () -> Void
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var mutationTask: Task<Void, Never>?

    public init(
        store: any NoteStore,
        preferences: (any NoteListPreferencesStore)? = nil,
        onChange: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.store = store
        self.preferences = preferences
        self.onChange = onChange
        if let stored = preferences?.load() {
            state.sortOrder = stored.sortOrder
            state.filter = stored.filter
        }
    }

    deinit {
        loadTask?.cancel()
        mutationTask?.cancel()
    }

    public func send(_ action: Action) {
        switch action {
        case .onAppear:
            load()
        case .refresh:
            load()
        case .selectFolder(let folder):
            state.selectedFolder = folder
            state.recompute()
        case .updateSearchQuery(let query):
            state.searchQuery = query
            state.recompute()
        case .setSortOrder(let order):
            state.sortOrder = order
            state.recompute()
            rememberHowTheListIsShown()
        case .setFilter(let filter):
            state.filter = filter
            state.recompute()
            rememberHowTheListIsShown()
        case .togglePin(let id):
            guard let index = state.index.notes.firstIndex(where: { $0.id == id }) else { return }
            let pinned = !state.index.notes[index].isPinned
            // Moved locally first, then persisted. Waiting for the round trip means the row sits
            // still under the finger and then jumps a moment later, which reads as a glitch
            // rather than as a move; a failed write reloads and puts it back.
            state.index.notes[index].isPinned = pinned
            state.recompute()
            perform { try await self.store.apply(NoteAttributePatch(isPinned: pinned), to: id) }
        case .moveToFolder(let id, let folder):
            perform { try await self.store.apply(NoteAttributePatch(folder: .set(folder)), to: id) }
        case .requestDiscard(let note):
            state.pendingDiscard = note
        case .confirmDiscard:
            guard let id = state.pendingDiscard?.id else { return }
            state.pendingDiscard = nil
            perform { try await self.store.discard(id); return nil }
        case .cancelDiscard:
            state.pendingDiscard = nil
        }
    }

    private func rememberHowTheListIsShown() {
        preferences?.save(NoteListPreferences(sortOrder: state.sortOrder, filter: state.filter))
    }

    private func load() {
        loadTask?.cancel()
        if state.phase == .idle { state.phase = .loading }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let index = try await store.index()
                guard !Task.isCancelled else { return }
                state.index = index
                if let folder = state.selectedFolder, !index.folders.contains(folder) {
                    state.selectedFolder = nil
                }
                state.phase = .loaded
                state.recompute()
            } catch {
                state.phase = .failed
            }
        }
    }

    private func perform(_ operation: @escaping @Sendable () async throws -> NoteDigest?) {
        guard !state.isBusy else { return }
        state.isBusy = true
        mutationTask = Task { [weak self] in
            guard let self else { return }
            defer { state.isBusy = false }
            do {
                _ = try await operation()
                onChange()
                load()
            } catch {
                state.phase = .failed
            }
        }
    }
}
