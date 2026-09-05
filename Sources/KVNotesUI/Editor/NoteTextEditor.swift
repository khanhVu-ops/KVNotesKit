import KVNotesCore
import SwiftUI

#if canImport(UIKit)
import UIKit

struct NoteTextEditor: UIViewRepresentable {
    @Binding var text: String
    let pendingCaretOffset: Int?
    let theme: NoteTheme
    let onSelection: (Range<Int>) -> Void
    let onCaretApplied: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.keyboardDismissMode = .interactive
        view.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        view.textColor = UIColor(theme.primaryText)
        if let offset = pendingCaretOffset {
            let utf16Offset = String(text.prefix(min(offset, text.count))).utf16.count
            view.selectedRange = NSRange(location: utf16Offset, length: 0)
            DispatchQueue.main.async { onCaretApplied() }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteTextEditor
        init(_ parent: NoteTextEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidChangeSelection(_ textView: UITextView) {
            let value = textView.text ?? ""
            guard let range = Range(textView.selectedRange, in: value) else { return }
            let lower = value.distance(from: value.startIndex, to: range.lowerBound)
            let upper = value.distance(from: value.startIndex, to: range.upperBound)
            parent.onSelection(lower..<upper)
        }
    }
}
#else
struct NoteTextEditor: View {
    @Binding var text: String
    let pendingCaretOffset: Int?
    let theme: NoteTheme
    let onSelection: (Range<Int>) -> Void
    let onCaretApplied: () -> Void
    var body: some View { TextEditor(text: $text).font(theme.monoFont).foregroundStyle(theme.primaryText) }
}
#endif
