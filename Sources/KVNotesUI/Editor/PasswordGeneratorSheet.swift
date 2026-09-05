import KVNotesCore
import SwiftUI

/// Builds a password and hands it back for insertion at the caret.
///
/// There is no copy button, and that is the point: the value goes straight into the note, which
/// is already encrypted, instead of onto a pasteboard every other app on the device can read.
struct PasswordGeneratorSheet: View {
    let theme: NoteTheme
    let onInsert: @MainActor @Sendable (String) -> Void
    let onCancel: @MainActor @Sendable () -> Void

    @State private var recipe = PasswordRecipe()
    @State private var value = PasswordGeneration.password(for: PasswordRecipe())
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: theme.medium) {
            header
            preview
            controls
            actions
        }
        .padding(theme.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.sheet)
    }

    private var header: some View {
        Text(.notesKit("Generate a password"))
            .font(theme.sectionFont)
            .textCase(.uppercase)
            .tracking(1.6)
            .foregroundStyle(theme.primaryText)
            .padding(.top, theme.small)
    }

    private var preview: some View {
        Text(verbatim: value)
            .font(theme.monoFont)
            .foregroundStyle(theme.primaryText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.small + 4)
            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous)
                    .strokeBorder(theme.separator, lineWidth: 0.75)
            }
            .contentTransition(.opacity)
            .animation(NoteMotion.selection(reduceMotion: reduceMotion), value: value)
            .accessibilityLabel(Text(.notesKit("Generated password")))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: theme.small) {
            HStack {
                Text(.notesKit("Length"))
                    .font(theme.modeFont)
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Text(recipe.length, format: .number)
                    .font(theme.monoFont)
                    .foregroundStyle(theme.primaryText)
                    .contentTransition(.numericText())
            }
            Slider(
                value: Binding(
                    get: { Double(recipe.length) },
                    set: { recipe.length = Int($0.rounded()) }
                ),
                in: Double(PasswordRecipe.lengthRange.lowerBound)...Double(PasswordRecipe.lengthRange.upperBound),
                step: 1
            )
            .tint(theme.accent)
            .accessibilityLabel(Text(.notesKit("Length")))

            toggle(Text(.notesKit("Digits")), isOn: $recipe.includesDigits)
            toggle(Text(.notesKit("Symbols")), isOn: $recipe.includesSymbols)
        }
        .onChange(of: recipe) { regenerate() }
    }

    private func toggle(_ title: Text, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            title
                .font(theme.modeFont)
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(theme.secondaryText)
        }
        .tint(theme.accent)
    }

    private var actions: some View {
        HStack(spacing: theme.small) {
            Button(.notesKit("Regenerate")) { regenerate() }
                .font(theme.modeFont)
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(theme.card, in: Capsule())
                .overlay { Capsule().strokeBorder(theme.separator, lineWidth: 0.75) }
                .buttonStyle(NotePressButtonStyle())

            Button(.notesKit("Insert")) { onInsert(value) }
                .font(theme.modeFont)
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(theme.accent, in: Capsule())
                .buttonStyle(NotePressButtonStyle())
        }
        .padding(.top, theme.xs)
    }

    private func regenerate() {
        value = PasswordGeneration.password(for: recipe)
    }
}

#Preview {
    PasswordGeneratorSheet(theme: .preview, onInsert: { _ in }, onCancel: {})
}
