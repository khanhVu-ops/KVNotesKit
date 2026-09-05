import KVNotesCore
import SwiftUI

struct NoteMarkdownView: View {
    let markdown: String
    let theme: NoteTheme
    let clipboardLifetime: TimeInterval
    let copy: @MainActor @Sendable (String) -> Void
    /// `nil` while the note is read-only to this screen — a task cannot be ticked on a body that
    /// has not been decrypted, and the checkbox must not pretend otherwise.
    var toggleTask: (@MainActor @Sendable (Int) -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.xs) {
                ForEach(Array(NoteMarkdownBlock.blocks(of: markdown).enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.medium)
            .padding(.bottom, theme.extraLarge)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func blockView(_ block: NoteMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level == 1 ? theme.sectionFont : theme.modeFont)
                .textCase(.uppercase)
                .tracking(level == 1 ? 1.8 : 1.5)
                .foregroundStyle(level == 1 ? theme.primaryText : theme.secondaryText)
                .padding(.top, level == 1 ? theme.medium : theme.small + 4)
        case .paragraph(let text):
            Text(inline(text))
                .font(theme.bodyFont)
                .foregroundStyle(theme.primaryText)
                .textSelection(.enabled)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: theme.small) {
                Text(verbatim: "—")
                    .font(theme.metadataFont)
                    .foregroundStyle(theme.disabledText)
                Text(inline(text))
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.primaryText)
                    .textSelection(.enabled)
            }
        case .task(let task):
            TaskRow(task: task, theme: theme, isEnabled: toggleTask != nil) {
                toggleTask?(task.lineIndex)
            }
        case .code(let value):
            CopyableValueRow(
                value: value,
                clipboardLifetime: clipboardLifetime,
                theme: theme,
                onCopy: copy
            )
        case .divider:
            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.75)
                .padding(.vertical, theme.small)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

/// A checkbox that writes to the note.
///
/// The strikethrough and the fill move on the tap rather than after the save returns: the write
/// is local, ordered behind whatever save is in flight, and a checkbox that waits for storage
/// feels broken on the second tap.
private struct TaskRow: View {
    let task: NoteMarkdownBlock.Task
    let theme: NoteTheme
    let isEnabled: Bool
    let onToggle: @MainActor @Sendable () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: theme.small) {
                Image(systemName: task.isDone ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(task.isDone ? theme.accent : theme.secondaryText)
                    .frame(width: 18)

                Text(verbatim: task.text)
                    .font(theme.bodyFont)
                    .strikethrough(task.isDone, color: theme.disabledText)
                    .foregroundStyle(task.isDone ? theme.disabledText : theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotePressButtonStyle())
        .disabled(!isEnabled)
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: task.isDone)
        .accessibilityAddTraits(task.isDone ? [.isSelected] : [])
        .accessibilityLabel(Text(verbatim: task.text))
    }
}

private struct CopyableValueRow: View {
    let value: String
    let clipboardLifetime: TimeInterval
    let theme: NoteTheme
    let onCopy: @MainActor @Sendable (String) -> Void

    @State private var secondsLeft: Int?
    @State private var countdownTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: theme.xs) {
            HStack(alignment: .top, spacing: theme.small) {
                Text(verbatim: value)
                    .font(theme.monoFont)
                    .foregroundStyle(theme.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: copyValue) {
                    Text(secondsLeft == nil ? .notesKit("Copy") : .notesKit("Copied"))
                        .font(theme.modeFont)
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(secondsLeft == nil ? theme.secondaryText : theme.success)
                        .padding(.horizontal, theme.small)
                        .frame(height: 26)
                        .overlay {
                            Capsule().strokeBorder(
                                secondsLeft == nil ? theme.separator : theme.success.opacity(0.5),
                                lineWidth: 0.75
                            )
                        }
                }
                .buttonStyle(NotePressButtonStyle())
            }

            if let secondsLeft {
                HStack(spacing: 4) {
                    Text(.notesKit("Clipboard clears in"))
                    Text(secondsLeft, format: .number).contentTransition(.numericText())
                    Text(verbatim: "s")
                }
                .font(theme.metadataFont)
                .foregroundStyle(theme.disabledText)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(theme.small + 4)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 0.75)
        }
        .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: secondsLeft != nil)
        .onDisappear { countdownTask?.cancel() }
    }

    private func copyValue() {
        onCopy(value)
        countdownTask?.cancel()
        secondsLeft = max(1, Int(clipboardLifetime.rounded(.up)))
        countdownTask = Task { @MainActor in
            while let remaining = secondsLeft, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                secondsLeft = max(0, remaining - 1)
            }
            secondsLeft = nil
        }
    }
}
