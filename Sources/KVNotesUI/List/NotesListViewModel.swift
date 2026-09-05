import Foundation
import KVNotesCore
import Observation

public struct NotesListState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, failed }
    public struct FolderChip: Identifiable, Equatable, Sendable {
        public let name: String
        public let count: Int
        public var id: String { name }
    }

    public var phase: Phase = .idle
    public var index = NoteIndex()
    public var selectedFolder: String?
    public var searchQuery = ""
    public var visibleNotes: [NoteDigest] = []
    public var folderChips: [FolderChip] = []
    public var pendingDiscard: NoteDigest?
    public var isBusy = false

    public var isEmptyBecauseStoreIsEmpty: Bool { phase == .loaded && index.isEmpty }
    public var isEmptyBecauseOfFilter: Bool {
        phase == .loaded && !index.isEmpty && visibleNotes.isEmpty
    }

    mutating func recompute() {
        let counts = index.notes.reduce(into: [String: Int]()) { result, note in
            if let folder = note.folder { result[folder, default: 0] += 1 }
        }
        folderChips = index.folders.map { FolderChip(name: $0, count: counts[$0, default: 0]) }
        let folderNotes = selectedFolder.map { folder in
            index.notes.filter { $0.folder == folder }
        } ?? index.notes
        let tokens = Self.normalize(searchQuery).split(whereSeparator: \.isWhitespace)
        visibleNotes = tokens.isEmpty ? folderNotes : folderNotes.filter { note in
            let haystack = Self.normalize(note.title + " " + (note.snippet ?? ""))
            return tokens.allSatisfy(haystack.contains)
        }
    }

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
        case toggleFavorite(NoteID)
        case moveToFolder(NoteID, String?)
        case requestDiscard(NoteDigest)
        case confirmDiscard
        case cancelDiscard
    }

    public private(set) var state = NotesListState()
    @ObservationIgnored private let store: any NoteStore
    @ObservationIgnored private let onChange: @MainActor @Sendable () -> Void
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(store: any NoteStore, onChange: @escaping @MainActor @Sendable () -> Void = {}) {
        self.store = store
        self.onChange = onChange
    }

    public func send(_ action: Action) {
        switch action {
        case .onAppear:
            guard state.phase == .idle else { return }
            load()
        case .refresh:
            load()
        case .selectFolder(let folder):
            state.selectedFolder = folder
            state.recompute()
        case .updateSearchQuery(let query):
            state.searchQuery = query
            state.recompute()
        case .toggleFavorite(let id):
            guard let note = state.index.notes.first(where: { $0.id == id }) else { return }
            perform { try await self.store.apply(NoteAttributePatch(isFavorite: !note.isFavorite), to: id) }
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

    private func load() {
        task?.cancel()
        state.phase = .loading
        task = Task { [weak self] in
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
        task = Task { [weak self] in
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
