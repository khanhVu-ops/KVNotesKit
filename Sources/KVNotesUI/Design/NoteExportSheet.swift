import KVNotesCore
import SwiftUI

struct NoteExportSheet: View {
    let theme: NoteTheme
    var haptic: @MainActor @Sendable () -> Void = {}
    let onSelect: @MainActor @Sendable (NoteExportFormat) -> Void
    let onCancel: @MainActor @Sendable () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.medium) {
            header
            warningCard
            formatCards
            Spacer(minLength: theme.xs)
            cancelButton
        }
        .padding(.horizontal, theme.medium)
        .padding(.top, theme.large)
        .padding(.bottom, theme.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.sheet)
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(.notesKit("Export note"))
                .font(theme.titleFont)
                .foregroundStyle(theme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text(.notesKit("Security"))
                .font(theme.metadataFont)
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var warningCard: some View {
        HStack(alignment: .top, spacing: theme.small + 2) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.warning)
                .frame(width: 24, height: 24)

            Text(.notesKit("The exported file will not be encrypted. Anyone with access to this file can read its contents."))
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(theme.small + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .fill(theme.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: theme.largeRadius, style: .continuous)
                .strokeBorder(theme.warning.opacity(0.35), lineWidth: 0.75)
        }
    }

    private var formatCards: some View {
        VStack(spacing: 0) {
            formatRow(
                title: .notesKit("Export as Markdown"),
                badge: ".md",
                icon: "doc.text",
                format: .markdown
            )

            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.75)
                .padding(.leading, 56)

            formatRow(
                title: .notesKit("Export as Plain Text"),
                badge: ".txt",
                icon: "text.alignleft",
                format: .plainText
            )
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

    private func formatRow(
        title: LocalizedStringResource,
        badge: String,
        icon: String,
        format: NoteExportFormat
    ) -> some View {
        Button {
            haptic()
            onSelect(format)
        } label: {
            HStack(spacing: theme.small + 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: theme.smallRadius - 2, style: .continuous)
                        .fill(theme.accent.opacity(0.12))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.accent)
                }
                .frame(width: 32, height: 32)

                Text(title)
                    .font(theme.rowFont)
                    .foregroundStyle(theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(verbatim: badge)
                    .font(theme.monoFont)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.elevatedCard, in: Capsule())

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, theme.small + 4)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotePressButtonStyle())
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text(.notesKit("Cancel"))
                .font(theme.modeFont)
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(theme.card, in: Capsule())
                .overlay { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
        }
        .buttonStyle(NotePressButtonStyle())
    }
}

#Preview {
    NoteExportSheet(
        theme: .preview,
        onSelect: { _ in },
        onCancel: {}
    )
}
