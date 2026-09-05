import KVNotesCore
import SwiftUI

public struct NoteEditorScreen: View {
    @State private var viewModel: NoteEditorViewModel
    @State private var selection = 0..<0
    private let unlockAuthority: any NoteUnlockAuthority
    private let secretPolicy: any NoteSecretPolicy
    private let theme: NoteTheme
    private let onClose: @MainActor @Sendable () -> Void
    private let haptic: @MainActor @Sendable () -> Void

    public init(
        note: NoteDigest? = nil,
        store: any NoteStore,
        unlockAuthority: any NoteUnlockAuthority,
        secretPolicy: any NoteSecretPolicy,
        theme: NoteTheme,
        onClose: @escaping @MainActor @Sendable () -> Void,
        onChange: @escaping @MainActor @Sendable () -> Void = {},
        haptic: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        _viewModel = State(initialValue: NoteEditorViewModel(
            note: note,
            store: store,
            unlockAuthority: unlockAuthority,
            onChange: onChange
        ))
        self.unlockAuthority = unlockAuthority
        self.secretPolicy = secretPolicy
        self.theme = theme
        self.onClose = onClose
        self.haptic = haptic
    }

    public var body: some View {
        Group {
            if viewModel.state.isLocked, let note = viewModel.state.note {
                NoteUnlockGate(
                    note: note,
                    offer: unlockAuthority.offer,
                    isAuthenticating: viewModel.state.isAuthenticating,
                    denied: viewModel.state.authenticationDenied,
                    theme: theme,
                    onUnlock: { viewModel.send(.authenticate) },
                    onCancel: onClose
                )
            } else {
                editor
            }
        }
        .background(theme.background)
        .noteNavigationChrome()
        .onAppear { viewModel.send(.onAppear) }
        .onDisappear { if viewModel.state.isDirty { viewModel.send(.save) } }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showOptions },
            set: { if !$0 { viewModel.send(.dismissOptions) } }
        )) { options }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            header
            titleField
            modePicker
            if viewModel.state.mode == .edit { editBody } else { readBody }
        }
    }

    private var header: some View {
        HStack {
            Button { if viewModel.state.isDirty { viewModel.send(.save) }; onClose() } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }.accessibilityLabel(Text("Back"))
            Spacer()
            saveStatus
            Button { viewModel.send(.openOptions) } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }.accessibilityLabel(Text("Note options"))
        }.foregroundStyle(theme.primaryText).padding(.horizontal, theme.small)
    }

    private var titleField: some View {
        TextField(
            text: Binding(get: { viewModel.state.title }, set: { viewModel.send(.setTitle($0)) }),
            prompt: Text(verbatim: viewModel.state.titlePlaceholder)
        ) { Text("Title") }
        .font(theme.titleFont).foregroundStyle(theme.primaryText).textFieldStyle(.plain)
        .padding(.horizontal, theme.medium).padding(.vertical, theme.small)
        .autocorrectionDisabled()
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            modeButton("Edit", .edit)
            modeButton("Read", .read)
        }.padding(3).background(theme.card, in: Capsule()).padding(.horizontal, theme.medium)
    }

    private func modeButton(_ title: LocalizedStringResource, _ mode: NoteEditorState.Mode) -> some View {
        Button { haptic(); viewModel.send(.setMode(mode)) } label: {
            Text(title).font(theme.modeFont).textCase(.uppercase).frame(maxWidth: .infinity).frame(height: 30)
                .foregroundStyle(viewModel.state.mode == mode ? theme.onAccent : theme.secondaryText)
                .background(viewModel.state.mode == mode ? theme.accent : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    private var editBody: some View {
        VStack(spacing: 0) {
            NoteTextEditor(
                text: Binding(get: { viewModel.state.body }, set: { viewModel.send(.setBody($0)) }),
                pendingCaretOffset: viewModel.state.pendingCaretOffset,
                theme: theme,
                onSelection: { selection = $0 },
                onCaretApplied: { viewModel.send(.caretApplied) }
            )
            toolbar
        }
    }

    private var toolbar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: theme.small) {
                ForEach(MarkdownToken.allCases) { token in
                    Button { haptic(); viewModel.send(.insert(token, selection)) } label: {
                        Text(verbatim: token.keyTitle).font(theme.modeFont).frame(minWidth: 36, minHeight: 36)
                            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.smallRadius))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, theme.medium).padding(.vertical, theme.small)
        }.scrollIndicators(.hidden).foregroundStyle(theme.primaryText)
    }

    private var readBody: some View {
        NoteMarkdownView(markdown: viewModel.state.body, theme: theme) { secretPolicy.copyTransient($0) }
    }

    @ViewBuilder private var saveStatus: some View {
        switch viewModel.state.saveStatus {
        case .saving: Text("Saving…")
        case .saved: Text("Saved to vault")
        case .failed: Text("Not saved")
        case .idle, .unsaved: EmptyView()
        }
    }

    private var options: some View {
        NoteOptionsSheet(
            icon: viewModel.state.icon,
            folder: viewModel.state.folder,
            folders: viewModel.state.folders,
            isLocked: viewModel.state.requiresBiometricUnlock,
            theme: theme,
            haptic: haptic,
            onIcon: { viewModel.send(.setIcon($0)) },
            onFolder: { viewModel.send(.setFolder($0)) },
            onToggleLock: { viewModel.send(.toggleBiometricLock) },
            onDismiss: { viewModel.send(.dismissOptions) }
        )
    }
}
