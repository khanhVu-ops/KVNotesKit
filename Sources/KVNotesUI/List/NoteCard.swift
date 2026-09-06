import KVNotesCore
import KVNotesTesting
import SwiftUI

/// One note, drawn as a row or as a card — the *same* view either way.
///
/// Two views would be simpler to read and would make the layout switch a cut. Rows and cards
/// hold the same five things (glyph, title, preview, metadata, and a way to reach the actions);
/// the only difference is whether the glyph sits beside that text or above it. `AnyLayout` says
/// exactly that, and says it without replacing anything: the children keep their identity across
/// the switch, so SwiftUI animates each one from where it was to where it is going. That is what
/// makes a row visibly *become* a card instead of dissolving into one.
///
/// Everything that used to differ between the two now does so by degree, not by kind — one line
/// of title or two, one line of preview or three — because a property that changes can animate
/// and a view that is swapped cannot.
///
/// **No swipe.** The row lost `.swipeActions` when both layouts moved into one `LazyVGrid`, and
/// a hand-rolled `DragGesture` would lose the full-swipe, the rubber band, the haptics and the
/// VoiceOver actions a `List` gives for free. Pin and Trash live on the visible button in the
/// corner and on the long press, in both layouts. An affordance moved somewhere a person can see
/// is a trade; one that quietly disappears is a regression.
struct NoteCard: View {
    let note: NoteDigest
    let theme: NoteTheme
    let layout: NoteListLayout
    var isSelecting = false
    var isSelected = false
    let haptic: @MainActor @Sendable () -> Void
    let onOpen: () -> Void
    /// The card asks for the options; what they are is the screen's business.
    let onOptions: @MainActor @Sendable () -> Void

    private var isGrid: Bool { layout == .grid }

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
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Text(.notesKit("Note options")))
            }
        }
    }

    /// The one place the two layouts differ, and it is a layout and not a branch.
    ///
    /// `AnyLayout` swaps the *arrangement* while `glyph` and `text` stay the same two views. A
    /// `if isGrid { VStack … } else { HStack … }` would build two different subtrees, SwiftUI
    /// would treat the children as new, and the switch would be a cross-fade of two cards rather
    /// than one card changing shape.
    private var arrangement: AnyLayout {
        isGrid
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: theme.small))
            : AnyLayout(HStackLayout(alignment: .top, spacing: theme.small + 4))
    }

    private var card: some View {
        arrangement {
            glyph
            text
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Only the grid stretches: a card fills the height its taller neighbour set, while a row
        // is as tall as its own contents and nothing else.
        .frame(maxHeight: isGrid ? .infinity : nil, alignment: .topLeading)
        .noteCard(theme: theme, padding: theme.small + 4)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous)
                    .strokeBorder(theme.accent, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: isGrid ? 4 : 3) {
            title
                .font(theme.rowFont)
                .foregroundStyle(theme.primaryText)
                .lineLimit(isGrid ? 2 : 1)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
                // A row's title starts on the same line as the corner button and would run
                // underneath it. A card's starts below the glyph, clear of it already.
                .padding(.trailing, isGrid ? 0 : 34)
            preview
            // Always present, so `metadata` keeps its place in the stack and travels rather than
            // being torn out and put back — a view that leaves one parent for another pops, and
            // that is the one seam a morph cannot hide.
            Spacer(minLength: 0)
            metadata.padding(.top, isGrid ? 0 : 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A card fills the height its taller neighbour set and lets the spacer push the metadata
        // to the bottom. A row has no such height to fill: without this the spacer stretches the
        // text to match the 44pt glyph beside it and leaves a gap under every one-line note.
        .fixedSize(horizontal: false, vertical: !isGrid)
    }

    private var title: Text {
        guard !note.title.isEmpty else {
            return note.requiresBiometricUnlock
                ? Text(.notesKit("Locked note"))
                : Text(.notesKit("Untitled note"))
        }
        return Text(verbatim: note.title)
    }

    /// Three lines as a card, one as a row — the reason to be in the grid at all.
    ///
    /// Reads `visiblePreview`, never `snippet`: a note the host withheld and a note the user hid
    /// are the same answer here, and asking two questions is how one of them gets forgotten.
    @ViewBuilder private var preview: some View {
        let lines = isGrid ? 3 : 1
        if note.visiblePreview == nil {
            // The redaction bars stand in for the lines that are not being shown, so there are
            // as many of them as there would have been lines.
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(Self.barWidths.prefix(lines).enumerated()), id: \.offset) { _, fraction in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.primaryText)
                        .frame(height: 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: fraction, y: 1, anchor: .leading)
                }
            }
            .opacity(0.14)
            .accessibilityHidden(true)
        } else if let snippet = note.visiblePreview, !snippet.isEmpty {
            Text(verbatim: snippet)
                .font(isGrid ? theme.captionFont : theme.monoFont)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(lines)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
        }
    }

    private static let barWidths: [CGFloat] = [1.0, 0.82, 0.45]

    private var glyph: some View {
        ZStack {
            theme.elevatedCard
            if let parsed = NoteIcon.parse(note.icon) {
                switch parsed {
                case .emoji(let emoji):
                    Text(verbatim: emoji).font(.system(size: 19))
                case .symbol(let symbolName):
                    Image(systemName: symbolName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                }
            } else if let initial = note.title.first {
                Text(verbatim: String(initial).uppercased())
                    .font(theme.rowFont)
                    .foregroundStyle(theme.primaryText)
            } else {
                Image(systemName: "note.text")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))
    }

    /// One metadata line for both layouts.
    ///
    /// The card used to carry the lock, the hidden-preview eye and the pin up beside its glyph
    /// while the row carried them down here. Two homes for one set of badges is two places to
    /// look, and — the reason it changed — a view that moves between two parents is a view that
    /// pops rather than travels, which is the one seam a morph cannot hide.
    private var metadata: some View {
        HStack(spacing: isGrid ? 5 : theme.small) {
            editedAt
            if let folder = note.folder {
                dot
                Text(verbatim: folder).foregroundStyle(theme.secondaryText)
            }
            if note.requiresBiometricUnlock {
                dot
                Image(systemName: "lock.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .accessibilityLabel(Text(.notesKit("Locked")))
            }
            // Only where the lock is not already saying it. Two badges for one hidden preview
            // reads as two different protections.
            if note.hidesPreview, !note.requiresBiometricUnlock {
                dot
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityLabel(Text(.notesKit("Preview hidden")))
            }
            if note.isPinned {
                dot
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(theme.accent)
                    .accessibilityLabel(Text(.notesKit("Pinned")))
            }
        }
        .font(theme.metadataFont)
        .tracking(1)
        .textCase(.uppercase)
        .foregroundStyle(theme.disabledText)
        .lineLimit(1)
        // A card is half the width of a row and carries the same line, so it is allowed to shrink
        // further before it starts dropping words.
        .minimumScaleFactor(isGrid ? 0.75 : 0.85)
    }

    private var marker: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(isSelected ? theme.accent : theme.disabledText)
            .background(Circle().fill(theme.card).padding(2))
            .contentTransition(.symbolEffect(.replace))
    }

    private var dot: some View { Circle().fill(theme.disabledText).frame(width: 2.5, height: 2.5) }

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

#Preview("Rows and cards") {
    @Previewable @State var layout: NoteListLayout = .list
    let theme = NoteTheme.preview

    return VStack(spacing: 0) {
        Button(layout == .grid ? "Rows" : "Cards") {
            withAnimation(NoteMotion.layout(reduceMotion: false)) {
                layout = layout == .grid ? .list : .grid
            }
        }
        .padding()

        ScrollView {
            LazyVGrid(
                columns: layout == .grid
                    ? [GridItem(.flexible(), spacing: theme.small, alignment: .top),
                       GridItem(.flexible(), spacing: theme.small, alignment: .top)]
                    : [GridItem(.flexible(), spacing: theme.small, alignment: .top)],
                spacing: theme.small
            ) {
                // A locked note, a plain one and a long title: the three shapes a card has to
                // hold without any of them setting the height of the row.
                ForEach(NoteFixtures.all) { note in
                    NoteCard(
                        note: note,
                        theme: theme,
                        layout: layout,
                        haptic: {},
                        onOpen: {},
                        onOptions: {}
                    )
                    .frame(minHeight: layout == .grid ? 158 : nil)
                }
            }
            .padding(theme.medium)
        }
    }
    .background(theme.background)
}
