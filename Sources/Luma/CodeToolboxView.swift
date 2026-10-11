import AppKit
import SwiftUI

/// 合并「JSON 编辑器」之后的编码小助手：上方输入、中间工具、下方结果。
///
/// 工具按分类分页显示，一次只铺开一组按钮，否则 28 个工具排下来会占掉
/// 编辑器的高度。JSON 高亮编辑器同时用于输入与输出，输出是 JSON 时同样有色。
struct CodePluginView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @State private var input = ""
    @State private var output = ""
    @State private var category: CodeToolboxCategory = .json
    @State private var message = ""
    @State private var isFailure = false

    var body: some View {
        VStack(spacing: 10) {
            editor(
                text: $input,
                autofocus: true,
                placeholder: L10n.text(
                    "粘贴或输入要处理的文本、JSON",
                    "Paste or type the text or JSON to work on"
                ),
                tint: nil
            )

            toolArea

            editor(
                text: $output,
                autofocus: false,
                placeholder: L10n.text("结果会显示在这里", "The result appears here"),
                tint: .cyan
            )

            actionRow
        }
        .padding(24)
    }

    private func editor(
        text: Binding<String>,
        autofocus: Bool,
        placeholder: String,
        tint: Color?
    ) -> some View {
        JSONSyntaxEditor(text: text, autofocus: autofocus)
            .background(
                tint.map { $0.opacity(0.06) } ?? LumaTone.controlFill,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tint.map { $0.opacity(0.22) } ?? Color(nsColor: .quaternaryLabelColor))
            }
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 13)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }
            }
    }

    /// 分类分页 + 当前分类的工具按钮，按钮按需换行。
    private var toolArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(CodeToolboxCategory.allCases) { item in
                    LumaSelectionButton(
                        title: item.title,
                        isSelected: category == item,
                        action: { category = item }
                    )
                }
            }

            LumaFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(category.tools) { tool in
                    Button(tool.title) { run(tool) }
                        .buttonStyle(LumaTextButtonStyle(height: 28))
                        .help(tool.help)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(LumaMotion.quick, value: category)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(isFailure ? Color.orange : Color.green)
                .lineLimit(1)

            Spacer(minLength: 12)

            Button(L10n.text("交换", "Swap")) { swap() }
                .buttonStyle(LumaTextButtonStyle(height: 28))
                .disabled(output.isEmpty)
                .help(L10n.text("把结果移到输入，便于连续处理", "Move the result into the input to chain tools"))

            Button(L10n.text("清空", "Clear")) { clear() }
                .buttonStyle(LumaTextButtonStyle(height: 28))
                .disabled(input.isEmpty && output.isEmpty)

            Button(L10n.text("复制", "Copy")) { clipboard.copy(output) }
                .buttonStyle(LumaTextButtonStyle(emphasis: .primary, height: 28))
                .disabled(output.isEmpty)
        }
    }

    private func run(_ tool: CodeToolboxTool) {
        if !tool.ignoresInput,
           input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = CodeToolboxError.nothingToDo.errorDescription ?? ""
            isFailure = true
            return
        }
        do {
            output = try tool.apply(to: input)
            message = "✓ " + tool.title
            isFailure = false
        } catch {
            message = error.localizedDescription
            isFailure = true
        }
    }

    private func swap() {
        let previousInput = input
        input = output
        output = previousInput
        message = ""
    }

    private func clear() {
        input = ""
        output = ""
        message = ""
    }
}

private extension CodeToolboxTool {
    /// 悬停提示：说明这个工具对输入的要求或产出形式。
    var help: String {
        switch self {
        case .jsonFormat:
            L10n.text("按 2 空格缩进并排序键名", "Indent with two spaces and sort keys")
        case .jsonMinify:
            L10n.text("去掉空白，压成一行", "Strip whitespace onto a single line")
        case .jsonEscape:
            L10n.text("转成可以嵌进 JSON 字符串的形式", "Turn the text into an embeddable JSON string")
        case .jsonUnescape:
            L10n.text("把 \\n、\\uXXXX 等转义还原", "Restore \\n, \\uXXXX, and other escapes")
        case .base64Encode, .base64Decode, .urlEncode, .urlDecode,
             .hexEncode, .hexDecode, .unicodeEscape, .unicodeUnescape:
            L10n.text("按 UTF-8 处理文本", "Operates on UTF-8 text")
        case .sha256, .sha512, .sha1, .md5:
            L10n.text("输出小写十六进制摘要", "Outputs a lowercase hexadecimal digest")
        case .camelCase, .pascalCase, .snakeCase, .kebabCase, .constantCase:
            L10n.text("先按空格、下划线、连字符与大小写拆词", "Splits on spaces, underscores, hyphens, and case changes")
        case .uuid:
            L10n.text("生成一个新的随机 UUID，不使用输入", "Generates a new random UUID; the input is ignored")
        case .timestampToDate:
            L10n.text("13 位按毫秒处理，输出带时区的 ISO 8601", "13 digits are treated as milliseconds; outputs ISO 8601 with an offset")
        case .dateToTimestamp:
            L10n.text("支持 ISO 8601、2024-05-01 12:00:00 与 2024-05-01", "Accepts ISO 8601, 2024-05-01 12:00:00, and 2024-05-01")
        case .sortLines, .dedupeLines, .reverseLines, .removeEmptyLines:
            L10n.text("以换行拆分，结果用换行连接", "Splits and rejoins on newlines")
        }
    }
}
