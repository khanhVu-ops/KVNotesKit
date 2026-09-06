import KVNotesCore
import SwiftUI

/// A details and security metrics panel for a note.
///
/// Displays word, character, and line counts alongside encrypted storage sizing
/// and cryptographic envelope metadata. When a note is locked, body-derived metrics
/// display an em dash to prevent information leakage without biometric authorization.
struct NoteInspectorView: View {
    let metrics: NoteMetrics
    let theme: NoteTheme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.small) {
            countsGrid
            metadataCard
        }
    }

    private var countsGrid: some View {
        HStack(spacing: theme.small) {
            countTile(title: .notesKit("Words"), count: metrics.words)
            countTile(title: .notesKit("Characters"), count: metrics.characters)
            countTile(title: .notesKit("Lines"), count: metrics.lines)
        }
    }

    private func countTile(title: LocalizedStringResource, count: Int?) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(theme.metadataFont)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)

            if let count {
                Text(count, format: .number)
                    .font(theme.rowFont)
                    .foregroundStyle(theme.primaryText)
                    .contentTransition(.numericText())
            } else {
                Text(verbatim: "—")
                    .font(theme.rowFont)
                    .foregroundStyle(theme.disabledText)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 0.75)
        }
    }

    private var metadataCard: some View {
        VStack(spacing: 0) {
            row(
                label: .notesKit("Created"),
                icon: "calendar.badge.plus"
            ) {
                Text(metrics.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(theme.metadataFont)
                    .foregroundStyle(theme.secondaryText)
            }

            separator

            row(
                label: .notesKit("Modified"),
                icon: "clock.arrow.circlepath"
            ) {
                Text(metrics.lastEditedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(theme.metadataFont)
                    .foregroundStyle(theme.secondaryText)
            }

            separator

            row(
                label: .notesKit("Storage"),
                icon: "internaldrive"
            ) {
                HStack(spacing: 4) {
                    Text(metrics.storedBytes, format: .number)
                        .font(theme.monoFont)
                        .foregroundStyle(theme.primaryText)
                    Text(verbatim: "B")
                        .font(theme.monoFont)
                        .foregroundStyle(theme.primaryText)
                    Text(verbatim: "(\(metrics.storedBytes / 1024) KiB)")
                        .font(theme.metadataFont)
                        .foregroundStyle(theme.secondaryText)
                }
            }

            separator

            row(
                label: .notesKit("Cipher"),
                icon: "lock.shield"
            ) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.success)
                    Text(verbatim: metrics.cipherDescription)
                        .font(theme.monoFont)
                        .foregroundStyle(theme.primaryText)
                }
            }
        }
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 0.75)
        }
    }

    private func row(
        label: LocalizedStringResource,
        icon: String,
        @ViewBuilder value: () -> some View
    ) -> some View {
        HStack(spacing: theme.small) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 20)

            Text(label)
                .font(theme.bodyFont)
                .foregroundStyle(theme.primaryText)

            Spacer()

            value()
        }
        .padding(.horizontal, theme.medium)
        .frame(height: 44)
    }

    private var separator: some View {
        Divider()
            .overlay(theme.separator)
            .padding(.leading, theme.medium + 28)
    }
}

/// Standalone sheet for inspecting a note's metrics from the notes list.
struct NoteInspectorSheet: View {
    let noteTitle: String
    let metrics: NoteMetrics
    let theme: NoteTheme
    let onDismiss: @MainActor @Sendable () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: theme.medium) {
                    NoteInspectorView(metrics: metrics, theme: theme)
                }
                .padding(.horizontal, theme.medium)
                .padding(.top, theme.small)
                .padding(.bottom, theme.extraLarge)
            }
            .scrollIndicators(.hidden)
        }
        .background(theme.sheet)
        .presentationDetents([.medium])
        .presentationBackground(theme.sheet)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(.notesKit("Details"))
                    .font(theme.sectionFont)
                    .textCase(.uppercase)
                    .tracking(1.8)
                    .foregroundStyle(theme.primaryText)
                if !noteTitle.isEmpty {
                    Text(verbatim: noteTitle)
                        .font(theme.metadataFont)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: onDismiss) {
                Text(.notesKit("Done"))
                    .font(theme.modeFont)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, theme.medium)
                    .frame(height: 32)
                    .background(theme.accent, in: Capsule())
            }
            .buttonStyle(NotePressButtonStyle())
        }
        .padding(.horizontal, theme.medium)
        .padding(.vertical, theme.small + 4)
        .background(theme.sheet)
    }
}

#Preview("NoteInspectorView · Unlocked") {
    let metrics = NoteMetrics(
        body: "Title\n\nThis is a private note with some content to measure.",
        isLocked: false,
        createdAt: Date(),
        lastEditedAt: Date()
    )
    NoteInspectorView(metrics: metrics, theme: .preview)
        .padding()
        .background(NoteTheme.preview.background)
}

#Preview("NoteInspectorView · Locked") {
    let metrics = NoteMetrics(
        body: nil,
        isLocked: true,
        createdAt: Date().addingTimeInterval(-86400),
        lastEditedAt: Date()
    )
    NoteInspectorView(metrics: metrics, theme: .preview)
        .padding()
        .background(NoteTheme.preview.background)
}

#Preview("NoteInspectorSheet") {
    let metrics = NoteMetrics(
        body: "A secret note",
        isLocked: false,
        createdAt: Date(),
        lastEditedAt: Date()
    )
    NoteInspectorSheet(
        noteTitle: "My Secure Note",
        metrics: metrics,
        theme: .preview,
        onDismiss: {}
    )
}
