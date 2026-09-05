import Foundation
import KVNotesCore
import Observation

public struct NoteEditorState: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case edit, read }
    public enum SaveStatus: Equatable, Sendable { case idle, unsaved, saving, saved(Date), failed }

    public var note: NoteDigest?
    public var title = ""
    public var body = ""
    public var folder: String?
    public var icon: String?
    public var requiresBiometricUnlock = false
    public var mode: Mode = .edit
    public var saveStatus: SaveStatus = .idle
    public var folders: [String] = []
    public var isLoading = false
    public var isLocked = false
    public var isAuthenticating = false
    public var authenticationDenied = false
    public var showOptions = false
    public var pendingCaretOffset: Int?

    public var characterCount: Int { body.count }
    public var titlePlaceholder: String { NoteTextDerivation.derivedTitle(from: body) }
    public var hasContent: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public var isDirty: Bool {
        switch saveStatus { case .unsaved, .failed: true; default: false }
    }
}

@MainActor
@Observable
public final class NoteEditorViewModel {
    public static let autosaveDelay: Duration = .milliseconds(1_200)
    public enum Action: Sendable {
        case onAppear
        case setTitle(String)
        case setBody(String)
        case setMode(NoteEditorState.Mode)
        case insert(MarkdownToken, Range<Int>)
        case caretApplied
        case save
        case setFolder(String?)
        case setIcon(String?)
        case toggleBiometricLock
        case openOptions
        case dismissOptions
        case authenticate
        case pinAuthenticated
        case sessionLocked
    }

    public private(set) var state: NoteEditorState
    @ObservationIgnored private let store: any NoteStore
    @ObservationIgnored private let unlockAuthority: any NoteUnlockAuthority
    @ObservationIgnored private let onChange: @MainActor @Sendable () -> Void
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var workTask: Task<Void, Never>?

    public init(
        note: NoteDigest? = nil,
        store: any NoteStore,
        unlockAuthority: any NoteUnlockAuthority,
        onChange: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.store = store
        self.unlockAuthority = unlockAuthority
        self.onChange = onChange
        var state = NoteEditorState()
        state.note = note
        state.title = note?.isTitleUserProvided == true ? note?.title ?? "" : ""
        state.folder = note?.folder
        state.icon = note?.icon
        state.requiresBiometricUnlock = note?.requiresBiometricUnlock ?? false
        state.mode = note == nil ? .edit : .read
        state.isLoading = note != nil
        state.isLocked = note?.requiresBiometricUnlock ?? false
        self.state = state
    }

    deinit { autosaveTask?.cancel(); workTask?.cancel() }

    public func send(_ action: Action) {
        switch action {
        case .onAppear:
            loadIndex()
            if !state.isLocked { loadBody() }
        case .setTitle(let title):
            guard title != state.title else { return }
            state.title = title; dirty()
        case .setBody(let body):
            guard body != state.body else { return }
            state.body = body; dirty()
        case .setMode(let mode):
            if state.isDirty { save() }
            state.mode = mode
        case .insert(let token, let selection):
            let result = MarkdownInsertion.apply(token, to: state.body, selection: selection)
            state.body = result.text
            state.pendingCaretOffset = result.caretOffset
            dirty()
        case .caretApplied:
            state.pendingCaretOffset = nil
        case .save:
            save()
        case .setFolder(let folder):
            state.folder = folder
            apply(NoteAttributePatch(folder: .set(folder)))
        case .setIcon(let icon):
            state.icon = icon
            apply(NoteAttributePatch(icon: .set(icon)))
        case .toggleBiometricLock:
            state.requiresBiometricUnlock.toggle()
            apply(NoteAttributePatch(requiresBiometricUnlock: state.requiresBiometricUnlock))
        case .openOptions:
            if state.note == nil, state.hasContent { save() }
            state.showOptions = true
        case .dismissOptions:
            state.showOptions = false
        case .authenticate:
            authenticate()
        case .pinAuthenticated:
            state.isLocked = false
            state.authenticationDenied = false
            loadBody()
        case .sessionLocked:
            autosaveTask?.cancel()
            workTask?.cancel()
            state.body = ""
            state.title = ""
            state.isLocked = state.note?.requiresBiometricUnlock ?? false
            state.saveStatus = .idle
        }
    }

    private func dirty() {
        state.saveStatus = .unsaved
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func loadIndex() {
        Task { [weak self] in
            guard let self else { return }
            if let index = try? await store.index() { state.folders = index.folders }
        }
    }

    private func loadBody() {
        guard let id = state.note?.id, state.isLoading else { return }
        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                state.body = try await store.body(id)
                state.isLoading = false
            } catch {
                state.isLoading = false
                state.saveStatus = .failed
            }
        }
    }

    private func authenticate() {
        guard state.isLocked, !state.isAuthenticating else { return }
        state.isAuthenticating = true
        state.authenticationDenied = false
        workTask = Task { [weak self] in
            guard let self else { return }
            defer { state.isAuthenticating = false }
            do {
                if try await unlockAuthority.authenticate(reason: .notesKit("Unlocking private note")) {
                    state.isLocked = false
                    loadBody()
                } else {
                    state.authenticationDenied = true
                }
            } catch {
                state.authenticationDenied = true
            }
        }
    }

    private func save() {
        guard state.hasContent, state.saveStatus != .saving else { return }
        autosaveTask?.cancel()
        state.saveStatus = .saving
        let body = state.body
        let title = state.title
        let existing = state.note
        let draft = NoteDraft(
            body: body,
            title: title,
            folder: state.folder,
            icon: state.icon,
            requiresBiometricUnlock: state.requiresBiometricUnlock
        )
        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                let saved = if let existing {
                    try await store.update(existing.id, body: body, title: title)
                } else {
                    try await store.create(draft)
                }
                state.note = saved
                state.folder = saved.folder
                state.icon = saved.icon
                state.saveStatus = .saved(saved.lastEditedAt)
                onChange()
            } catch {
                state.saveStatus = .failed
            }
        }
    }

    private func apply(_ patch: NoteAttributePatch) {
        guard let id = state.note?.id else { return }
        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                state.note = try await store.apply(patch, to: id)
                onChange()
                loadIndex()
            } catch {
                state.saveStatus = .failed
            }
        }
    }
}
