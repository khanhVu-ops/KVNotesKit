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
    public var hidesPreview = false
    public var mode: Mode = .edit
    public var saveStatus: SaveStatus = .idle
    public var folders: [String] = []
    public var isLoading = false
    public var isLocked = false
    public var unlockPhase: UnlockPhase = .waiting
    public var showOptions = false
    public var showSavedToast = false
    public var pendingCaretOffset: Int?
    /// Where the caret is, as the ViewModel's own fact.
    ///
    /// It lived in the screen as `@State` and that was a bug with a long fuse: a sheet's content
    /// closure captures the view struct as it was when the sheet was built, so the generator
    /// inserted its password wherever the caret had been *before* the clock key ran. A reference
    /// the closure reads through cannot go stale that way.
    public var selection = 0..<0
    public var canUndo = false
    public var canRedo = false
    public var find = Find()

    /// Find-in-note, as state rather than as a one-shot effect: it survives a rebuild, and the
    /// match count can be asserted without SwiftUI.
    public struct Find: Equatable, Sendable {
        public var isOpen = false
        public var query = ""
        /// Ranges into the body, in UTF-16 units — the editor highlights and scrolls with them.
        public var matches: [NSRange] = []
        public var currentIndex = 0

        public var currentMatch: NSRange? {
            matches.indices.contains(currentIndex) ? matches[currentIndex] : nil
        }
        public var hasQuery: Bool {
            !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        /// The ordinal a human reads: 1-based, and 0 when there is nothing to count.
        public var currentNumber: Int { matches.isEmpty ? 0 : currentIndex + 1 }
    }

    public var isAuthenticating: Bool { unlockPhase == .authenticating }
    public var authenticationDenied: Bool { unlockPhase == .denied }

    public var initialTemplateMarkdown: String?

    public var characterCount: Int { body.count }
    public var titlePlaceholder: String { NoteTextDerivation.derivedTitle(from: body) }
    public var hasContent: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return true }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let initial = initialTemplateMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return trimmedBody != initial && !trimmedBody.isEmpty
        }
        return !trimmedBody.isEmpty
    }
    public var isDirty: Bool {
        switch saveStatus { case .unsaved, .failed: true; default: false }
    }
}

@MainActor
@Observable
public final class NoteEditorViewModel {
    public static let autosaveDelay: Duration = .milliseconds(1_200)
    /// Typing inside this window folds into the previous undo entry, so one undo removes a word
    /// rather than a keystroke. Anything else — a toolbar key, a ticked checkbox, a pause — opens
    /// a new entry.
    static let undoCoalescingWindow: TimeInterval = 0.8
    /// Enough history to walk back through a session's edits; the cap is what keeps a long note
    /// from holding dozens of copies of itself in memory.
    static let undoLimit = 60

    /// One point the editor can return to.
    private struct EditorSnapshot: Equatable {
        var body: String
        var title: String
    }
    public enum Action: Sendable {
        case onAppear
        case setTitle(String)
        case setBody(String)
        case setMode(NoteEditorState.Mode)
        case insert(MarkdownToken, Range<Int>)
        case insertText(String, Range<Int>)
        case applyContinuation(text: String, caretOffset: Int)
        case setSelection(Range<Int>)
        case openFind
        case closeFind
        case setFindQuery(String)
        case stepFind(forward: Bool)
        case undo
        case redo
        case toggleTask(line: Int)
        case caretApplied
        case save
        case setFolder(String?)
        case setIcon(String?)
        case toggleBiometricLock
        case toggleHiddenPreview
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
    @ObservationIgnored private var undoStack: [EditorSnapshot] = []
    @ObservationIgnored private var redoStack: [EditorSnapshot] = []
    @ObservationIgnored private var lastTypingSnapshotAt: Date?

    public init(
        note: NoteDigest? = nil,
        template: NoteTemplate? = nil,
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
        state.icon = note?.icon ?? template?.defaultIcon
        state.requiresBiometricUnlock = note?.requiresBiometricUnlock ?? false
        state.hidesPreview = note?.hidesPreview ?? false
        state.mode = note == nil ? .edit : .read
        state.isLoading = note != nil
        state.isLocked = note?.requiresBiometricUnlock ?? false
        if note == nil, let template, !template.initialMarkdown.isEmpty {
            state.body = template.initialMarkdown
            state.initialTemplateMarkdown = template.initialMarkdown
            state.pendingCaretOffset = template.initialCaretOffset
            state.selection = template.initialCaretOffset..<template.initialCaretOffset
        }
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
            recordUndoSnapshot(coalescingTyping: true)
            state.title = title; dirty()
        case .setBody(let body):
            guard body != state.body else { return }
            recordUndoSnapshot(coalescingTyping: true)
            state.body = body; dirty()
        case .setMode(let mode):
            guard mode != state.mode else { return }
            if state.isDirty { save() }
            state.mode = mode
        case .insert(let token, let selection):
            recordUndoSnapshot(coalescingTyping: false)
            let result = MarkdownInsertion.apply(token, to: state.body, selection: selection)
            state.body = result.text
            state.pendingCaretOffset = result.caretOffset
            state.selection = result.caretOffset..<result.caretOffset
            dirty()
        case .toggleTask(let line):
            // Read mode becomes a write path here, and it takes the same one every other change
            // takes: mutate the body, then `save()`, which serialises behind an in-flight save
            // and queues a second tap rather than racing it. A note whose gate has not opened has
            // no body loaded, so there is nothing to toggle.
            guard !state.isLocked, !state.isLoading else { return }
            let toggled = NoteMarkdownBlock.togglingTask(atLine: line, in: state.body)
            guard toggled != state.body else { return }
            recordUndoSnapshot(coalescingTyping: false)
            state.body = toggled
            state.saveStatus = .unsaved
            save()
        case .insertText(let value, let selection):
            guard !value.isEmpty else { return }
            recordUndoSnapshot(coalescingTyping: false)
            let lower = min(max(selection.lowerBound, 0), state.body.count)
            let upper = min(max(selection.upperBound, lower), state.body.count)
            let start = state.body.index(state.body.startIndex, offsetBy: lower)
            let end = state.body.index(state.body.startIndex, offsetBy: upper)
            state.body.replaceSubrange(start..<end, with: value)
            let caret = lower + value.count
            state.pendingCaretOffset = caret
            state.selection = caret..<caret
            dirty()
        case .applyContinuation(let text, let caret):
            recordUndoSnapshot(coalescingTyping: false)
            state.body = text
            state.selection = caret..<caret
            dirty()
        case .setSelection(let range):
            guard range != state.selection else { return }
            state.selection = range
        case .openFind:
            // Find reads the note's source, so it opens the editor. Searching the rendered view
            // would highlight text at offsets that do not exist in what is stored.
            state.mode = .edit
            state.find.isOpen = true
            refreshFindMatches(startingAt: state.selection.lowerBound)
        case .closeFind:
            state.find = NoteEditorState.Find()
        case .setFindQuery(let query):
            guard query != state.find.query else { return }
            state.find.query = query
            refreshFindMatches(startingAt: state.selection.lowerBound)
        case .stepFind(let forward):
            guard !state.find.matches.isEmpty else { return }
            let count = state.find.matches.count
            state.find.currentIndex = (state.find.currentIndex + (forward ? 1 : count - 1)) % count
        case .undo:
            step(undoing: true)
        case .redo:
            step(undoing: false)
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
        case .toggleHiddenPreview:
            state.hidesPreview.toggle()
            if state.note == nil {
                if state.hasContent { save() }
            } else {
                apply(NoteAttributePatch(hidesPreview: state.hidesPreview))
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
            // History is plaintext by another name: every entry holds a copy of the note. It goes
            // when the session does, for the same reason `body` does.
            undoStack.removeAll()
            redoStack.removeAll()
            lastTypingSnapshotAt = nil
            state.canUndo = false
            state.canRedo = false
        }
    }

    /// Undo is owned here rather than by the `UITextView`, and that is a decision NK-210 had to
    /// make either way.
    ///
    /// UIKit's own stack is destroyed by assigning `.text`, which is exactly what a toolbar
    /// insertion and a ticked checkbox do — so the UIKit route would have left undo silently
    /// dead right after the formatting keys this task adds. One stack in the ViewModel covers
    /// typing, the toolbar and the checkboxes at once, survives the read/edit switch by
    /// construction, and can be tested without a simulator.
    private func recordUndoSnapshot(coalescingTyping: Bool) {
        let now = Date()
        if coalescingTyping,
           let last = lastTypingSnapshotAt,
           now.timeIntervalSince(last) < Self.undoCoalescingWindow,
           !undoStack.isEmpty {
            lastTypingSnapshotAt = now
            return
        }
        undoStack.append(EditorSnapshot(body: state.body, title: state.title))
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        lastTypingSnapshotAt = coalescingTyping ? now : nil
        refreshHistoryFlags()
    }

    /// One method rather than two `inout` stacks: passing both arrays of the same object as
    /// `inout` is overlapping exclusive access, and Swift 6 traps on it at runtime.
    private func step(undoing: Bool) {
        guard let snapshot = undoing ? undoStack.popLast() : redoStack.popLast() else { return }
        let current = EditorSnapshot(body: state.body, title: state.title)
        if undoing { redoStack.append(current) } else { undoStack.append(current) }
        state.body = snapshot.body
        state.title = snapshot.title
        // The caret would otherwise stay where it was in text that no longer exists.
        state.pendingCaretOffset = min(state.pendingCaretOffset ?? snapshot.body.count, snapshot.body.count)
        lastTypingSnapshotAt = nil
        refreshHistoryFlags()
        dirty()
    }

    private func refreshHistoryFlags() {
        state.canUndo = !undoStack.isEmpty
        state.canRedo = !redoStack.isEmpty
    }

    /// Recomputed whenever the query or the body changes, because a match range into text that
    /// has moved is a highlight over the wrong words.
    private func refreshFindMatches(startingAt caret: Int) {
        guard state.find.isOpen, state.find.hasQuery else {
            state.find.matches = []
            state.find.currentIndex = 0
            return
        }
        let matches = NoteFind.matches(of: state.find.query, in: state.body as NSString)
        state.find.matches = matches
        state.find.currentIndex = NoteFind.indexOfMatch(at: caret, in: matches) ?? 0
    }

    private func dirty() {
        state.saveStatus = .unsaved
        // The body just changed under the matches.
        if state.find.isOpen { refreshFindMatches(startingAt: state.find.currentMatch?.location ?? 0) }
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
            requiresBiometricUnlock: state.requiresBiometricUnlock,
            hidesPreview: state.hidesPreview
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
                let desiredHiding = state.hidesPreview
                state.note = saved
                state.initialTemplateMarkdown = nil
                state.folder = desiredFolder
                state.icon = desiredIcon
                state.requiresBiometricUnlock = desiredLock
                state.hidesPreview = desiredHiding
                saveTask = nil
                onChange()
                let attributePatch = NoteAttributePatch(
                    folder: saved.folder == desiredFolder ? .unchanged : .set(desiredFolder),
                    icon: saved.icon == desiredIcon ? .unchanged : .set(desiredIcon),
                    requiresBiometricUnlock: saved.requiresBiometricUnlock == desiredLock ? nil : desiredLock,
                    hidesPreview: saved.hidesPreview == desiredHiding ? nil : desiredHiding
                )
                if attributePatch.folder != .unchanged
                    || attributePatch.icon != .unchanged
                    || attributePatch.requiresBiometricUnlock != nil
                    || attributePatch.hidesPreview != nil {
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
