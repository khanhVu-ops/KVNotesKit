import KVNotesCore
import SwiftUI

struct NoteMarkdownView: View {
    let markdown: String
    let theme: NoteTheme
    let copy: @MainActor @Sendable (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.small + 4) {
                ForEach(Array(NoteMarkdownBlock.blocks(of: markdown).enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(theme.medium)
        }
    }

    @ViewBuilder private func blockView(_ block: NoteMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(verbatim: text).font(level == 1 ? theme.titleFont : theme.sectionFont).foregroundStyle(theme.primaryText)
        case .paragraph(let text):
            Text(verbatim: text).font(theme.bodyFont).foregroundStyle(theme.primaryText)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline) { Text(verbatim: "•"); Text(verbatim: text) }
                .font(theme.bodyFont).foregroundStyle(theme.primaryText)
        case .code(let value):
            Button { copy(value) } label: {
                HStack { Text(verbatim: value).font(theme.monoFont); Spacer(); Image(systemName: "doc.on.doc") }
                    .foregroundStyle(theme.primaryText).noteCard(theme: theme, padding: theme.small + 4)
            }.buttonStyle(.plain)
        case .divider:
            Rectangle().fill(theme.separator).frame(height: 1)
        }
    }
}
