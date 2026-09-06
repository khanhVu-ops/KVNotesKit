import KVNotesCore
import SwiftUI

public struct NoteEditorScreen: View {
    @State private var viewModel: NoteEditorViewModel
    @State private var showsGenerator = false
    @Namespace private var modeNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase

    private let unlockAuthority: any NoteUnlockAuthority
    private let secretPolicy: any NoteSecretPolicy
    private let theme: NoteTheme
    private let onClose: @MainActor @Sendable () -> Void
    private let onRequestPIN: @MainActor @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
    private let haptic: @MainActor @Sendable () -> Void

    public init(
        note: NoteDigest? = nil,
        template: NoteTemplate? = nil,
        store: any NoteStore,
        unlockAuthority: any NoteUnlockAuthority,
        secretPolicy: any NoteSecretPolicy,
        theme: NoteTheme,
        onClose: @escaping @MainActor @Sendable () -> Void,
        onRequestPIN: @escaping @MainActor @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = { _ in },
        onChange: @escaping @MainActor @Sendable () -> Void = {},
        haptic: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        _viewModel = State(initialValue: NoteEditorViewModel(
            note: note,
            template: template,
            store: store,
            unlockAuthority: unlockAuthority,
            onChange: onChange
        ))
        self.unlockAuthority = unlockAuthority
        self.secretPolicy = secretPolicy
        self.theme = theme
        self.onClose = onClose
        self.onRequestPIN = onRequestPIN
        self.haptic = haptic
    }

    public var body: some View {
        editor
            .overlay {
                if viewModel.state.isLocked, let note = viewModel.state.note {
                    NoteUnlockGate(
                        note: note,
                        offer: unlockAuthority.offer,
                        phase: viewModel.state.unlockPhase,
                        theme: theme,
                        onUnlock: { viewModel.send(.authenticate) },
                        onUsePIN: { onRequestPIN { viewModel.send(.pinAuthenticated) } },
                        onCancel: onClose
                    )
                    .transition(.opacity)
                }
            }
            .animation(NoteMotion.content(reduceMotion: reduceMotion), value: viewModel.state.isLocked)
            .background(theme.background)
            .navigationTitle("")
            .noteInlineNavigationTitle()
            .toolbar { toolbarContent }
            .onAppear { viewModel.send(.onAppear) }
            .onDisappear { if viewModel.state.isDirty { viewModel.send(.save) } }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active, viewModel.state.isDirty { viewModel.send(.save) }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showOptions },
                set: { if !$0 { viewModel.send(.dismissOptions) } }
            )) { options }
            .sheet(isPresented: $showsGenerator) {
                PasswordGeneratorSheet(
                    theme: theme,
                    onInsert: { password in
                        showsGenerator = false
                        viewModel.send(.insertText(password, viewModel.state.selection))
                    },
                    onCancel: { showsGenerator = false }
                )
                .presentationDetents([.medium])
            }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            header
            if viewModel.state.find.isOpen { findBar }
            // Both surfaces stay in the hierarchy across the switch. Rebuilding the text view
            // every time the user previews a note would throw away the caret and the scroll
            // position, and read mode's own state with them.
            // A straight cross-fade leaves two copies of the same paragraph ghosting through
            // each other, because both surfaces draw the note in the same place. A few points of
            // travel in opposite directions separates them without turning a mode switch into a
            // slide show.
            ZStack {
                editBody
                    .opacity(isEditing ? 1 : 0)
                    .offset(y: isEditing ? 0 : -8)
                    .allowsHitTesting(isEditing)
                    .accessibilityHidden(!isEditing)
                readBody
                    .opacity(isEditing ? 0 : 1)
                    .offset(y: isEditing ? 8 : 0)
                    .allowsHitTesting(!isEditing)
                    .accessibilityHidden(isEditing)
            }
        }
        .background(theme.background)
        .animation(NoteMotion.mode(reduceMotion: reduceMotion), value: viewModel.state.mode)
        .animation(NoteMotion.mode(reduceMotion: reduceMotion), value: viewModel.state.find.isOpen)
        .overlay(alignment: .bottom) { savedToast }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                text: Binding(get: { viewModel.state.title }, set: { viewModel.send(.setTitle($0)) }),
                prompt: titlePrompt.foregroundStyle(theme.disabledText)
            ) { Text(.notesKit("Title")) }
                .textFieldStyle(.plain)
                .font(theme.titleFont)
                .foregroundStyle(theme.primaryText)
                .disabled(viewModel.state.mode == .read)
                .autocorrectionDisabled()
                .noteNeverAutocapitalizes()
                .lineLimit(2)
                .padding(.horizontal, theme.medium)
                .padding(.top, theme.small)

            metaRow
        }
    }

    private var titlePrompt: Text {
        viewModel.state.titlePlaceholder.isEmpty
            ? Text(.notesKit("Untitled note"))
            : Text(verbatim: viewModel.state.titlePlaceholder)
    }

    private var metaRow: some View {
        HStack(spacing: theme.small) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal").font(.system(size: 9, weight: .semibold))
                Text(verbatim: "AES-256-GCM")
            }
            .foregroundStyle(theme.success)

            if let folder = viewModel.state.folder {
                divider
                Text(verbatim: folder)
            }
            if viewModel.state.requiresBiometricUnlock {
                divider
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill").font(.system(size: 8, weight: .semibold))
                    Text(.notesKit("Locked"))
                }
            }
            Spacer(minLength: theme.small)
            saveStatus
        }
        .font(theme.metadataFont)
        .tracking(1.1)
        .textCase(.uppercase)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(theme.secondaryText)
        .padding(.horizontal, theme.medium)
        .padding(.top, theme.small)
        .padding(.bottom, theme.small + 4)
    }

    private var divider: some View {
        Rectangle().fill(theme.disabledText).frame(width: 10, height: 0.75)
    }

    @ViewBuilder
    private var saveStatus: some View {
        HStack(spacing: 5) {
            Circle().fill(saveTone).frame(width: 6, height: 6)
            switch viewModel.state.saveStatus {
            case .idle:
                Text(.notesKit(count: "\(viewModel.state.characterCount) characters"))
            case .unsaved:
                Text(.notesKit("Unsaved"))
            case .saving:
                Text(.notesKit("Saving…"))
            case .saved(let date):
                Text(date, format: .dateTime.hour().minute())
            case .failed:
                Text(.notesKit("Not saved"))
            }
        }
        .foregroundStyle(saveTone)
        .contentTransition(.opacity)
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: viewModel.state.saveStatus)
    }

    private var saveTone: Color {
        switch viewModel.state.saveStatus {
        case .idle: theme.disabledText
        case .unsaved: theme.warning
        case .saving: theme.secondaryText
        case .saved: theme.success
        case .failed: theme.error
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .principal) { modeSwitch }
        ToolbarItem(placement: .topBarTrailing) { optionsButton }
        ToolbarItem(placement: .topBarLeading) { findButton }
        #else
        ToolbarItem { modeSwitch }
        ToolbarItem { optionsButton }
        ToolbarItem { findButton }
        #endif
    }

    /// In the toolbar rather than only on the keyboard's accessory bar: looking for something in
    /// a note is what a reader does, and read mode has no keyboard up to hang a key from.
    private var findButton: some View {
        Button {
            haptic()
            viewModel.send(viewModel.state.find.isOpen ? .closeFind : .openFind)
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(viewModel.state.find.isOpen ? theme.accent : theme.primaryText)
        }
        .disabled(viewModel.state.isLocked)
        .accessibilityLabel(Text(.notesKit("Find in note")))
    }

    private var optionsButton: some View {
        Button { viewModel.send(.openOptions) } label: {
            Image(systemName: viewModel.state.requiresBiometricUnlock ? "lock.fill" : "ellipsis")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(viewModel.state.requiresBiometricUnlock ? theme.success : theme.primaryText)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(Text(.notesKit("Note options")))
    }

    private var modeSwitch: some View {
        HStack(spacing: 2) {
            modeButton(.edit, title: .notesKit("Edit"))
            modeButton(.read, title: .notesKit("Read"))
        }
        .padding(3)
        .background(theme.elevatedCard, in: Capsule())
        // The switch lives in the toolbar, outside the body's own animation scope, so it carries
        // the same curve itself — otherwise the pill and the text it reveals move at two speeds.
        .animation(NoteMotion.mode(reduceMotion: reduceMotion), value: viewModel.state.mode)
    }

    private func modeButton(_ mode: NoteEditorState.Mode, title: LocalizedStringResource) -> some View {
        let isSelected = viewModel.state.mode == mode
        return Button {
            haptic()
            viewModel.send(.setMode(mode))
        } label: {
            Text(title)
                .font(theme.modeFont)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(isSelected ? theme.onAccent : theme.secondaryText)
                .padding(.horizontal, theme.small + 4)
                .frame(height: 26)
                .background {
                    // One capsule shared between the two buttons, so it slides across instead of
                    // vanishing under one label and reappearing under the other.
                    if isSelected {
                        Capsule()
                            .fill(theme.accent)
                            .matchedGeometryEffect(id: "mode", in: modeNamespace)
                    }
                }
        }
        .buttonStyle(NotePressButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Reachable from the toolbar while typing and from the options sheet while reading, because
    /// looking for something in a note is not an editing gesture.
    private var findBar: some View {
        HStack(spacing: theme.small) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryText)

            TextField(
                text: Binding(
                    get: { viewModel.state.find.query },
                    set: { viewModel.send(.setFindQuery($0)) }
                ),
                prompt: Text(.notesKit("Find in note")).foregroundStyle(theme.disabledText)
            ) { Text(.notesKit("Find in note")) }
                .textFieldStyle(.plain)
                .font(theme.monoFont)
                .foregroundStyle(theme.primaryText)
                .autocorrectionDisabled()
                .noteNeverAutocapitalizes()
                .submitLabel(.search)
                .onSubmit { viewModel.send(.stepFind(forward: true)) }

            if viewModel.state.find.hasQuery {
                Text(verbatim: "\(viewModel.state.find.currentNumber)/\(viewModel.state.find.matches.count)")
                    .font(theme.metadataFont)
                    .foregroundStyle(viewModel.state.find.matches.isEmpty ? theme.error : theme.secondaryText)
                    .contentTransition(.numericText())
                    .accessibilityLabel(Text(.notesKit("Matches")))
            }

            stepButton(systemImage: "chevron.up", forward: false)
            stepButton(systemImage: "chevron.down", forward: true)

            Button { viewModel.send(.closeFind) } label: {
                Text(.notesKit("Done"))
                    .font(theme.modeFont)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(theme.primaryText)
            }
            .buttonStyle(NotePressButtonStyle())
        }
        .padding(.horizontal, theme.medium)
        .padding(.vertical, theme.small)
        .background(theme.sheet)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.separator).frame(height: 0.75)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(NoteMotion.mode(reduceMotion: reduceMotion), value: viewModel.state.find.matches.count)
    }

    private func stepButton(systemImage: String, forward: Bool) -> some View {
        Button {
            haptic()
            viewModel.send(.stepFind(forward: forward))
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(viewModel.state.find.matches.isEmpty ? theme.disabledText : theme.primaryText)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(NotePressButtonStyle())
        .disabled(viewModel.state.find.matches.isEmpty)
        .accessibilityLabel(Text(forward ? .notesKit("Next match") : .notesKit("Previous match")))
    }

    private var isEditing: Bool { viewModel.state.mode == .edit }

    private var editBody: some View {
        NoteTextEditor(
            text: Binding(get: { viewModel.state.body }, set: { viewModel.send(.setBody($0)) }),
            selection: Binding(
                get: { viewModel.state.selection },
                set: { viewModel.send(.setSelection($0)) }
            ),
            pendingCaretOffset: viewModel.state.pendingCaretOffset,
            theme: theme,
            onCaretApplied: { viewModel.send(.caretApplied) },
            onInsert: { viewModel.send(.insert($0, viewModel.state.selection)) },
            onContinuation: { text, caret in viewModel.send(.applyContinuation(text: text, caretOffset: caret)) },
            onUndo: { viewModel.send(.undo) },
            onRedo: { viewModel.send(.redo) },
            onInsertTimestamp: {
                viewModel.send(.insertText(NoteTimestamp.text(locale: locale), viewModel.state.selection))
            },
            onOpenGenerator: { showsGenerator = true },
            onOpenFind: { viewModel.send(.openFind) },
            onIndent: { viewModel.send(.indent) },
            onOutdent: { viewModel.send(.outdent) },
            canUndo: viewModel.state.canUndo,
            canRedo: viewModel.state.canRedo,
            findMatches: viewModel.state.find.matches,
            currentFindMatch: viewModel.state.find.currentMatch,
            isActive: viewModel.state.mode == .edit,
            doneTitle: NotesLocalization.string("Done", locale: locale),
            undoTitle: NotesLocalization.string("Undo", locale: locale),
            redoTitle: NotesLocalization.string("Redo", locale: locale),
            timestampTitle: NotesLocalization.string("Insert the time", locale: locale),
            generatorTitle: NotesLocalization.string("Generate a password", locale: locale),
            findTitle: NotesLocalization.string("Find in note", locale: locale),
            indentTitle: NotesLocalization.string("Indent", locale: locale),
            outdentTitle: NotesLocalization.string("Outdent", locale: locale),
            haptic: haptic,
            onToggleTask: viewModel.state.isLocked || viewModel.state.isLoading ? nil : { line in
                haptic()
                viewModel.send(.toggleTask(line: line))
            }
        )
    }

    private var readBody: some View {
        NoteMarkdownView(
            markdown: viewModel.state.body,
            theme: theme,
            clipboardLifetime: secretPolicy.transientCopyLifetime,
            copy: { secretPolicy.copyTransient($0) },
            toggleTask: viewModel.state.isLocked || viewModel.state.isLoading ? nil : { line in
                haptic()
                viewModel.send(.toggleTask(line: line))
            }
        )
    }

    @ViewBuilder
    private var savedToast: some View {
        if viewModel.state.showSavedToast {
            HStack(spacing: theme.small) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.success)
                Text(.notesKit("Saved to vault"))
                    .font(theme.modeFont)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(theme.primaryText)
            }
            .padding(.horizontal, theme.medium)
            .padding(.vertical, theme.small + 2)
            .background(theme.card, in: Capsule())
            .overlay { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
            .padding(.bottom, theme.extraLarge)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task {
                try? await Task.sleep(for: .seconds(2))
                viewModel.send(.dismissToast)
            }
        }
    }

    private var options: some View {
        NoteOptionsSheet(
            icon: viewModel.state.icon,
            folder: viewModel.state.folder,
            folders: viewModel.state.folders,
            isLocked: viewModel.state.requiresBiometricUnlock,
            hidesPreview: viewModel.state.hidesPreview,
            metrics: viewModel.state.metrics,
            theme: theme,
            haptic: haptic,
            onIcon: { viewModel.send(.setIcon($0)) },
            onFolder: { viewModel.send(.setFolder($0)) },
            onToggleLock: { viewModel.send(.toggleBiometricLock) },
            onToggleHiddenPreview: { viewModel.send(.toggleHiddenPreview) },
            onDismiss: { viewModel.send(.dismissOptions) }
        )
    }
}
