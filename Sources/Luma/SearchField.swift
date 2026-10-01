import AppKit
import SwiftUI

struct LauncherSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let onSubmit: () -> Void
    let onMove: (Int) -> Void
    /// 左右方向键；返回是否消费按键，未消费时交还文本光标移动。
    let onHorizontalMove: (Int) -> Bool
    let onEscape: () -> Void
    /// 输入法正在组合（有标记文本）时为 true，此时占位符必须让位。
    let onComposingChange: (Bool) -> Void

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
        // NSSearchFieldCell 自带一个本地化的默认占位符（中文即「搜索」，且用输入框
        // 自己的 26pt 字体绘制）。占位符由 LauncherHeader 自己画，这里必须压掉它；
        // 置空字符串会被当成 nil 而回退到默认值，所以用一个透明的空格占位。
        // 字号要跟输入框一致：输入框的固有高度由占位符字号决定，写小了会把输入的文字裁掉。
        field.placeholderAttributedString = NSAttributedString(
            string: " ",
            attributes: [
                .font: NSFont.systemFont(ofSize: LumaChromeMetrics.titleFontSize, weight: .medium),
                .foregroundColor: NSColor.clear
            ]
        )
        (field.cell as? NSSearchFieldCell)?.searchButtonCell = nil
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
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
            parent.onComposingChange(
                (field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
            )
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
