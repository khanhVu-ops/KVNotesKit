import KVNotesCore
import SwiftUI

#if canImport(UIKit)
import UIKit

/// A hardened editing surface. Predictive learning, spell checking and smart punctuation stay
/// disabled so secrets typed here do not leave the vault through keyboard conveniences.
struct NoteTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: Range<Int>
    let pendingCaretOffset: Int?
    let theme: NoteTheme
    let onCaretApplied: @MainActor @Sendable () -> Void
    let onInsert: @MainActor @Sendable (MarkdownToken) -> Void
    let onContinuation: (@MainActor @Sendable (String, Int) -> Void)?
    let onUndo: @MainActor @Sendable () -> Void
    let onRedo: @MainActor @Sendable () -> Void
    let onInsertTimestamp: @MainActor @Sendable () -> Void
    let onOpenGenerator: @MainActor @Sendable () -> Void
    let onOpenFind: @MainActor @Sendable () -> Void
    let onIndent: @MainActor @Sendable () -> Void
    let onOutdent: @MainActor @Sendable () -> Void
    let canUndo: Bool
    let canRedo: Bool
    let findMatches: [NSRange]
    let currentFindMatch: NSRange?
    /// False while read mode is on top. The view stays in the hierarchy — it keeps the caret and
    /// the scroll position across the switch — but it must not hold the keyboard.
    let isActive: Bool
    let doneTitle: String
    let undoTitle: String
    let redoTitle: String
    let timestampTitle: String
    let generatorTitle: String
    let findTitle: String
    let indentTitle: String
    let outdentTitle: String
    let haptic: @MainActor @Sendable () -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(
            top: 0,
            left: theme.medium,
            bottom: theme.extraLarge,
            right: theme.medium
        )
        view.textContainer.lineFragmentPadding = 0
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.textContentType = nil
        view.adjustsFontForContentSizeCategory = true
        view.font = Self.font
        view.text = text
        view.inputAccessoryView = context.coordinator.makeAccessoryBar()
        context.coordinator.attach(view)
        context.coordinator.styleEverythingVisible(in: view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            // A ViewModel-driven change: an insertion, an undo, a toggled checkbox. Assigning
            // `.text` drops every attribute in the storage, so the visible range is restyled
            // immediately afterwards rather than on the next keystroke.
            view.text = text
            context.coordinator.styleEverythingVisible(in: view)
        }
        context.coordinator.updateHistoryKeys(canUndo: canUndo, canRedo: canRedo)
        if !isActive, view.isFirstResponder { view.resignFirstResponder() }
        context.coordinator.applyFindHighlights(in: view)
        view.tintColor = UIColor(theme.primaryText)
        if view.font != Self.font {
            view.font = Self.font
            context.coordinator.styleEverythingVisible(in: view)
        }

        if let pendingCaretOffset {
            let clamped = min(max(pendingCaretOffset, 0), view.text.count)
            if let position = view.position(from: view.beginningOfDocument, offset: clamped) {
                view.selectedTextRange = view.textRange(from: position, to: position)
                // Report it back rather than waiting for the delegate: setting the range
                // programmatically does not reliably call `textViewDidChangeSelection`, and a
                // binding left behind sends the *next* insertion to where the caret used to be.
                context.coordinator.reportSelection(of: view)
            }
            Task { @MainActor in onCaretApplied() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private static var font: UIFont {
        UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .monospacedSystemFont(ofSize: 15, weight: .regular)
        )
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteTextEditor
        private weak var textView: UITextView?
        private weak var undoKey: UIButton?
        private weak var redoKey: UIButton?

        init(parent: NoteTextEditor) { self.parent = parent }

        func attach(_ view: UITextView) {
            textView = view
            view.typingAttributes = styling.typingAttributes
        }

        /// Built once and reused: the attribute dictionaries are the expensive part, and they do
        /// not change between keystrokes. Rebuilt only when the font does — a Dynamic Type change.
        private var cachedStyling: NoteSyntaxStyling?
        private var lastFindSignature: FindSignature?
        private var styling: NoteSyntaxStyling {
            if let cachedStyling, cachedStyling.baseFont == NoteTextEditor.font { return cachedStyling }
            let styling = NoteSyntaxStyling(theme: parent.theme, baseFont: NoteTextEditor.font)
            cachedStyling = styling
            return styling
        }

        /// Styles what is on screen plus a margin either side.
        func styleEverythingVisible(in view: UITextView) {
            let text = view.text as NSString
            guard text.length > 0 else { return }
            styling.apply(
                to: view.textStorage,
                range: visibleRange(of: view),
                matches: parent.findMatches,
                current: parent.currentFindMatch
            )
            view.typingAttributes = styling.typingAttributes
        }

        /// Styles only the lines an edit touched.
        ///
        /// The keystroke path. Everything here is bounded by the paragraph the caret is in, so the
        /// cost of typing does not grow with the length of the note.
        private func styleEditedParagraph(in view: UITextView) {
            let text = view.text as NSString
            guard text.length > 0 else { return }
            let paragraph = NoteSyntaxHighlighting.lineRange(of: text, containing: view.selectedRange)
            styling.apply(
                to: view.textStorage,
                range: paragraph,
                matches: parent.findMatches,
                current: parent.currentFindMatch
            )
            // Typing attributes are reset every time: without this, a character typed right after
            // a bold run inherits bold and the note grows styling the author never wrote.
            view.typingAttributes = styling.typingAttributes
        }

        /// Repaints and scrolls when the search moves, and does nothing at all when it has not —
        /// `updateUIView` runs for every state change in the screen, including every keystroke.
        func applyFindHighlights(in view: UITextView) {
            let signature = FindSignature(matches: parent.findMatches, current: parent.currentFindMatch)
            guard signature != lastFindSignature else { return }
            lastFindSignature = signature
            styleEverythingVisible(in: view)
            guard let current = parent.currentFindMatch else { return }
            view.scrollRangeToVisible(current)
        }

        private struct FindSignature: Equatable {
            let matches: [NSRange]
            let current: NSRange?
        }

        private func visibleRange(of view: UITextView) -> NSRange {
            let text = view.text as NSString
            let inset = view.textContainerInset
            let rect = CGRect(
                x: 0,
                y: view.contentOffset.y - inset.top,
                width: view.bounds.width,
                height: view.bounds.height
            )
            guard let start = view.closestPosition(to: CGPoint(x: rect.minX, y: rect.minY)),
                  let end = view.closestPosition(to: CGPoint(x: rect.maxX, y: rect.maxY))
            else { return NSRange(location: 0, length: min(text.length, NoteSyntaxStyling.visibleMargin)) }

            let lower = view.offset(from: view.beginningOfDocument, to: start)
            let upper = view.offset(from: view.beginningOfDocument, to: end)
            let padded = NSRange(
                location: max(0, min(lower, upper) - NoteSyntaxStyling.visibleMargin),
                length: abs(upper - lower) + NoteSyntaxStyling.visibleMargin * 2
            )
            return NoteSyntaxHighlighting.lineRange(
                of: text,
                containing: NSIntersectionRange(padded, NSRange(location: 0, length: text.length))
            )
        }

        /// Dim rather than hide: keys that come and go move every other key under the thumb.
        func updateHistoryKeys(canUndo: Bool, canRedo: Bool) {
            undoKey?.isEnabled = canUndo
            redoKey?.isEnabled = canRedo
            undoKey?.alpha = canUndo ? 1 : 0.4
            redoKey?.alpha = canRedo ? 1 : 0.4
        }

        func makeAccessoryBar() -> UIView {
            let bar = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 46))
            bar.autoresizingMask = .flexibleWidth
            bar.backgroundColor = UIColor(parent.theme.sheet)

            let hairline = UIView()
            hairline.backgroundColor = UIColor(parent.theme.separator)
            hairline.translatesAutoresizingMaskIntoConstraints = false

            let undo = key(symbol: "arrow.uturn.backward", action: #selector(undoTapped))
            undo.accessibilityLabel = parent.undoTitle
            undoKey = undo

            let redo = key(symbol: "arrow.uturn.forward", action: #selector(redoTapped))
            redo.accessibilityLabel = parent.redoTitle
            redoKey = redo
            updateHistoryKeys(canUndo: parent.canUndo, canRedo: parent.canRedo)

            let separator = UIView()
            separator.backgroundColor = UIColor(parent.theme.separator)
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.widthAnchor.constraint(equalToConstant: 0.75).isActive = true
            separator.heightAnchor.constraint(equalToConstant: 20).isActive = true

            let timestamp = key(symbol: "clock", action: #selector(timestampTapped))
            timestamp.accessibilityLabel = parent.timestampTitle

            let generator = key(symbol: "key.horizontal", action: #selector(generatorTapped))
            generator.accessibilityLabel = parent.generatorTitle

            let find = key(symbol: "magnifyingglass", action: #selector(findTapped))
            find.accessibilityLabel = parent.findTitle

            let outdent = key(symbol: "decrease.indent", action: #selector(outdentTapped))
            outdent.accessibilityLabel = parent.outdentTitle

            let indent = key(symbol: "increase.indent", action: #selector(indentTapped))
            indent.accessibilityLabel = parent.indentTitle

            let keys = UIStackView(arrangedSubviews: [undo, redo, separator, outdent, indent, find, timestamp, generator]
                + MarkdownToken.allCases.enumerated().map { index, token in
                    key(titled: token.keyTitle, tag: index, action: #selector(insertTapped(_:)))
                })
            keys.spacing = parent.theme.xs
            keys.alignment = .center
            keys.translatesAutoresizingMaskIntoConstraints = false

            // Keep the formatting keys on one line at every Dynamic Type size. A fixed stack is
            // compressed on narrow phones and can turn `H2` into two rows; scrolling preserves
            // each key's hit target while the Done action remains pinned and immediately usable.
            let keyScroller = UIScrollView()
            keyScroller.showsHorizontalScrollIndicator = false
            keyScroller.alwaysBounceHorizontal = false
            keyScroller.addSubview(keys)
            NSLayoutConstraint.activate([
                keys.leadingAnchor.constraint(equalTo: keyScroller.contentLayoutGuide.leadingAnchor),
                keys.trailingAnchor.constraint(equalTo: keyScroller.contentLayoutGuide.trailingAnchor),
                keys.topAnchor.constraint(equalTo: keyScroller.contentLayoutGuide.topAnchor),
                keys.bottomAnchor.constraint(equalTo: keyScroller.contentLayoutGuide.bottomAnchor),
                keys.heightAnchor.constraint(equalTo: keyScroller.frameLayoutGuide.heightAnchor)
            ])

            let done = key(titled: parent.doneTitle, tag: -1, action: #selector(doneTapped))
            done.backgroundColor = UIColor(parent.theme.accent)
            done.configuration?.baseForegroundColor = UIColor(parent.theme.onAccent)
            done.layer.borderWidth = 0
            done.setContentCompressionResistancePriority(.required, for: .horizontal)

            let row = UIStackView(arrangedSubviews: [keyScroller, done])
            row.spacing = parent.theme.xs
            row.alignment = .center
            row.translatesAutoresizingMaskIntoConstraints = false

            bar.addSubview(hairline)
            bar.addSubview(row)
            NSLayoutConstraint.activate([
                hairline.topAnchor.constraint(equalTo: bar.topAnchor),
                hairline.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
                hairline.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
                hairline.heightAnchor.constraint(equalToConstant: 0.75),
                row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: parent.theme.small + 2),
                row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -(parent.theme.small + 2)),
                row.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
            ])
            return bar
        }

        private func key(symbol: String, action: Selector) -> UIButton {
            let button = key(titled: "", tag: -2, action: action)
            button.configuration?.image = UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            )
            return button
        }

        private func key(titled title: String, tag: Int, action: Selector) -> UIButton {
            var configuration = UIButton.Configuration.plain()
            configuration.title = title
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: parent.theme.small,
                bottom: 0,
                trailing: parent.theme.small
            )
            configuration.baseForegroundColor = UIColor(parent.theme.primaryText)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
                    for: .monospacedSystemFont(ofSize: 13, weight: .medium)
                )
                return outgoing
            }
            let button = UIButton(configuration: configuration)
            button.titleLabel?.numberOfLines = 1
            button.titleLabel?.lineBreakMode = .byClipping
            button.backgroundColor = UIColor(parent.theme.card)
            button.layer.cornerRadius = parent.theme.smallRadius
            button.layer.borderWidth = 0.75
            button.layer.borderColor = UIColor(parent.theme.separator).cgColor
            button.tag = tag
            button.addTarget(self, action: action, for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            return button
        }

        @objc private func insertTapped(_ sender: UIButton) {
            let tokens = MarkdownToken.allCases
            guard tokens.indices.contains(sender.tag) else { return }
            parent.haptic()
            parent.onInsert(tokens[sender.tag])
        }

        @objc private func doneTapped() { textView?.resignFirstResponder() }

        @objc private func undoTapped() {
            parent.haptic()
            parent.onUndo()
        }

        @objc private func redoTapped() {
            parent.haptic()
            parent.onRedo()
        }

        @objc private func timestampTapped() {
            parent.haptic()
            parent.onInsertTimestamp()
        }

        @objc private func generatorTapped() {
            parent.haptic()
            parent.onOpenGenerator()
        }

        @objc private func findTapped() {
            parent.haptic()
            parent.onOpenFind()
        }

        @objc private func outdentTapped() {
            parent.haptic()
            parent.onOutdent()
        }

        @objc private func indentTapped() {
            parent.haptic()
            parent.onIndent()
        }

        func textViewDidChange(_ textView: UITextView) {
            self.textView = textView
            styleEditedParagraph(in: textView)
            parent.text = textView.text
            reportSelection(of: textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            let fullText = textView.text ?? ""
            guard let textRange = Range(range, in: fullText) else { return true }
            let lower = fullText.distance(from: fullText.startIndex, to: textRange.lowerBound)
            let upper = fullText.distance(from: fullText.startIndex, to: textRange.upperBound)

            // 1. Return: Markdown list continuation / exit
            if text == "\n" {
                if let result = MarkdownListContinuation.continueOrExitList(
                    in: fullText,
                    selection: lower..<upper
                ) {
                    applyCustomEdit(result.text, caretOffset: result.caretOffset, in: textView)
                    return false
                }
                return true
            }

            // 2. Typing: Auto-pairing / Smart-wrapping / Skip-over
            if text.count == 1 {
                if let result = MarkdownAutoPairing.handleTyping(
                    text,
                    in: fullText,
                    selection: lower..<upper
                ) {
                    applyCustomEdit(result.text, caretOffset: result.caretOffset, in: textView)
                    return false
                }
            }

            // 3. Backspace: Empty pair deletion
            if text.isEmpty, range.length == 1 {
                if let result = MarkdownAutoPairing.handleBackspace(
                    in: fullText,
                    selection: lower..<upper
                ) {
                    applyCustomEdit(result.text, caretOffset: result.caretOffset, in: textView)
                    return false
                }
            }

            return true
        }

        private func applyCustomEdit(
            _ newText: String,
            caretOffset: Int,
            in textView: UITextView
        ) {
            textView.text = newText
            let charIdx = newText.index(
                newText.startIndex,
                offsetBy: min(max(caretOffset, 0), newText.count)
            )
            let utf16Offset = NSRange(charIdx..<charIdx, in: newText).location
            textView.selectedRange = NSRange(location: utf16Offset, length: 0)
            textView.scrollRangeToVisible(textView.selectedRange)
            styleEditedParagraph(in: textView)
            parent.text = newText
            reportSelection(of: textView)
            parent.onContinuation?(newText, caretOffset)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let view = scrollView as? UITextView else { return }
            // Scrolling styles what has come into view. Cheap for the same reason the keystroke
            // path is: it is a range, not the document.
            styleEverythingVisible(in: view)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            self.textView = textView
            reportSelection(of: textView)
        }

        func reportSelection(of textView: UITextView) {
            let value = textView.text ?? ""
            guard let range = Range(textView.selectedRange, in: value) else { return }
            let lower = value.distance(from: value.startIndex, to: range.lowerBound)
            let upper = value.distance(from: value.startIndex, to: range.upperBound)
            let reported = lower..<max(lower, upper)
            if parent.selection != reported { parent.selection = reported }
        }
    }
}
#else
struct NoteTextEditor: View {
    @Binding var text: String
    @Binding var selection: Range<Int>
    let pendingCaretOffset: Int?
    let theme: NoteTheme
    let onCaretApplied: @MainActor @Sendable () -> Void
    let onInsert: @MainActor @Sendable (MarkdownToken) -> Void
    let onContinuation: (@MainActor @Sendable (String, Int) -> Void)?
    let onUndo: @MainActor @Sendable () -> Void
    let onRedo: @MainActor @Sendable () -> Void
    let onInsertTimestamp: @MainActor @Sendable () -> Void
    let onOpenGenerator: @MainActor @Sendable () -> Void
    let onOpenFind: @MainActor @Sendable () -> Void
    let onIndent: @MainActor @Sendable () -> Void
    let onOutdent: @MainActor @Sendable () -> Void
    let canUndo: Bool
    let canRedo: Bool
    let findMatches: [NSRange]
    let currentFindMatch: NSRange?
    let isActive: Bool
    let doneTitle: String
    let undoTitle: String
    let redoTitle: String
    let timestampTitle: String
    let generatorTitle: String
    let findTitle: String
    let indentTitle: String
    let outdentTitle: String
    let haptic: @MainActor @Sendable () -> Void

    var body: some View {
        TextEditor(text: $text)
            .font(theme.monoFont)
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, theme.medium)
    }
}
#endif
