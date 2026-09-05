import SwiftUI

struct NoteOptionsSheet: View {
    static let icons = ["🔑", "🏦", "💳", "🧾", "📓", "🖥", "🔒", "🧭", "✈️", "🏠", "💊", "🎓"]
    let icon: String?
    let folder: String?
    let folders: [String]
    let isLocked: Bool
    let theme: NoteTheme
    let haptic: @MainActor @Sendable () -> Void
    let onIcon: (String?) -> Void
    let onFolder: (String?) -> Void
    let onToggleLock: () -> Void
    let onDismiss: () -> Void
    @State private var newFolder = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.large) {
                section(.notesKit("Icon")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                        iconButton(nil, label: "Aa")
                        ForEach(Self.icons, id: \.self) { iconButton($0, label: $0) }
                    }
                }
                section(.notesKit("Folder")) {
                    VStack(alignment: .leading, spacing: theme.small) {
                        ScrollView(.horizontal) {
                            HStack {
                                folderButton(nil, label: Text(.notesKit("No folder")))
                                ForEach(folders, id: \.self) { folderButton($0, label: Text(verbatim: $0)) }
                            }
                        }.scrollIndicators(.hidden)
                        HStack {
                            TextField(text: $newFolder, prompt: Text(.notesKit("New folder"))) { EmptyView() }.textFieldStyle(.plain)
                            Button(.notesKit("Done")) {
                                let value = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !value.isEmpty else { return }
                                haptic(); onFolder(value); newFolder = ""
                            }
                        }.noteCard(theme: theme, padding: theme.small + 4)
                    }
                }
                section(.notesKit("Security")) {
                    Button { haptic(); onToggleLock() } label: {
                        HStack {
                            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                            VStack(alignment: .leading) {
                                Text(.notesKit("Lock this note")).font(theme.rowFont)
                                Text(.notesKit("Even inside an unlocked vault, this note asks to unlock again before it opens."))
                                    .font(theme.captionFont).foregroundStyle(theme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: isLocked ? "checkmark.circle.fill" : "circle")
                        }.foregroundStyle(theme.primaryText).noteCard(theme: theme, padding: theme.small + 4)
                    }.buttonStyle(.plain)
                }
            }.padding(theme.medium)
        }
        .background(theme.sheet)
        .safeAreaInset(edge: .top) {
            HStack {
                Text(.notesKit("Note options")).font(theme.sectionFont).textCase(.uppercase)
                Spacer()
                Button(.notesKit("Done"), action: onDismiss).foregroundStyle(theme.accent)
            }.padding(theme.medium).background(theme.sheet)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.sheet)
    }

    private func section<C: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: theme.small) {
            Text(title).font(theme.sectionFont).textCase(.uppercase).foregroundStyle(theme.secondaryText)
            content()
        }
    }

    private func iconButton(_ value: String?, label: String) -> some View {
        Button { haptic(); onIcon(value) } label: {
            Text(verbatim: label).frame(maxWidth: .infinity).frame(height: 44)
                .background(icon == value ? theme.accent : theme.card, in: RoundedRectangle(cornerRadius: theme.smallRadius))
        }.buttonStyle(.plain)
    }

    private func folderButton(_ value: String?, label: Text) -> some View {
        Button { haptic(); onFolder(value) } label: {
            label.font(theme.modeFont).textCase(.uppercase).padding(.horizontal, theme.medium).frame(height: 34)
                .foregroundStyle(folder == value ? theme.onAccent : theme.secondaryText)
                .background(folder == value ? theme.accent : theme.card, in: Capsule())
        }.buttonStyle(.plain)
    }
}
