import Foundation
import KVNotesCore
import Observation

public struct NoteEditorState: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case edit, read }
    public enum SaveStatus: Equatable, Sendable { case idle, unsaved, saving, saved(Date), failed }
    public enum UnlockPhase: Equatable, Sendable { case waiting, authenticating, denied, granted }

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
    public var unlockPhase: UnlockPhase = .waiting
    public var showOptions = false
    public var showSavedToast = false
    public var pendingCaretOffset: Int?

    public var isAuthenticating: Bool { unlockPhase == .authenticating }
    public var authenticationDenied: Bool { unlockPhase == .denied }

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
        case toggleTask(line: Int)
        case caretApplied
        case save
        case setFolder(String?)
        case setIcon(String?)
        case toggleBiometricLock
        case openOptions
        case dismissOptions
        case dismissToast
        case authenticate
        case pinAuthenticated
        case sessionLocked
    }

    public private(set) var state: NoteEditorState
    @ObservationIgnored private let store: any NoteStore
    @ObservationIgnored private let unlockAuthority: any NoteUnlockAuthority
    @ObservationIgnored private let onChange: @MainActor @Sendable () -> Void
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var authenticationTask: Task<Void, Never>?
    @ObservationIgnored private var gateTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var attributeTask: Task<Void, Never>?
    @ObservationIgnored private var queuedSave = false

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

    deinit {
        autosaveTask?.cancel()
        loadTask?.cancel()
        authenticationTask?.cancel()
        gateTask?.cancel()
        saveTask?.cancel()
        attributeTask?.cancel()
    }

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
            guard mode != state.mode else { return }
            if state.isDirty { save() }
            state.mode = mode
        case .insert(let token, let selection):
            let result = MarkdownInsertion.apply(token, to: state.body, selection: selection)
            state.body = result.text
            state.pendingCaretOffset = result.caretOffset
            dirty()
        case .toggleTask(let line):
            // Read mode becomes a write path here, and it takes the same one every other change
            // takes: mutate the body, then `save()`, which serialises behind an in-flight save
            // and queues a second tap rather than racing it. A note whose gate has not opened has
            // no body loaded, so there is nothing to toggle.
            guard !state.isLocked, !state.isLoading else { return }
            let toggled = NoteMarkdownBlock.togglingTask(atLine: line, in: state.body)
            guard toggled != state.body else { return }
            state.body = toggled
            state.saveStatus = .unsaved
            save()
        case .caretApplied:
            state.pendingCaretOffset = nil
        case .save:
            save()
        case .setFolder(let folder):
            state.folder = folder
            if state.note == nil {
                if state.hasContent { save() }
            } else {
                apply(NoteAttributePatch(folder: .set(folder)))
            }
        case .setIcon(let icon):
            state.icon = icon
            if state.note == nil {
                if state.hasContent { save() }
            } else {
                apply(NoteAttributePatch(icon: .set(icon)))
            }
        case .toggleBiometricLock:
            state.requiresBiometricUnlock.toggle()
            if state.note == nil {
                if state.hasContent { save() }
            } else {
                apply(NoteAttributePatch(requiresBiometricUnlock: state.requiresBiometricUnlock))
            }
        case .openOptions:
            if state.note == nil, state.hasContent { save() }
            state.showOptions = true
        case .dismissOptions:
            state.showOptions = false
        case .dismissToast:
            state.showSavedToast = false
        case .authenticate:
            authenticate()
        case .pinAuthenticated:
            openGate()
        case .sessionLocked:
            autosaveTask?.cancel()
            loadTask?.cancel()
            authenticationTask?.cancel()
            gateTask?.cancel()
            saveTask?.cancel()
            attributeTask?.cancel()
            queuedSave = false
            state.body = ""
            state.title = ""
            state.isLocked = state.note?.requiresBiometricUnlock ?? false
            state.unlockPhase = .waiting
            state.saveStatus = .idle
            state.showSavedToast = false
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
        loadTask?.cancel()
        loadTask = Task { [weak self] in
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
        guard state.isLocked, authenticationTask == nil else { return }
        guard unlockAuthority.offer.biometric != nil else { return }
        state.unlockPhase = .authenticating
        authenticationTask = Task { [weak self] in
            guard let self else { return }
            defer { authenticationTask = nil }
            do {
                if try await unlockAuthority.authenticate(reason: .notesKit("Unlocking private note")) {
                    openGate()
                } else {
                    state.unlockPhase = .denied
                }
            } catch {
                state.unlockPhase = .denied
            }
        }
    }

    private func openGate() {
        state.unlockPhase = .granted
        gateTask?.cancel()
        gateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled, let self else { return }
            state.isLocked = false
            state.unlockPhase = .waiting
            loadBody()
            gateTask = nil
        }
    }

    private func save() {
        autosaveTask?.cancel()
        guard state.hasContent else {
            state.saveStatus = .idle
            return
        }
        guard state.isDirty else { return }
        if saveTask != nil {
            queuedSave = true
            return
        }
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
        saveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let saved = if let existing {
                    try await store.update(existing.id, body: body, title: title)
                } else {
                    try await store.create(draft)
                }
                let desiredFolder = state.folder
                let desiredIcon = state.icon
                let desiredLock = state.requiresBiometricUnlock
                state.note = saved
                state.folder = desiredFolder
                state.icon = desiredIcon
                state.requiresBiometricUnlock = desiredLock
                saveTask = nil
                onChange()
                let attributePatch = NoteAttributePatch(
                    folder: saved.folder == desiredFolder ? .unchanged : .set(desiredFolder),
                    icon: saved.icon == desiredIcon ? .unchanged : .set(desiredIcon),
                    requiresBiometricUnlock: saved.requiresBiometricUnlock == desiredLock ? nil : desiredLock
                )
                if attributePatch.folder != .unchanged
                    || attributePatch.icon != .unchanged
                    || attributePatch.requiresBiometricUnlock != nil {
                    apply(attributePatch)
                }
                let changedWhileSaving = state.body != body || state.title != title
                if changedWhileSaving || queuedSave {
                    queuedSave = false
                    state.saveStatus = .unsaved
                    save()
                } else {
                    state.saveStatus = .saved(saved.lastEditedAt)
                    state.showSavedToast = true
                }
            } catch {
                saveTask = nil
                queuedSave = false
                state.saveStatus = .failed
            }
        }
    }

    private func apply(_ patch: NoteAttributePatch) {
        guard let id = state.note?.id else { return }
        attributeTask?.cancel()
        attributeTask = Task { [weak self] in
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
