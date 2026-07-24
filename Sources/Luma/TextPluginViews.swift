import AppKit
import SwiftUI

#if canImport(Translation)
import Translation
#endif

struct PasswordPluginView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @State private var length = 16
    @State private var uppercase = true
    @State private var digits = true
    @State private var symbols = true
    @State private var password = ""

    var body: some View {
        Form {
            Section("生成结果") {
                HStack {
                    Text(password)
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                        .privacySensitive()
                    Spacer()
                    Button("复制") { clipboard.copy(password) }
                        .buttonStyle(LumaTextButtonStyle())
                }
            }
            Section("选项") {
                HStack(spacing: 12) {
                    Text("长度")
                    Text("\(length)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 32)
                    Spacer(minLength: 16)
                    HStack(spacing: 6) {
                        Text("6").font(.caption).foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { Double(length) },
                                set: { length = Int($0.rounded()) }
                            ),
                            in: 6...32,
                            step: 1
                        )
                        .labelsHidden()
                        Text("32").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 460)
                }
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Toggle("大写字母", isOn: $uppercase)
                        .toggleStyle(LumaToggleStyle())
                    Toggle("数字", isOn: $digits)
                        .toggleStyle(LumaToggleStyle())
                    Toggle("符号", isOn: $symbols)
                        .toggleStyle(LumaToggleStyle())
                }
            }
            HStack {
                Spacer(minLength: 0)
                Button("重新生成") { generate() }
                    .buttonStyle(LumaTextButtonStyle(emphasis: .primary))
            }
        }
        .formStyle(.grouped)
        .onAppear { if password.isEmpty { generate() } }
        .onChange(of: length) { generate() }
        .onChange(of: uppercase) { generate() }
        .onChange(of: digits) { generate() }
        .onChange(of: symbols) { generate() }
    }

    private func generate() {
        password = PasswordTool.generate(length: length, uppercase: uppercase, digits: digits, symbols: symbols)
    }
}
struct BorderlessTextEditor: NSViewRepresentable {
    @Binding var text: String
    let autofocus: Bool
    let onSubmit: (() -> Void)?

    init(
        text: Binding<String>,
        autofocus: Bool = false,
        onSubmit: (() -> Void)? = nil
    ) {
        _text = text
        self.autofocus = autofocus
        self.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = Self.makeScrollView(text: text, delegate: context.coordinator)
        context.coordinator.focusIfNeeded(scrollView, autofocus: autofocus)
        return scrollView
    }

    static func makeScrollView(text: String, delegate: NSTextViewDelegate?) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .none

        let textView = NSTextView()
        textView.delegate = delegate
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSubmit = onSubmit
        context.coordinator.focusIfNeeded(scrollView, autofocus: autofocus)
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else { return }
        let selectedRanges = textView.selectedRanges
        textView.string = text
        textView.selectedRanges = selectedRanges.filter { rangeValue in
            NSMaxRange(rangeValue.rangeValue) <= (text as NSString).length
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        private var didAutofocus = false
        var onSubmit: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)? = nil) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let onSubmit,
                  BorderlessTextEditorCommand.shouldSubmit(
                    commandSelector,
                    modifierFlags: NSApp.currentEvent?.modifierFlags ?? []
                  ) else { return false }
            onSubmit()
            return true
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
    }
}

enum BorderlessTextEditorCommand {
    static func shouldSubmit(
        _ commandSelector: Selector,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        commandSelector == #selector(NSResponder.insertNewline(_:))
            && !modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
    }
}

struct TranslationPluginView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var settings: TranslationSettings
    @State private var input = ""
    @State private var output = ""
    @State private var isPresented = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var targetLanguage = TranslationLanguage.simplifiedChinese
    @State private var didLoadClipboard = false

    var body: some View {
        if settings.backend == .ai {
            translationContent
        } else {
            Group {
                if #available(macOS 14.4, *) {
                    translationContent
                        .translationPresentation(
                            isPresented: $isPresented,
                            text: input,
                            replacementAction: {
                                output = $0
                                errorMessage = nil
                            }
                        )
                } else {
                    ContentUnavailableView(
                        "需要 macOS 14.4 或更高版本",
                        systemImage: "character.book.closed",
                        description: Text("当前选择了 Apple 系统翻译")
                    )
                }
            }
        }
    }

    private var translationContent: some View {
        VStack(spacing: 12) {
            BorderlessTextEditor(
                text: $input,
                autofocus: true,
                onSubmit: submitTranslation
            )
                .padding(10)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                .onChange(of: input) { _, value in
                    updateTargetLanguage(for: value)
                }

            HStack(spacing: 10) {
                Spacer()

                engineDescription

                if settings.backend == .ai {
                    LumaMenuPicker(
                        selection: $targetLanguage,
                        values: TranslationLanguage.allCases,
                        title: { $0.title }
                    )
                    .frame(width: 120)
                }

                Button("复制结果") { clipboard.copy(output) }
                    .buttonStyle(LumaTextButtonStyle())
                    .disabled(output.isEmpty)

                if settings.backend == .ai {
                    Button {
                        submitTranslation()
                    } label: {
                        if isLoading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("翻译中")
                            }
                        } else {
                            Text("翻译")
                        }
                    }
                    .buttonStyle(LumaTextButtonStyle(emphasis: .primary))
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || settings.requestTarget == nil
                              || isLoading)
                } else {
                    Button("调用系统翻译") {
                        submitTranslation()
                    }
                    .buttonStyle(LumaTextButtonStyle(emphasis: .primary))
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            BorderlessTextEditor(text: $output)
                .padding(10)
                .background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).stroke(.teal.opacity(0.25))
                }
                .overlay(alignment: .topLeading) {
                    if output.isEmpty {
                        Text("翻译结果将在这里显示")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 15)
                            .padding(.top, 18)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(24)
        .onAppear(perform: loadClipboardTextIfNeeded)
    }

    @ViewBuilder
    private var engineDescription: some View {
        if settings.backend == .ai {
            if let provider = settings.selectedProvider, let model = settings.selectedModel {
                Text("\(provider.name) / \(model.name)")
                    .lineLimit(1)
            } else {
                Text("请先配置 AI 模型")
            }
        } else {
            Text("Apple Translation")
        }
    }

    private func translateWithAI() {
        guard let target = settings.requestTarget else {
            errorMessage = "AI 配置不可用，请检查供应商、模型和 API Key"
            return
        }
        let source = input
        let language = targetLanguage.promptName
        isLoading = true
        errorMessage = nil
        Task {
            do {
                output = try await AIService().translate(
                    text: source,
                    targetLanguage: language,
                    target: target
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func submitTranslation() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if settings.backend == .ai {
            guard !isLoading else { return }
            translateWithAI()
        } else {
            errorMessage = nil
            isPresented = true
        }
    }

    private func loadClipboardTextIfNeeded() {
        guard !didLoadClipboard else { return }
        didLoadClipboard = true
        guard let text = clipboard.currentPlainText() else { return }
        input = text
    }

    private func updateTargetLanguage(for text: String) {
        switch TranslationLanguageDetector.target(for: text) {
        case .english:
            targetLanguage = .english
        case .simplifiedChinese:
            targetLanguage = .simplifiedChinese
        case nil:
            break
        }
    }

    private enum TranslationLanguage: String, CaseIterable, Identifiable {
        case simplifiedChinese
        case english
        case japanese
        case korean
        case spanish

        var id: String { rawValue }

        var title: String {
            switch self {
            case .simplifiedChinese: "简体中文"
            case .english: "English"
            case .japanese: "日本語"
            case .korean: "한국어"
            case .spanish: "Español"
            }
        }

        var promptName: String {
            switch self {
            case .simplifiedChinese: "简体中文"
            case .english: "英语"
            case .japanese: "日语"
            case .korean: "韩语"
            case .spanish: "西班牙语"
            }
        }
    }
}

struct CodePluginView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @State private var input = "Luma 原生工具箱"
    @State private var output = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: $input)
                .font(.system(size: 13, design: .monospaced))
                .focused($isInputFocused)
                .padding(10)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            TextEditor(text: $output)
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .background(Color.cyan.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.cyan.opacity(0.22)))
            HStack(spacing: 8) {
                Button("Base64 编码") { output = CodeTool.base64Encode(input) }
                    .buttonStyle(LumaTextButtonStyle(height: 28))
                Button("Base64 解码") { output = CodeTool.base64Decode(input) ?? "无法解码" }
                    .buttonStyle(LumaTextButtonStyle(height: 28))
                Button("URL 编码") { output = CodeTool.urlEncode(input) }
                    .buttonStyle(LumaTextButtonStyle(height: 28))
                Button("URL 解码") { output = CodeTool.urlDecode(input) }
                    .buttonStyle(LumaTextButtonStyle(height: 28))
                Button("SHA-256") { output = CodeTool.sha256(input) }
                    .buttonStyle(LumaTextButtonStyle(height: 28))
                Spacer()
                Button("复制") { clipboard.copy(output) }
                    .buttonStyle(LumaTextButtonStyle(height: 28))
                    .disabled(output.isEmpty)
            }
            .controlSize(.small)
        }
        .padding(24)
        .onAppear { DispatchQueue.main.async { isInputFocused = true } }
    }
}
