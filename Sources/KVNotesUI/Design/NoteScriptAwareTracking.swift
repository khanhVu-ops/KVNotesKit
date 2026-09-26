import SwiftUI

extension View {
    /// Letter-spacing that steps aside for the scripts it damages: Arabic (every right-to-left
    /// language shipped) and Hindi are joined scripts, and tracking pries their letters apart.
    /// Same rule as the host app's `appTracking` and the editor's caps style.
    func scriptTracking(_ value: CGFloat) -> some View {
        modifier(NoteScriptAwareTracking(value: value))
    }
}

private struct NoteScriptAwareTracking: ViewModifier {
    let value: CGFloat

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        let joinedScript = layoutDirection == .rightToLeft
            || locale.language.languageCode?.identifier == "hi"
        return content.tracking(joinedScript ? 0 : value)
    }
}
