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
    let doneTitle: String
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
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        view.textColor = UIColor(theme.primaryText)
        view.tintColor = UIColor(theme.primaryText)
        view.font = Self.font

        if let pendingCaretOffset {
            let clamped = min(max(pendingCaretOffset, 0), view.text.count)
            if let position = view.position(from: view.beginningOfDocument, offset: clamped) {
                view.selectedTextRange = view.textRange(from: position, to: position)
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

        init(parent: NoteTextEditor) { self.parent = parent }

        func attach(_ view: UITextView) { textView = view }

        func makeAccessoryBar() -> UIView {
            let bar = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 46))
            bar.autoresizingMask = .flexibleWidth
            bar.backgroundColor = UIColor(parent.theme.sheet)

            let hairline = UIView()
            hairline.backgroundColor = UIColor(parent.theme.separator)
            hairline.translatesAutoresizingMaskIntoConstraints = false

            let keys = UIStackView(arrangedSubviews: MarkdownToken.allCases.enumerated().map { index, token in
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

        func textViewDidChange(_ textView: UITextView) {
            self.textView = textView
            parent.text = textView.text
            reportSelection(of: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            self.textView = textView
            reportSelection(of: textView)
        }

        private func reportSelection(of textView: UITextView) {
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
    let doneTitle: String
    let haptic: @MainActor @Sendable () -> Void

    var body: some View {
        TextEditor(text: $text)
            .font(theme.monoFont)
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, theme.medium)
    }
}
#endif
