import AppKit
import SwiftUI

struct JSONSyntaxEditor: NSViewRepresentable {
    @Binding var text: String
    let autofocus: Bool

    init(text: Binding<String>, autofocus: Bool = false) {
        _text = text
        self.autofocus = autofocus
    }

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
        context.coordinator.focusIfNeeded(scrollView, autofocus: autofocus)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.focusIfNeeded(scrollView, autofocus: autofocus)
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
        private var didAutofocus = false
        private var pendingHighlight: DispatchWorkItem?
        private static let tokenPatterns: [(NSRegularExpression, NSColor)] = [
            (try! NSRegularExpression(pattern: #"[{}\[\],:]"#), .secondaryLabelColor),
            (try! NSRegularExpression(pattern: #"-?\b(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#), .systemBlue),
            (try! NSRegularExpression(pattern: #"\b(?:true|false|null)\b"#), .systemOrange),
            (try! NSRegularExpression(pattern: #"\"(?:\\.|[^\"\\])*\""#), .systemGreen),
            (try! NSRegularExpression(pattern: #"\"(?:\\.|[^\"\\])*\"(?=\s*:)"#), .systemPurple)
        ]

        init(parent: JSONSyntaxEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            scheduleHighlighting(for: textView)
        }

        func focusIfNeeded(_ scrollView: NSScrollView, autofocus: Bool) {
            guard autofocus, !didAutofocus else { return }
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self,
                      !self.didAutofocus,
                      let scrollView,
                      let textView = scrollView.documentView as? NSTextView,
                      let window = textView.window else { return }
                window.makeFirstResponder(textView)
                self.didAutofocus = true
            }
        }

        func applyHighlighting(to textView: NSTextView) {
            pendingHighlight?.cancel()
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
            for (regex, color) in Self.tokenPatterns {
                highlight(regex, color: color, in: storage)
            }
            storage.endEditing()
            textView.setSelectedRange(selection)
            textView.typingAttributes = base
            isUpdating = false
        }

        private func scheduleHighlighting(for textView: NSTextView) {
            pendingHighlight?.cancel()
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.applyHighlighting(to: textView)
            }
            pendingHighlight = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }

        private func highlight(
            _ regex: NSRegularExpression,
            color: NSColor,
            in storage: NSTextStorage
        ) {
            let range = NSRange(location: 0, length: storage.length)
            regex.enumerateMatches(in: storage.string, range: range) { result, _, _ in
                guard let result else { return }
                storage.addAttribute(.foregroundColor, value: color, range: result.range)
            }
        }
    }
}
