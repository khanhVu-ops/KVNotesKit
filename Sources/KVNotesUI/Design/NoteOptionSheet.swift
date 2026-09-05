import SwiftUI

/// One choice in an option sheet.
struct NoteOptionItem: Identifiable {
    let id: String
    let title: NoteOptionTitle
    let systemImage: String
    /// Drawn as a tick rather than as a highlight: half of these lists are a single choice out of
    /// several, and a highlighted row reads as "pressed" on a surface where everything is tappable.
    var isSelected = false
    var isDestructive = false
    let action: @MainActor () -> Void
}

/// A title that is either the app's own copy or something the user typed.
///
/// Folder names come from the vault and must never go through the translation table; everything
/// else must. Making that a type rather than a convention means the wrong one does not compile.
enum NoteOptionTitle {
    case localized(LocalizedStringResource)
    case verbatim(String)

    var text: Text {
        switch self {
        case .localized(let resource): Text(resource)
        case .verbatim(let value): Text(verbatim: value)
        }
    }
}

struct NoteOptionGroup: Identifiable {
    let id: String
    var heading: LocalizedStringResource?
    var items: [NoteOptionItem]
}

/// Every "what do you want to do with this" list in the flow, as one sheet.
///
/// It replaces the `Menu`s these actions used to live on. Three reasons, in the order they
/// mattered: a menu is drawn by UIKit in system type and system colours in the middle of a screen
/// that is neither; it gives a folder name the same 17pt row as "Move to Trash" with no room to
/// group or explain them; and opening one on this screen raised the software keyboard with nothing
/// focused and no caret anywhere — reproducible on the sort menu, a card's menu and the folder
/// manager's, and gone with the last menu. What exactly took first responder was never pinned
/// down; a sheet is this flow's own surface, lands in the same place every time, and does not do
/// it.
struct NoteOptionSheetView: View {
    let title: LocalizedStringResource
    let subtitle: NoteOptionTitle?
    let groups: [NoteOptionGroup]
    /// True for a list of actions — pick one and the sheet has done its job. False for a list of
    /// settings like sort and filter, where closing after the first tap means opening it twice to
    /// answer two questions.
    var dismissesOnSelection = true
    let theme: NoteTheme
    var haptic: @MainActor @Sendable () -> Void = {}
    let onDismiss: @MainActor @Sendable () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: theme.medium) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: theme.xs + 2) {
                            if let heading = group.heading {
                                Text(heading)
                                    .font(theme.metadataFont)
                                    .textCase(.uppercase)
                                    .tracking(1.4)
                                    .foregroundStyle(theme.secondaryText)
                                    .padding(.horizontal, theme.xs)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            card(for: group)
                        }
                    }
                }
                .padding(.horizontal, theme.medium)
                .padding(.bottom, theme.small)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .background(theme.sheet)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(theme.titleFont)
                .foregroundStyle(theme.primaryText)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                subtitle.text
                    .font(theme.metadataFont)
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.medium)
        // No grabber above this, so the title carries the top margin itself.
        .padding(.top, theme.large)
        .padding(.bottom, theme.medium)
    }

    /// One card per group, with hairlines between the rows rather than a gap.
    ///
    /// Separate cards would read as several unrelated lists; one card with rules inside reads as
    /// one list with sections, which is what it is.
    private func card(for group: NoteOptionGroup) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(theme.separator)
                        .frame(height: 0.75)
                        .padding(.leading, 32 + theme.small + 4)
                }
                row(item)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .fill(theme.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 0.75)
        }
    }

    private func row(_ item: NoteOptionItem) -> some View {
        let tone = item.isDestructive ? theme.error : theme.primaryText
        return Button {
            haptic()
            item.action()
            if dismissesOnSelection { onDismiss() }
        } label: {
            HStack(spacing: theme.small + 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: theme.smallRadius - 2, style: .continuous)
                        .fill(tone.opacity(item.isDestructive ? 0.12 : 0.08))
                    Image(systemName: item.systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tone)
                }
                .frame(width: 32, height: 32)

                item.title.text
                    .font(theme.rowFont)
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if item.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, theme.small + 4)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotePressButtonStyle())
        .accessibilityAddTraits(item.isSelected ? [.isSelected] : [])
    }

    private var footer: some View {
        Button(action: onDismiss) {
            Text(dismissesOnSelection ? .notesKit("Cancel") : .notesKit("Done"))
                .font(theme.modeFont)
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(dismissesOnSelection ? theme.primaryText : theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background {
                    if dismissesOnSelection {
                        Capsule().fill(theme.card)
                            .overlay { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
                    } else {
                        Capsule().fill(theme.accent)
                    }
                }
        }
        .buttonStyle(NotePressButtonStyle())
        .padding(.horizontal, theme.medium)
        .padding(.top, theme.small)
        .padding(.bottom, theme.medium)
    }

    /// What to ask for as the sheet's detent.
    ///
    /// An estimate, and it has to be: the real height depends on the type size the reader chose,
    /// and a sheet cannot measure its own content before it is presented. The rows scroll, so
    /// being short is survivable and being too tall is not — a half-empty sheet over the list is
    /// the thing people notice.
    var estimatedHeight: CGFloat {
        let rows = groups.reduce(0) { $0 + $1.items.count }
        let headings = groups.count { $0.heading != nil }
        let content = CGFloat(rows) * 54
            + CGFloat(headings) * 26
            + CGFloat(max(groups.count - 1, 0)) * theme.medium
        let chrome = theme.large + 52 + theme.medium + theme.small + 50 + theme.medium
        return min(chrome + content, 640)
    }
}

extension View {
    /// Presents an option sheet over this view.
    func noteOptionSheet(
        isPresented: Binding<Bool>,
        sheet: NoteOptionSheetView
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            sheet
                .presentationDetents([.height(sheet.estimatedHeight)])
                .presentationDragIndicator(.hidden)
        }
    }

    /// Presents an option sheet *inside* the current sheet rather than on top of it.
    ///
    /// Same reason as `noteConfirmOverlay`: a sheet presented from a sheet replaces what is under
    /// it, so cancelling would leave the user somewhere they never asked to be.
    func noteOptionOverlay(
        isPresented: Binding<Bool>,
        theme: NoteTheme,
        reduceMotion: Bool,
        sheet: NoteOptionSheetView
    ) -> some View {
        overlay {
            // The `if` inside the stack, not around it: a wrapped stack is one inserted view, and
            // SwiftUI then runs the container's default transition instead of the ones written on
            // the scrim and the card.
            ZStack(alignment: .bottom) {
                if isPresented.wrappedValue {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture(perform: sheet.onDismiss)
                        .transition(.opacity)

                    sheet
                        .frame(maxHeight: sheet.estimatedHeight)
                        .clipShape(RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                        .padding(theme.small)
                        .transition(
                            .move(edge: .bottom)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.96, anchor: .bottom))
                        )
                }
            }
        }
        .animation(NoteMotion.mode(reduceMotion: reduceMotion), value: isPresented.wrappedValue)
    }
}

#Preview {
    NoteOptionSheetView(
        title: .notesKit("Note options"),
        subtitle: .verbatim("Bank details"),
        groups: [
            NoteOptionGroup(id: "actions", items: [
                NoteOptionItem(id: "pin", title: .localized(.notesKit("Pin")), systemImage: "pin") {},
                NoteOptionItem(
                    id: "trash",
                    title: .localized(.notesKit("Move to Trash")),
                    systemImage: "trash",
                    isDestructive: true
                ) {}
            ]),
            NoteOptionGroup(id: "folders", heading: .notesKit("Move to folder"), items: [
                NoteOptionItem(id: "none", title: .localized(.notesKit("No folder")), systemImage: "tray") {},
                NoteOptionItem(
                    id: "banking",
                    title: .verbatim("Banking"),
                    systemImage: "folder",
                    isSelected: true
                ) {}
            ])
        ],
        theme: .preview,
        onDismiss: {}
    )
}
