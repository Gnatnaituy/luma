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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("", text: $expression)
                .font(.system(size: 20, design: .monospaced))
                .textFieldStyle(.plain)
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                }
                .focused($isExpressionFocused)
                .onSubmit(calculate)
                .accessibilityLabel(L10n.text("计算表达式", "Calculate Expression"))

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 5) {
                ForEach(history.records) { record in
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
                        Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
            }

            Spacer(minLength: 0)

            Text(L10n.text(
                "支持 + − × ÷ % ^、括号，以及 sqrt / sin / cos / tan / abs / log / ln。",
                "Supports + − × ÷ % ^, parentheses, and sqrt / sin / cos / tan / abs / log / ln."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .onAppear { DispatchQueue.main.async { isExpressionFocused = true } }
    }

    private func calculate() {
        let source = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        do {
            let result = ExpressionEvaluator.display(try ExpressionEvaluator.evaluate(source))
            history.append(expression: source, result: result)
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
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
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
