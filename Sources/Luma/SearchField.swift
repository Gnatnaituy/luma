import AppKit
import SwiftUI

struct LauncherSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    /// 大标题式的占位符：首页显示页面标题，其他页面显示搜索提示。
    let placeholder: String
    let onSubmit: () -> Void
    let onMove: (Int) -> Void
    /// 左右方向键；返回是否消费按键，未消费时交还文本光标移动。
    let onHorizontalMove: (Int) -> Bool
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        Self.configure(field, coordinator: context.coordinator)
        return field
    }

    static func configure(_ field: NSSearchField, coordinator: Coordinator) {
        field.font = .systemFont(ofSize: LumaChromeMetrics.titleFontSize, weight: .medium)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = coordinator
        field.cell?.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        (field.cell as? NSSearchFieldCell)?.searchButtonCell = nil
    }

    /// macOS 27 的标题兼作搜索框：占位符用更小更细的字号与三级文字色，
    /// 既能当页面标题，又不会看起来像已输入的内容。
    static func attributedPlaceholder(_ placeholder: String) -> NSAttributedString {
        NSAttributedString(
            string: placeholder,
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: LumaChromeMetrics.placeholderFontSize,
                    weight: .regular
                ),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        )
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        field.placeholderAttributedString = Self.attributedPlaceholder(placeholder)
        if field.stringValue != text { field.stringValue = text }
        guard context.coordinator.lastFocusRequest != focusRequest else { return }
        context.coordinator.lastFocusRequest = focusRequest
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: LauncherSearchField
        var lastFocusRequest = -1

        init(parent: LauncherSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                guard !textView.hasMarkedText() else { return false }
                parent.onSubmit(); return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1); return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1); return true
            case #selector(NSResponder.moveLeft(_:)):
                return parent.onHorizontalMove(-1)
            case #selector(NSResponder.moveRight(_:)):
                return parent.onHorizontalMove(1)
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape(); return true
            default:
                return false
            }
        }
    }
}
