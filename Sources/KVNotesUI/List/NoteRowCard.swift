import KVNotesCore
import SwiftUI

struct NoteRowCard: View {
    let note: NoteDigest
    let theme: NoteTheme
    let haptic: @MainActor @Sendable () -> Void
    let onOpen: () -> Void

    var body: some View {
        Button {
            haptic()
            onOpen()
        } label: {
            HStack(alignment: .top, spacing: theme.small + 4) {
                glyph
                VStack(alignment: .leading, spacing: 3) {
                    title.font(theme.rowFont).foregroundStyle(theme.primaryText).lineLimit(1)
                    preview
                    metadata.padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .noteCard(theme: theme, padding: theme.small + 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var title: Text {
        guard !note.title.isEmpty else {
            return note.requiresBiometricUnlock ? Text("Locked note") : Text("Untitled note")
        }
        return Text(verbatim: note.title)
    }

    @ViewBuilder private var preview: some View {
        if note.requiresBiometricUnlock || note.snippet == nil {
            HStack(spacing: 4) {
                ForEach([38.0, 22.0, 54.0, 30.0], id: \.self) { width in
                    RoundedRectangle(cornerRadius: 2).fill(theme.primaryText).frame(width: width, height: 7)
                }
            }
            .opacity(0.14).frame(height: 15).accessibilityHidden(true)
        } else if let snippet = note.snippet, !snippet.isEmpty {
            Text(verbatim: snippet)
                .font(theme.monoFont).foregroundStyle(theme.secondaryText).lineLimit(1)
        }
    }

    private var glyph: some View {
        ZStack {
            theme.elevatedCard
            if let icon = note.icon, !icon.isEmpty {
                Text(verbatim: icon).font(.system(size: 19))
            } else if let initial = note.title.first {
                Text(verbatim: String(initial).uppercased()).font(theme.rowFont).foregroundStyle(theme.primaryText)
            } else {
                Image(systemName: "note.text").font(.system(size: 16)).foregroundStyle(theme.secondaryText)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))
    }

    private var metadata: some View {
        HStack(spacing: theme.small) {
            editedAt
            if let folder = note.folder { dot; Text(verbatim: folder).foregroundStyle(theme.secondaryText) }
            if note.requiresBiometricUnlock { dot; Image(systemName: "lock.fill") }
            if note.isFavorite { dot; Image(systemName: "heart.fill").foregroundStyle(theme.error) }
        }
        .font(theme.metadataFont).textCase(.uppercase).foregroundStyle(theme.disabledText).lineLimit(1)
    }

    private var dot: some View { Circle().fill(theme.disabledText).frame(width: 2.5, height: 2.5) }

    @ViewBuilder private var editedAt: some View {
        let elapsed = Date().timeIntervalSince(note.lastEditedAt)
        if elapsed < 60 { Text("Just now") }
        else if elapsed < 7 * 86_400 { Text(note.lastEditedAt, format: .relative(presentation: .named)) }
        else { Text(note.lastEditedAt, format: .dateTime.day().month(.abbreviated)) }
    }
}
