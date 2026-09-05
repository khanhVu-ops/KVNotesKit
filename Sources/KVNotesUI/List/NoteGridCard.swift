import KVNotesCore
import KVNotesTesting
import SwiftUI

/// One note as a card in the two-column grid.
///
/// The row's affordances do not survive the move to a grid: `LazyVGrid` has no `.swipeActions`,
/// and a hand-rolled `DragGesture` would lose the full-swipe, the rubber band, the haptics and the
/// VoiceOver actions the system gives a `List` row for free. So the card does not pretend to swipe.
/// It carries the same actions behind a button that is *visible* — the one in the corner — as well
/// as on the long press, and multi-select still does the rest. An affordance moved somewhere a
/// person can see is a trade; one that quietly disappears is a regression.
struct NoteGridCard: View {
    let note: NoteDigest
    let theme: NoteTheme
    var isSelecting = false
    var isSelected = false
    let haptic: @MainActor @Sendable () -> Void
    let onOpen: () -> Void
    /// The card asks for the options; what they are is the screen's business.
    let onOptions: @MainActor @Sendable () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                haptic()
                onOpen()
            } label: {
                card
            }
            .buttonStyle(NotePressButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelecting ? [.isButton, .isSelected] : [.isButton])
            .accessibilityRemoveTraits(isSelecting && !isSelected ? [.isSelected] : [])

            // Outside the button rather than inside its label: a control nested in a `Button`'s
            // label never receives the tap, it just makes the whole card look pressable twice.
            if isSelecting {
                marker
                    .padding(theme.small + 2)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    haptic()
                    onOptions()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(theme.elevatedCard, in: Circle())
                }
                .buttonStyle(NotePressButtonStyle())
                .padding(theme.small)
                .accessibilityLabel(Text(.notesKit("Note options")))
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: theme.small) {
            glyph
            VStack(alignment: .leading, spacing: 4) {
                title
                    .font(theme.rowFont)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                preview
            }
            Spacer(minLength: theme.xs)
            metadata
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .noteCard(theme: theme, padding: theme.small + 4)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous)
                    .strokeBorder(theme.accent, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
    }

    private var marker: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(isSelected ? theme.accent : theme.disabledText)
            .background(Circle().fill(theme.card).padding(2))
    }

    private var title: Text {
        guard !note.title.isEmpty else {
            return note.requiresBiometricUnlock
                ? Text(.notesKit("Locked note"))
                : Text(.notesKit("Untitled note"))
        }
        return Text(verbatim: note.title)
    }

    /// Three lines rather than the row's one — the reason to be in this layout at all.
    ///
    /// `visiblePreview`, never `snippet`: withheld by the host and hidden by the user are the
    /// same answer, and asking two questions is how one of them gets forgotten.
    @ViewBuilder private var preview: some View {
        if note.visiblePreview == nil {
            VStack(alignment: .leading, spacing: 5) {
                ForEach([1.0, 0.82, 0.45], id: \.self) { fraction in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.primaryText)
                        .frame(width: nil, height: 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: fraction, y: 1, anchor: .leading)
                }
            }
            .opacity(0.14)
            .accessibilityHidden(true)
        } else if let snippet = note.visiblePreview, !snippet.isEmpty {
            Text(verbatim: snippet)
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
        }
    }

    private var glyph: some View {
        HStack(spacing: theme.xs) {
            ZStack {
                theme.elevatedCard
                if let icon = note.icon, !icon.isEmpty {
                    Text(verbatim: icon).font(.system(size: 17))
                } else if let initial = note.title.first {
                    Text(verbatim: String(initial).uppercased())
                        .font(theme.rowFont)
                        .foregroundStyle(theme.primaryText)
                } else {
                    Image(systemName: "note.text")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))

            if note.requiresBiometricUnlock {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .accessibilityLabel(Text(.notesKit("Locked")))
            }
            if note.hidesPreview, !note.requiresBiometricUnlock {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityLabel(Text(.notesKit("Preview hidden")))
            }
            if note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.accent)
                    .accessibilityLabel(Text(.notesKit("Pinned")))
            }
        }
        // The corner opposite belongs to the menu button; without this the lock and the pin end
        // up underneath it on a narrow card.
        .padding(.trailing, 30)
    }

    private var metadata: some View {
        HStack(spacing: 5) {
            editedAt
            if let folder = note.folder {
                Circle().fill(theme.disabledText).frame(width: 2.5, height: 2.5)
                Text(verbatim: folder).foregroundStyle(theme.secondaryText).lineLimit(1)
            }
        }
        .font(theme.metadataFont)
        .tracking(1)
        .textCase(.uppercase)
        .foregroundStyle(theme.disabledText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    @ViewBuilder private var editedAt: some View {
        let elapsed = Date().timeIntervalSince(note.lastEditedAt)
        if elapsed < 60 { Text(.notesKit("Just now")) }
        else if elapsed < 7 * 86_400 { Text(note.lastEditedAt, format: .relative(presentation: .named)) }
        else if Calendar.current.isDate(note.lastEditedAt, equalTo: Date(), toGranularity: .year) {
            Text(note.lastEditedAt, format: .dateTime.day().month(.abbreviated))
        } else {
            Text(note.lastEditedAt, format: .dateTime.day().month(.abbreviated).year())
        }
    }
}

#Preview {
    let theme = NoteTheme.preview
    return ScrollView {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: theme.small), GridItem(.flexible(), spacing: theme.small)],
            spacing: theme.small
        ) {
            // A locked note, a plain one and a long title: the three shapes a card has to hold
            // without any of them setting the height of the row.
            ForEach(NoteFixtures.all) { note in
                NoteGridCard(note: note, theme: theme, haptic: {}, onOpen: {}, onOptions: {})
            }
        }
        .padding(theme.medium)
    }
    .background(theme.background)
}
