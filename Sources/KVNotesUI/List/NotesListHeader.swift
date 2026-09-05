import KVNotesCore
import SwiftUI

/// The notes list's chrome, as items in the host's own navigation bar.
///
/// It used to be a `safeAreaInset` drawn by hand, above a hidden navigation bar. That is why the
/// back swipe on this screen was never the system one: UIKit refuses `interactivePopGestureRecognizer`
/// while the bar is hidden — not by disabling it, which KVRouterKit already forces back on, but
/// through the delegate it installs on it, which `isEnabled` cannot overrule. The workaround was to
/// push the screen on a router transition so it brought its own edge recogniser, and that recogniser
/// is a plain pan: anything under the finger that pans beats it, which cost the swipe over the
/// folder chips.
///
/// Showing the bar and putting the controls in it is the fix, and it is the smaller thing to
/// maintain. UIKit owns the push, the back button and the swipe; nothing here is a re-implementation
/// of navigation.
///
/// `ToolbarContent` rather than a `View`, because that is what `.toolbar` takes — but the rule is
/// unchanged: values and closures, never the ViewModel.
struct NotesListToolbar: ToolbarContent {
    /// Read only by `NotesInlineTitle`, so a scroll redraws a label and not this whole bar.
    let collapse: NotesHeaderCollapse
    let theme: NoteTheme
    let isSelecting: Bool
    let isEverythingSelected: Bool
    let selectionCount: Int
    let hasVisibleNotes: Bool
    let isNarrowed: Bool
    let layout: NoteListLayout
    let haptic: @MainActor @Sendable () -> Void
    let onCreateNote: @MainActor @Sendable () -> Void
    let onStartSelecting: @MainActor @Sendable () -> Void
    let onStopSelecting: @MainActor @Sendable () -> Void
    let onSelectAllOrNone: @MainActor @Sendable () -> Void
    let onOpenSortAndFilter: @MainActor @Sendable () -> Void
    let onToggleLayout: @MainActor @Sendable () -> Void

    /// `topBar*` is iOS-only and this package also builds for macOS, where the same two corners
    /// are named by role rather than by edge.
    #if os(iOS)
    private static let leading: ToolbarItemPlacement = .topBarLeading
    private static let trailing: ToolbarItemPlacement = .topBarTrailing
    #else
    private static let leading: ToolbarItemPlacement = .cancellationAction
    private static let trailing: ToolbarItemPlacement = .primaryAction
    #endif

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if isSelecting {
            // Cancel stands where Back would, and the screen hides the system back button while a
            // selection is live: leaving both would offer two different ways out of two different
            // things. The back swipe goes with it, which is the right trade — a swipe that threw
            // away a half-built selection is not a shortcut anyone wants.
            ToolbarItem(placement: Self.leading) {
                Button(action: onStopSelecting) {
                    Text(.notesKit("Cancel"))
                        .font(theme.modeFont)
                        .textCase(.uppercase)
                        .tracking(1.0)
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(NotePressButtonStyle())
                .fixedSize()
                .layoutPriority(1)
            }

            ToolbarItem(placement: .principal) {
                Text(.notesKit(count: "\(selectionCount) selected"))
                    .font(theme.metadataFont)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(theme.secondaryText)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            ToolbarItem(placement: Self.trailing) {
                Button {
                    haptic()
                    onSelectAllOrNone()
                } label: {
                    Text(isEverythingSelected
                        ? .notesKit("Deselect All")
                        : .notesKit("Select All"))
                        .font(theme.modeFont)
                        .textCase(.uppercase)
                        .tracking(1.0)
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(NotePressButtonStyle())
                .fixedSize()
            }
        } else {
            ToolbarItem(placement: .principal) {
                NotesInlineTitle(collapse: collapse, theme: theme)
            }

            ToolbarItemGroup(placement: Self.trailing) {
                sortButton
                layoutToggle
                selectButton
                createButton
            }
        }
    }

    /// Sort and filter behind one control rather than two.
    ///
    /// They answer the same question — "show me a different slice of this list" — and the bar has
    /// room for one more circle, not two. The fill marks a list that is narrowed, because a filter
    /// left on looks exactly like a vault that lost its notes.
    private var sortButton: some View {
        Button {
            haptic()
            onOpenSortAndFilter()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isNarrowed ? theme.onAccent : theme.primaryText)
                .frame(width: 32, height: 32)
                .background(isNarrowed ? theme.accent : theme.card, in: Circle())
                .overlay {
                    Circle().strokeBorder(
                        isNarrowed ? .clear : theme.separator,
                        lineWidth: 0.75
                    )
                }
        }
        .buttonStyle(NotePressButtonStyle())
        .accessibilityLabel(Text(.notesKit("Sort and filter")))
    }

    /// Rows or cards, one tap either way.
    ///
    /// The icon names the layout the tap will *produce*, not the one on screen — the same grammar
    /// as the Photos grid density control, and the reason it needs no label beside it.
    private var layoutToggle: some View {
        let isGrid = layout == .grid
        return Button {
            haptic()
            onToggleLayout()
        } label: {
            Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .frame(width: 32, height: 32)
                .background(theme.card, in: Circle())
                .overlay { Circle().strokeBorder(theme.separator, lineWidth: 0.75) }
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(NotePressButtonStyle())
        .accessibilityLabel(Text(isGrid ? .notesKit("List view") : .notesKit("Grid view")))
    }

    private var selectButton: some View {
        Button {
            haptic()
            onStartSelecting()
        } label: {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .frame(width: 32, height: 32)
                .background(theme.card, in: Circle())
                .overlay { Circle().strokeBorder(theme.separator, lineWidth: 0.75) }
        }
        .buttonStyle(NotePressButtonStyle())
        .disabled(!hasVisibleNotes)
        .accessibilityLabel(Text(.notesKit("Select notes")))
    }

    private var createButton: some View {
        Button(action: onCreateNote) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.onAccent)
                .frame(width: 32, height: 32)
                .background(theme.accent, in: Circle())
        }
        .buttonStyle(NotePressButtonStyle())
        .accessibilityLabel(Text(.notesKit("New note")))
    }
}

/// The title in the navigation bar: absent at rest, arriving as the large one scrolls away.
///
/// Its own view so that the scroll redraws this label and nothing else. Reading `progress` from
/// the screen would put a per-frame write back into the body that builds the whole list.
///
/// Not `.navigationTitle`, which would show the words permanently and repeat the large title six
/// points below itself.
struct NotesInlineTitle: View {
    let collapse: NotesHeaderCollapse
    let theme: NoteTheme

    /// Arrives after the large title has finished leaving — two titles legible at once reads as a
    /// double image. Vault Home's ramp.
    private var opacity: Double {
        let p = min(max(collapse.progress, 0), 1)
        return min(max((p - 0.55) * 2.3, 0), 1)
    }

    var body: some View {
        Text(.notesKit("Private notes"))
            .font(theme.sectionFont)
            .foregroundStyle(theme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .opacity(opacity)
            // Hidden from VoiceOver until it is actually legible: two headers reading the same
            // words is one too many.
            .accessibilityHidden(opacity < 0.5)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The search field and the folder chips, pinned under the control row while the list moves.
///
/// A `Section` header inside the scroll view rather than part of the `safeAreaInset`, and the
/// reason is the order things are drawn in. A `safeAreaInset` is always above the content, so
/// anything pinned that way sits above the title — and the title has to be *below* the control
/// row and *above* the search, which is the order the design has always had. Pinning it from
/// inside the scroll is what lets the title scroll away past it while it stays put.
///
/// It could have gone in the header and folded away with the title. It should not: the search
/// field and the chips are how the list is narrowed, and a control that leaves the moment you
/// scroll is a control you have to scroll back for. Vault Home pins its category rail for the
/// same reason.
struct NotesListFilterBar: View {
    let theme: NoteTheme
    @Binding var searchText: String
    let noteCount: Int
    let folderChips: [NotesListState.FolderChip]
    let folderTints: [String: NoteFolderTint]
    let selectedFolder: String?
    /// Only the hairline reads this, and only to fade with.
    let progress: Double
    let haptic: @MainActor @Sendable () -> Void
    let onSelectFolder: @MainActor @Sendable (String?) -> Void
    let onOpenFolderManager: @MainActor @Sendable () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Shape: Equatable {
        let selectedFolder: String?
        let hasSearchText: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if !folderChips.isEmpty { folderRow }

            // Invisible at rest and drawn once there is content behind it — a separator over
            // nothing is a line for its own sake.
            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.75)
                .opacity(min(max(progress, 0), 1))
                .padding(.top, theme.xs)
        }
        // Opaque, and not optional: cards scroll underneath this, and a translucent bar over
        // moving text reads as a rendering fault rather than as a design.
        .background(theme.background)
        .animation(
            NoteMotion.header(reduceMotion: reduceMotion),
            value: Shape(selectedFolder: selectedFolder, hasSearchText: !searchText.isEmpty)
        )
    }

    private var searchField: some View {
        HStack(spacing: theme.small) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            TextField(
                text: $searchText,
                prompt: Text(.notesKit("Search notes")).foregroundStyle(theme.disabledText)
            ) { Text(.notesKit("Search")) }
                .textFieldStyle(.plain)
                .font(theme.monoFont)
                .foregroundStyle(theme.primaryText)
                .autocorrectionDisabled()
                .noteNeverAutocapitalizes()
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.disabledText)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Text(.notesKit("Cancel")))
            }
        }
        .padding(.horizontal, theme.small + 4)
        .frame(height: 36)
        .background(theme.card, in: Capsule())
        .overlay { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
        .padding(.horizontal, theme.medium)
        .padding(.bottom, theme.small)
    }

    private var folderRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: theme.xs + 2) {
                chip(
                    title: Text(.notesKit("All")),
                    count: noteCount,
                    isSelected: selectedFolder == nil
                ) { onSelectFolder(nil) }
                ForEach(folderChips) { folder in
                    chip(
                        title: Text(verbatim: folder.name),
                        count: folder.count,
                        isSelected: selectedFolder == folder.name,
                        tint: folderTints[folder.name] ?? .neutral
                    ) { onSelectFolder(folder.name) }
                }

                // Managing folders belongs where the folders are, not in a header that already
                // carries four controls and a title — on a small phone that row runs out of
                // width before the title does.
                Button {
                    haptic()
                    onOpenFolderManager()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, theme.small + 2)
                        .frame(height: 31)
                        .overlay { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
                        .contentShape(Capsule())
                }
                .buttonStyle(NotePressButtonStyle())
                .frame(minHeight: 44)
                .accessibilityLabel(Text(.notesKit("Folders")))
            }
            .padding(.horizontal, theme.medium)
            .padding(.bottom, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(
        title: Text,
        count: Int,
        isSelected: Bool,
        tint: NoteFolderTint = .neutral,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            haptic()
            action()
        } label: {
            HStack(spacing: 5) {
                if tint != .neutral, !isSelected {
                    Circle().fill(theme.color(for: tint)).frame(width: 6, height: 6)
                }
                title.textCase(.uppercase).tracking(1.3)
                Text(count, format: .number)
                    .foregroundStyle(isSelected ? theme.onAccent.opacity(0.6) : theme.disabledText)
            }
            .font(theme.modeFont)
            .foregroundStyle(isSelected ? theme.onAccent : theme.secondaryText)
            .padding(.horizontal, theme.small + 4)
            .frame(height: 31)
            .background {
                if isSelected { Capsule().fill(theme.accent) }
                else { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(NotePressButtonStyle())
        .frame(minHeight: 44)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Filter bar") {
    @Previewable @State var searchText = ""

    VStack(spacing: 0) {
        NotesListFilterBar(
            theme: .preview,
            searchText: $searchText,
            noteCount: 12,
            folderChips: [
                NotesListState.FolderChip(name: "Work", count: 4),
                NotesListState.FolderChip(name: "Travel", count: 2)
            ],
            folderTints: ["Work": .teal],
            selectedFolder: nil,
            progress: 1,
            haptic: {},
            onSelectFolder: { _ in },
            onOpenFolderManager: {}
        )
        Spacer()
    }
    .background(NoteTheme.preview.background)
}

/// The screen's name and its count line — scrolling content, not header.
///
/// This is the whole fix for a header that flickered on a slow scroll and locked up a device.
///
/// The header is a `safeAreaInset`, so its height *is* the scroll view's top content inset. A
/// header that changes height in response to the scroll offset is therefore a closed loop through
/// UIKit: fold a little, the inset shrinks, the scroll view reports new geometry, that geometry
/// changes the fold. Whether the loop settles or runs away is a question about gain and about how
/// consistently the two terms arrive in the same frame — and the honest answer is that it is not
/// worth betting a screen on either. Damped it reads as flicker under a slow finger, which is
/// exactly what it felt like; undamped it never reaches a fixed point and the frame never
/// finishes, which is a screen that opens and hangs.
///
/// So nothing about the pinned header's height depends on scrolling any more. The part that
/// leaves is ordinary content at the top of the list, and it leaves by being scrolled, at exactly
/// the speed of the finger, because that is what scrolling is. Progress still exists, but it only
/// drives opacity now — the inline title in the row, the hairline — and opacity cannot change a
/// layout, so it cannot come back round.
///
/// Vault Home has the loop this removes. Its chrome shrinks 32pt against a 56pt travel distance,
/// a gain of 0.57, so it converges instead of hanging — and runs at 1.75x the rate its own
/// constant claims. It should be moved to this shape too.
struct NotesListTitleBlock: View {
    let theme: NoteTheme
    let noteCount: Int
    /// Only to fade with. It must never reach anything that decides a size.
    let progress: Double

    private var p: Double { min(max(progress, 0), 1) }

    /// Gone by 60%, so the words have finished leaving before the row that takes their place
    /// starts arriving. Two titles legible at once reads as a double image.
    private var opacity: Double { p >= 0.6 ? 0 : 1 - p / 0.6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The screen's name, on its own line and at title size. It used to sit between the
            // back button and three controls, which capped it at a caption and left the row
            // looking like a toolbar with a label wedged into it.
            Text(.notesKit("Private notes"))
                .font(theme.titleFont)
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, theme.xs)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)

            countLine
        }
        .padding(.horizontal, theme.medium)
        .padding(.bottom, theme.small)
        .opacity(opacity)
    }

    private var countLine: some View {
        HStack(spacing: theme.small) {
            Text(.notesKit(count: "\(noteCount) notes"))
                .textCase(.uppercase)
                .contentTransition(.numericText())
            Rectangle().fill(theme.secondaryText).frame(width: 16, height: 0.75)
            HStack(spacing: 4) {
                Image(systemName: "lock").font(.system(size: 10, weight: .semibold))
                Text(verbatim: "AES-256")
            }
        }
        .font(theme.metadataFont)
        .tracking(1.4)
        .foregroundStyle(theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Title block") {
    VStack(spacing: 0) {
        NotesListTitleBlock(theme: .preview, noteCount: 12, progress: 0)
        NotesListTitleBlock(theme: .preview, noteCount: 12, progress: 0.35)
        Spacer()
    }
    .background(NoteTheme.preview.background)
}

