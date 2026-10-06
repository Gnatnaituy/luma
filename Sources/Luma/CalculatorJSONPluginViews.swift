import AppKit
import SwiftUI

struct CalculationRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let expression: String
    let result: String

    init(id: UUID = UUID(), expression: String, result: String) {
        self.id = id
        self.expression = expression
        self.result = result
    }
}
enum CalculationHistory {
    static let maximumCount = 15

    static func appending(
        expression: String,
        result: String,
        to records: [CalculationRecord]
    ) -> [CalculationRecord] {
        let updated = records + [CalculationRecord(expression: expression, result: result)]
        return Array(updated.suffix(maximumCount))
    }
}

final class CalculationHistoryStore: ObservableObject {
    @Published private(set) var records: [CalculationRecord]

    private let defaults: UserDefaults
    private let storageKey = "luma.calculator.history.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([CalculationRecord].self, from: data) {
            records = Array(decoded.suffix(CalculationHistory.maximumCount))
        } else {
            records = []
        }
    }

    func append(expression: String, result: String) {
        records = CalculationHistory.appending(
            expression: expression,
            result: result,
            to: records
        )
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct CalculatorPluginView: View {
    @StateObject private var history = CalculationHistoryStore()
    @State private var expression = ""
    @State private var errorMessage: String?
    @FocusState private var isExpressionFocused: Bool

    private var trimmedExpression: String {
        expression.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 版式与其它插件一致：顶部一条固定输入栏，历史记录占满剩余高度并自行滚动。
    ///
    /// 历史最多 15 条（约 675pt），原先直接堆在 `VStack` 里、没有滚动容器：内容最小高度
    /// 超过面板可用高度后整列溢出，顶部工具栏被挤出可视区域，看起来就像搜索栏消失了。
    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            content

            Text(L10n.text(
                "支持 + − × ÷ % ^、括号，以及 sqrt / sin / cos / tan / abs / log / ln。",
                "Supports + − × ÷ % ^, parentheses, and sqrt / sin / cos / tan / abs / log / ln."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { DispatchQueue.main.async { isExpressionFocused = true } }
    }

    /// 顶部输入栏沿用其它插件的控件填充与内边距，回车或点按等号计算。
    private var toolbar: some View {
        HStack(spacing: 7) {
            TextField(
                L10n.text("输入算式，如 (12 + 3) × 4", "Enter an expression, e.g. (12 + 3) × 4"),
                text: $expression
            )
                .textFieldStyle(LumaTextFieldStyle())
                .font(.system(size: 14, design: .monospaced))
                .focused($isExpressionFocused)
                .onSubmit(calculate)
                .accessibilityLabel(L10n.text("计算表达式", "Calculate Expression"))

            Button(action: calculate) {
                Image(systemName: "equal")
            }
            .buttonStyle(LumaIconButtonStyle())
            .disabled(trimmedExpression.isEmpty)
            .help(L10n.text("计算", "Calculate"))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if history.records.isEmpty {
            ContentUnavailableView(
                L10n.text("还没有计算记录", "No Calculations Yet"),
                systemImage: "function",
                description: Text(L10n.text(
                    "在上方输入算式并按回车，结果会保存在这里",
                    "Enter an expression above and press Return; results are kept here"
                ))
            )
        } else {
            // 与剪贴板插件一样最新的在最上面，刚算完的结果不用滚动就能看到。
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(history.records.reversed()) { record in
                        HStack(spacing: 12) {
                            Text(record.expression)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 20)
                            Text("= \(record.result)")
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(
                            LumaTone.cardFill,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
    }

    private func calculate() {
        guard !trimmedExpression.isEmpty else { return }
        do {
            let result = ExpressionEvaluator.display(try ExpressionEvaluator.evaluate(trimmedExpression))
            history.append(expression: trimmedExpression, result: result)
            expression = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct JSONPluginView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @State private var input = "{\"name\":\"Luma\",\"native\":true,\"plugins\":[\"clipboard\",\"calc\",\"json\"]}"
    @State private var message = ""

    var body: some View {
        VStack(spacing: 12) {
            JSONSyntaxEditor(text: $input, autofocus: true)
                .background(LumaTone.controlFill, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))

            HStack {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.hasPrefix("✓") ? .green : .orange)
                Spacer()
                Button(L10n.text("压缩", "Minify")) { transform(pretty: false) }
                    .buttonStyle(LumaTextButtonStyle())
                Button(L10n.text("转义", "Escape")) { escape() }
                    .buttonStyle(LumaTextButtonStyle())
                Button(L10n.text("去转义", "Unescape")) { unescape() }
                    .buttonStyle(LumaTextButtonStyle())
                Button(L10n.text("复制", "Copy")) { clipboard.copy(input) }
                    .buttonStyle(LumaTextButtonStyle())
                Button(L10n.text("格式化", "Format")) { transform(pretty: true) }
                    .buttonStyle(LumaTextButtonStyle(emphasis: .primary))
            }
        }
        .padding(24)
    }

    private func transform(pretty: Bool) {
        do {
            input = try JSONTool.format(input, pretty: pretty)
            message = L10n.text("✓ JSON 有效", "✓ Valid JSON")
        } catch {
            message = error.localizedDescription
        }
    }

    private func escape() {
        do {
            input = try JSONTool.escape(input)
            message = L10n.text("✓ 已转义", "✓ Escaped")
        } catch {
            message = error.localizedDescription
        }
    }

    private func unescape() {
        do {
            input = try JSONTool.unescape(input)
            message = L10n.text("✓ 已去转义", "✓ Unescaped")
        } catch {
            message = error.localizedDescription
        }
    }
}
