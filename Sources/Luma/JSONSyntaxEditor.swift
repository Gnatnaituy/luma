import AppKit
import SwiftUI

struct JSONSyntaxEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        scrollView.documentView = textView
        context.coordinator.applyHighlighting(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            context.coordinator.isUpdating = true
            textView.string = text
            context.coordinator.applyHighlighting(to: textView)
            context.coordinator.isUpdating = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONSyntaxEditor
        var isUpdating = false

        init(parent: JSONSyntaxEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyHighlighting(to: textView)
        }

        func applyHighlighting(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let selection = textView.selectedRange()
            let wholeRange = NSRange(location: 0, length: storage.length)
            let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            let base: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]

            isUpdating = true
            storage.beginEditing()
            storage.setAttributes(base, range: wholeRange)
            highlight(#"[{}\[\],:]"#, color: .secondaryLabelColor, in: storage)
            highlight(#"-?\b(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, color: .systemBlue, in: storage)
            highlight(#"\b(?:true|false|null)\b"#, color: .systemOrange, in: storage)
            highlight(#"\"(?:\\.|[^\"\\])*\""#, color: .systemGreen, in: storage)
            highlight(#"\"(?:\\.|[^\"\\])*\"(?=\s*:)"#, color: .systemPurple, in: storage)
            storage.endEditing()
            textView.setSelectedRange(selection)
            textView.typingAttributes = base
            isUpdating = false
        }

        private func highlight(_ pattern: String, color: NSColor, in storage: NSTextStorage) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(location: 0, length: storage.length)
            regex.enumerateMatches(in: storage.string, range: range) { result, _, _ in
                guard let result else { return }
                storage.addAttribute(.foregroundColor, value: color, range: result.range)
            }
        }
    }
}
