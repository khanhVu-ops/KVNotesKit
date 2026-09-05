import Foundation
import KVNotesCore
import Observation

public struct NotesListState: Equatable, Sendable {
    private struct SearchHaystackCache: Equatable, Sendable {
        let source: String
        let normalized: String
    }
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, failed }
    /// Which option sheet is open, if any.
    ///
    /// State rather than a one-shot present, for the same reason the alerts are: it survives a
    /// rebuild, and "the options for note X are open" can be asserted without SwiftUI. The note is
    /// held by id, not by value — a digest captured when the sheet opened would keep drawing the
    /// old pin state after the write it triggered came back.
    public enum OptionSheet: Equatable, Sendable {
        case sortAndFilter
        case note(NoteID)
        case batch
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
    /// Rows or cards. It changes nothing about which notes are shown, only how they are drawn,
    /// so it takes no part in `recompute()`.
    public var layout: NoteListLayout = .list
    /// The filtered list the screen draws, pinned notes first. One array rather than two, so a
    /// note can never be missing from both or present in both.
    public var visibleNotes: [NoteDigest] = []
    /// How many of `visibleNotes` lead it as pinned. The screen slices rather than filters
    /// again, and the count is what tells it whether to draw the pinned header at all.
    public var pinnedCount = 0
    public var folderChips: [FolderChip] = []
    public var pendingDiscard: NoteDigest?
    /// Set while a batch is waiting for the user to confirm sending it to the trash.
    public var pendingBatchDiscard = false
    public var isBusy = false
    public var isSelecting = false
    public var showsFolderManager = false
    public var optionSheet: OptionSheet?
    public var selection: Set<NoteID> = []
    private var normalizedSearchHaystacks: [NoteID: SearchHaystackCache] = [:]

    /// Whether anything narrows the list beyond the folder chips, which the header already
    /// shows. Drives the marker on the sort control: a filter left on and forgotten looks
    /// exactly like a vault that lost its notes.
    public var isNarrowed: Bool { filter != .all || sortOrder != .lastEditedNewest }

    /// The notes a batch action would touch, in the order they are on screen.
    public var selectedNotes: [NoteDigest] { visibleNotes.filter { selection.contains($0.id) } }
    public var isEverythingSelected: Bool {
        !visibleNotes.isEmpty && selection.count == visibleNotes.count
    }
    /// One verb for the whole batch: pinning a mixed selection pins all of it, which is what the
    /// photo grid does with Favourite and what a person means by tapping Pin on five rows.
    public var batchWouldPin: Bool { selectedNotes.contains { !$0.isPinned } }
    public var batchWouldLock: Bool { selectedNotes.contains { !$0.requiresBiometricUnlock } }

    /// The note an open note-options sheet is about, read fresh from the index every time.
    ///
    /// Derived rather than stored: a digest captured when the sheet opened would go on offering
    /// "Pin" to a note the same sheet had just pinned.
    public var optionSheetNote: NoteDigest? {
        guard case .note(let id) = optionSheet else { return nil }
        return index.notes.first { $0.id == id }
    }

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
        case setLayout(NoteListLayout)
        case togglePin(NoteID)
        case moveToFolder(NoteID, String?)
        case requestDiscard(NoteDigest)
        case confirmDiscard
        case cancelDiscard
        case openFolderManager
        case closeFolderManager
        case openOptions(NotesListState.OptionSheet)
        case closeOptions
        case renameFolder(String, to: String)
        case tintFolder(String, NoteFolderTint)
        case removeFolder(String)
        case startSelecting
        case stopSelecting
        case toggleSelection(NoteID)
        case selectAllOrNone
        case batchPin
        case batchLock
        case batchMoveToFolder(String?)
        case requestBatchDiscard
        case confirmBatchDiscard
        case cancelBatchDiscard
    }

    public private(set) var state = NotesListState()
    @ObservationIgnored private let store: any NoteStore
    @ObservationIgnored private let preferences: (any NoteListPreferencesStore)?
    @ObservationIgnored private let onChange: @MainActor @Sendable () -> Void
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var mutationTask: Task<Void, Never>?
    @ObservationIgnored private var queuedWrites = 0

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
            state.layout = stored.layout
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
        case .setLayout(let layout):
            guard state.layout != layout else { return }
            state.layout = layout
            // No `recompute()`: the same notes in the same order, drawn differently.
            rememberHowTheListIsShown()
        case .togglePin(let id):
            guard let index = state.index.notes.firstIndex(where: { $0.id == id }) else { return }
            let pinned = !state.index.notes[index].isPinned
            // Moved locally first, then persisted. Waiting for the round trip means the row sits
            // still under the finger and then jumps a moment later, which reads as a glitch
            // rather than as a move; a failed write reloads and puts it back.
            state.index.notes[index].isPinned = pinned
            state.recompute()
            // Deliberately not `perform`: that reloads the whole index when the write returns,
            // and the list then animated a second time about half a second after the row had
            // already moved. One write, one digest back, one row updated in place.
            update(id) { try await self.store.apply(NoteAttributePatch(isPinned: pinned), to: id) }
        case .moveToFolder(let id, let folder):
            perform { try await self.store.apply(NoteAttributePatch(folder: .set(folder)), to: id) }
        case .requestDiscard(let note):
            // The question replaces the options it was asked from; leaving both open stacks a
            // sheet on a sheet, and the one underneath is about to be answered anyway.
            state.optionSheet = nil
            state.pendingDiscard = note
        case .confirmDiscard:
            guard let id = state.pendingDiscard?.id else { return }
            state.pendingDiscard = nil
            // Gone from the list on the same frame the user confirmed, like the pin moves on
            // the tap: waiting for the write meant the row sat there, then vanished a beat
            // later with no gesture attached to it. A failed write reloads and puts it back.
            state.index.notes.removeAll { $0.id == id }
            state.recompute()
            perform { try await self.store.discard(id); return nil }
        case .cancelDiscard:
            state.pendingDiscard = nil
        case .openFolderManager:
            state.showsFolderManager = true
        case .closeFolderManager:
            state.showsFolderManager = false
        case .openOptions(let sheet):
            state.optionSheet = sheet
        case .closeOptions:
            state.optionSheet = nil
        case .renameFolder(let name, let newName):
            // The folder the user is looking at is about to have a different name; a chip
            // filtering on the old one would show an empty list until the next tap.
            if state.selectedFolder == name { state.selectedFolder = newName }
            perform { _ = try await self.store.renameFolder(name, to: newName); return nil }
        case .tintFolder(let name, let tint):
            perform { _ = try await self.store.tintFolder(name, with: tint); return nil }
        case .removeFolder(let name):
            if state.selectedFolder == name { state.selectedFolder = nil }
            perform { _ = try await self.store.removeFolder(name); return nil }
        case .startSelecting:
            state.isSelecting = true
            state.selection = []
        case .stopSelecting:
            state.isSelecting = false
            state.selection = []
            if state.optionSheet == .batch { state.optionSheet = nil }
        case .toggleSelection(let id):
            if state.selection.contains(id) {
                state.selection.remove(id)
            } else {
                state.selection.insert(id)
            }
        case .selectAllOrNone:
            state.selection = state.isEverythingSelected
                ? []
                : Set(state.visibleNotes.map(\.id))
        case .batchPin:
            let pinned = state.batchWouldPin
            batch { store, id in _ = try await store.apply(NoteAttributePatch(isPinned: pinned), to: id) }
        case .batchLock:
            let locked = state.batchWouldLock
            batch { store, id in
                _ = try await store.apply(NoteAttributePatch(requiresBiometricUnlock: locked), to: id)
            }
        case .batchMoveToFolder(let folder):
            batch { store, id in _ = try await store.apply(NoteAttributePatch(folder: .set(folder)), to: id) }
        case .requestBatchDiscard:
            guard !state.selection.isEmpty else { return }
            state.optionSheet = nil
            state.pendingBatchDiscard = true
        case .cancelBatchDiscard:
            state.pendingBatchDiscard = false
        case .confirmBatchDiscard:
            state.pendingBatchDiscard = false
            // Ids first: the local removal below empties `selectedNotes`, which is derived from
            // the notes the list is showing.
            let discarding = state.selectedNotes.map(\.id)
            state.index.notes.removeAll { discarding.contains($0.id) }
            state.recompute()
            batch(discarding) { store, id in try await store.discard(id) }
        }
    }

    private func rememberHowTheListIsShown() {
        preferences?.save(NoteListPreferences(
            sortOrder: state.sortOrder,
            filter: state.filter,
            layout: state.layout
        ))
    }

    /// Applies one operation to every selected note, in the order the list shows them.
    ///
    /// Sequential rather than concurrent, and that is not laziness: every one of these writes
    /// re-encrypts the same vault, and a `TaskGroup` racing five metadata writes through one
    /// store is how a batch ends up with a note whose attributes came from two different writes.
    /// Selection ends when the batch does — leaving five rows ticked after they have all moved is
    /// a selection of things that are no longer where the user left them.
    private func batch(
        _ ids: [NoteID]? = nil,
        _ operation: @escaping @Sendable (any NoteStore, NoteID) async throws -> Void
    ) {
        let ids = ids ?? state.selectedNotes.map(\.id)
        guard !ids.isEmpty else { return }
        perform { [store] in
            for id in ids { try await operation(store, id) }
            return nil
        }
        state.isSelecting = false
        state.selection = []
    }

    /// Runs one write and folds its result back into the note it belongs to.
    ///
    /// The list is already showing the outcome; a full reload would replay it as a second
    /// animation, which is what made a pinned row appear to move twice.
    private func update(
        _ id: NoteID,
        _ operation: @escaping @Sendable () async throws -> NoteDigest
    ) {
        enqueue { [weak self] in
            guard let self else { return }
            do {
                let digest = try await operation()
                if let index = state.index.notes.firstIndex(where: { $0.id == id }) {
                    state.index.notes[index] = digest
                    state.recompute()
                }
                onChange()
            } catch {
                // The optimistic change was wrong; the reload is what puts it back.
                load()
            }
        }
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
                // A note that has gone — trashed here or elsewhere — must not stay selected, or
                // the next batch acts on an id the store no longer has.
                state.selection.formIntersection(Set(index.notes.map(\.id)))
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
        enqueue { [weak self] in
            guard let self else { return }
            do {
                _ = try await operation()
                onChange()
                load()
            } catch {
                state.phase = .failed
            }
        }
    }

    /// Runs one write after the write before it has finished.
    ///
    /// These all re-encrypt the same vault, so they cannot overlap. The previous version refused
    /// the second write instead of queueing it — `guard !state.isBusy else { return }` — and the
    /// screen had already moved the row optimistically by then, so pinning two notes in quick
    /// succession left the second one pinned on screen and unpinned in the vault until something
    /// reloaded the list and pulled it back down. Dropping a write the user has already been
    /// shown the result of is not backpressure, it is a lie.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = mutationTask
        // Counted, and raised here rather than inside the task: `isBusy` disables the folder
        // sheet and the batch dock, and a flag that only goes up once the write actually starts
        // leaves both live for the frame in which the user could press the same button again.
        queuedWrites += 1
        state.isBusy = true
        mutationTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            defer {
                queuedWrites -= 1
                state.isBusy = queuedWrites > 0
            }
            await work()
        }
    }
}
