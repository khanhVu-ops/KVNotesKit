import SwiftUI

/// Every visual decision KVNotesUI needs. Hosts map their design tokens once instead of letting
/// package screens reach back into an app's design system.
public struct NoteTheme {
    public var background: Color
    public var sheet: Color
    public var card: Color
    public var elevatedCard: Color
    public var separator: Color
    public var primaryText: Color
    public var secondaryText: Color
    public var disabledText: Color
    public var accent: Color
    public var onAccent: Color
    public var success: Color
    public var warning: Color
    public var error: Color

    public var titleFont: Font
    public var sectionFont: Font
    public var rowFont: Font
    public var modeFont: Font
    public var metadataFont: Font
    public var bodyFont: Font
    public var captionFont: Font
    public var monoFont: Font

    public var xs: CGFloat
    public var small: CGFloat
    public var medium: CGFloat
    public var large: CGFloat
    public var extraLarge: CGFloat
    public var smallRadius: CGFloat
    public var largeRadius: CGFloat

    public init(
        background: Color,
        sheet: Color,
        card: Color,
        elevatedCard: Color,
        separator: Color,
        primaryText: Color,
        secondaryText: Color,
        disabledText: Color,
        accent: Color,
        onAccent: Color,
        success: Color,
        warning: Color = .orange,
        error: Color,
        titleFont: Font,
        sectionFont: Font,
        rowFont: Font,
        modeFont: Font,
        metadataFont: Font,
        bodyFont: Font,
        captionFont: Font,
        monoFont: Font,
        xs: CGFloat = 4,
        small: CGFloat = 8,
        medium: CGFloat = 16,
        large: CGFloat = 24,
        extraLarge: CGFloat = 32,
        smallRadius: CGFloat = 10,
        largeRadius: CGFloat = 18
    ) {
        self.background = background
        self.sheet = sheet
        self.card = card
        self.elevatedCard = elevatedCard
        self.separator = separator
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.disabledText = disabledText
        self.accent = accent
        self.onAccent = onAccent
        self.success = success
        self.warning = warning
        self.error = error
        self.titleFont = titleFont
        self.sectionFont = sectionFont
        self.rowFont = rowFont
        self.modeFont = modeFont
        self.metadataFont = metadataFont
        self.bodyFont = bodyFont
        self.captionFont = captionFont
        self.monoFont = monoFont
        self.xs = xs
        self.small = small
        self.medium = medium
        self.large = large
        self.extraLarge = extraLarge
        self.smallRadius = smallRadius
        self.largeRadius = largeRadius
    }

    @MainActor public static let preview = NoteTheme(
        background: Color(red: 0.055, green: 0.059, blue: 0.067),
        sheet: Color(red: 0.075, green: 0.08, blue: 0.09),
        card: Color(red: 0.095, green: 0.1, blue: 0.11),
        elevatedCard: Color(red: 0.13, green: 0.135, blue: 0.15),
        separator: Color.white.opacity(0.13),
        primaryText: .white,
        secondaryText: Color.white.opacity(0.66),
        disabledText: Color.white.opacity(0.38),
        accent: Color(red: 0.84, green: 0.73, blue: 0.49),
        onAccent: .black,
        success: .green,
        warning: .orange,
        error: .red,
        titleFont: .system(.title2, design: .rounded, weight: .semibold),
        sectionFont: .system(.headline, design: .rounded, weight: .semibold),
        rowFont: .system(.body, design: .rounded, weight: .semibold),
        modeFont: .system(.caption, design: .rounded, weight: .semibold),
        metadataFont: .system(.caption2, design: .monospaced, weight: .medium),
        bodyFont: .body,
        captionFont: .caption,
        monoFont: .system(.body, design: .monospaced)
    )
}

extension View {
    func noteCard(theme: NoteTheme, padding: CGFloat) -> some View {
        self.padding(padding)
            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.smallRadius, style: .continuous)
                    .strokeBorder(theme.separator, lineWidth: 0.75)
            }
    }

    @ViewBuilder
    func noteNavigationChrome() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Section spacing sized for cards on a plain background rather than for grouped tables.
    @ViewBuilder
    func noteCompactSections(_ spacing: CGFloat) -> some View {
        #if os(iOS)
        listSectionSpacing(spacing)
        #else
        self
        #endif
    }

    /// `textSelection` takes two different types for on and off, so a ternary cannot express it.
    @ViewBuilder
    func noteTextSelection(enabled: Bool) -> some View {
        if enabled { textSelection(.enabled) } else { textSelection(.disabled) }
    }

    @ViewBuilder
    func noteNeverAutocapitalizes() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func noteInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
