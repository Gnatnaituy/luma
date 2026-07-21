import AppKit
import SwiftUI

#if canImport(Translation)
import Translation
#endif

struct PluginDetailView: View {
    let plugin: Plugin
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var stocks: StockStore
    @ObservedObject var translationSettings: TranslationSettings
    let pasteClipboardEntry: (ClipboardEntry) -> Void

    @ViewBuilder
    var body: some View {
        switch plugin {
        case .clipboard: ClipboardPluginView(clipboard: clipboard, onPaste: pasteClipboardEntry)
        case .calculator: CalculatorPluginView(clipboard: clipboard)
        case .json: JSONPluginView(clipboard: clipboard)
        case .password: PasswordPluginView(clipboard: clipboard)
        case .translate: TranslationPluginView(clipboard: clipboard, settings: translationSettings)
        case .code: CodePluginView(clipboard: clipboard)
        case .stocks: StocksPluginView(store: stocks)
        }
    }
}

struct ClipboardPluginView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    let onPaste: (ClipboardEntry) -> Void
    @State private var filter: ClipboardFilter

    init(
        clipboard: ClipboardMonitor,
        initialFilter: ClipboardFilter = .all,
        onPaste: @escaping (ClipboardEntry) -> Void = { _ in }
    ) {
        self.clipboard = clipboard
        self.onPaste = onPaste
        _filter = State(initialValue: initialFilter)
    }

    private var visibleEntries: [ClipboardEntry] {
        clipboard.filteredEntries(filter)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("最近 \(clipboard.entries.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空未收藏", role: .destructive) { clipboard.clearHistory() }
                    .buttonStyle(LumaTextButtonStyle(emphasis: .destructive, height: 28))
                    .disabled(!clipboard.entries.contains { !$0.isFavorite })
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ClipboardFilter.allCases) { item in
                        Button { filter = item } label: {
                            Text(item.title)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(filter == item ? Color.accentColor : Color.primary.opacity(0.06), in: Capsule())
                                .foregroundStyle(filter == item ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

            if clipboard.entries.isEmpty {
                ContentUnavailableView("还没有剪贴板记录", systemImage: "clipboard", description: Text("复制文本、图片、文件或链接后会自动持久化到本机"))
            } else if visibleEntries.isEmpty {
                ContentUnavailableView("该分类暂无记录", systemImage: "line.3.horizontal.decrease.circle", description: Text("切换到其他类型查看剪贴板历史"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleEntries) { entry in
                            ClipboardEntryRow(entry: entry, clipboard: clipboard, onPaste: onPaste)
                                .padding(.horizontal, 24)
                            Divider().padding(.horizontal, 24)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    @ObservedObject var clipboard: ClipboardMonitor
    let onPaste: (ClipboardEntry) -> Void
    @State private var isImageExpanded: Bool

    init(
        entry: ClipboardEntry,
        clipboard: ClipboardMonitor,
        initiallyExpanded: Bool = false,
        onPaste: @escaping (ClipboardEntry) -> Void = { _ in }
    ) {
        self.entry = entry
        self.clipboard = clipboard
        self.onPaste = onPaste
        _isImageExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    preview
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.title)
                            .font(.system(.body, design: .rounded))
                            .lineLimit(entry.kind == .image ? 1 : 3)
                        HStack(spacing: 6) {
                            Label(entry.kind.title, systemImage: entry.kind.symbol)
                            Text("·")
                            Text(entry.copiedAt.formatted(.dateTime.year().month().day().hour().minute()))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded { onPaste(entry) }
                )

                actionButtons
            }

            if let storedImage = imagePayload {
                if isImageExpanded, let image = storedImage.makeImage() {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isImageExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isImageExpanded ? "chevron.up" : "chevron.down")
                        Text(isImageExpanded ? "收起图片" : "展开图片")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isImageExpanded ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(LumaTextButtonStyle(height: 30))
                .help(isImageExpanded ? "收起图片" : "展开图片")
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if entry.kind == .link || entry.kind == .file {
                Button { openEntry() } label: {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(LumaIconButtonStyle())
                .help("打开")
            }

            Button { clipboard.toggleFavorite(entry) } label: {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(entry.isFavorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(LumaIconButtonStyle())
            .help(entry.isFavorite ? "取消收藏" : "收藏")

            Button { clipboard.copy(entry) } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(LumaIconButtonStyle())
            .help("复制")

            Button(role: .destructive) { clipboard.remove(entry) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(LumaIconButtonStyle())
            .help("删除")
        }
        .frame(height: 28, alignment: .top)
        .fixedSize()
    }

    private var imagePayload: ClipboardImage? {
        guard case .image(let storedImage) = entry.payload else { return nil }
        return storedImage
    }

    @ViewBuilder
    private var preview: some View {
        switch entry.payload {
        case .image(let storedImage):
            if let image = storedImage.makeImage() {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    Button { openImageInPreview(storedImage) } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(LumaIconButtonStyle())
                    .padding(4)
                    .help("使用 macOS Preview 查看")
                    .accessibilityLabel("使用 macOS Preview 查看")
                }
                .frame(width: 72, height: 56)
            }
        default:
            Image(systemName: entry.kind.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.indigo)
                .frame(width: 34, height: 34)
                .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func openEntry() {
        switch entry.payload {
        case .link(let url): NSWorkspace.shared.open(url)
        case .files(let urls): NSWorkspace.shared.activateFileViewerSelecting(urls)
        default: break
        }
    }

    private func openImageInPreview(_ storedImage: ClipboardImage) {
        guard let url = previewURL(for: storedImage) else { return }
        guard let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") else {
            NSWorkspace.shared.open(url)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: preview,
            configuration: configuration
        ) { _, error in
            if let error { NSLog("Luma Preview open failed: %@", error.localizedDescription) }
        }
    }

    private func previewURL(for storedImage: ClipboardImage) -> URL? {
        if let fileURL = storedImage.fileURL { return fileURL }
        guard let image = storedImage.makeImage(),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaPreview", isDirectory: true)
        let destination = directory.appendingPathComponent(entry.id.uuidString + ".png")
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try png.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }
}

private struct CalculatorPluginView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @State private var expression = "(18 + 6) * 3 / 2"

    private var result: Result<Double, Error> {
        Result { try ExpressionEvaluator.evaluate(expression) }
    }

    var body: some View {
        Form {
            Section("表达式") {
                TextField("例如：sqrt(81) + 2^3", text: $expression)
                    .font(.system(size: 22, design: .monospaced))
                    .textFieldStyle(LumaTextFieldStyle(height: 38))
            }
            Section("结果") {
                switch result {
                case .success(let value):
                    HStack {
                        Text(ExpressionEvaluator.display(value))
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .textSelection(.enabled)
                        Spacer()
                        Button("复制") { clipboard.copy(ExpressionEvaluator.display(value)) }
                            .buttonStyle(LumaTextButtonStyle())
                    }
                case .failure(let error):
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Text("支持 + − × ÷ % ^、括号，以及 sqrt / sin / cos / tan / abs / log / ln。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct JSONPluginView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @State private var input = "{\"name\":\"Luma\",\"native\":true,\"plugins\":[\"clipboard\",\"calc\",\"json\"]}"
    @State private var message = ""

    var body: some View {
        VStack(spacing: 12) {
            JSONSyntaxEditor(text: $input)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))

            HStack {
                Button("格式化") { transform(pretty: true) }
                    .buttonStyle(LumaTextButtonStyle(emphasis: .primary))
                Button("压缩") { transform(pretty: false) }
                    .buttonStyle(LumaTextButtonStyle())
                Button("复制") { clipboard.copy(input) }
                    .buttonStyle(LumaTextButtonStyle())
                Spacer()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.hasPrefix("✓") ? .green : .orange)
            }
        }
        .padding(24)
    }

    private func transform(pretty: Bool) {
        do {
            input = try JSONTool.format(input, pretty: pretty)
            message = "✓ JSON 有效"
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct PasswordPluginView: View {
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

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        Self.makeScrollView(text: text, delegate: context.coordinator)
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

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private struct TranslationPluginView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var settings: TranslationSettings
    @State private var input = "Hello, welcome to Luma."
    @State private var output = ""
    @State private var isPresented = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var targetLanguage = TranslationLanguage.simplifiedChinese

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
            BorderlessTextEditor(text: $input)
                .padding(10)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))

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

                    Button {
                        translateWithAI()
                    } label: {
                        if isLoading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("翻译中")
                            }
                        } else {
                            Text("使用 AI 翻译")
                        }
                    }
                    .buttonStyle(LumaTextButtonStyle(emphasis: .primary))
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || settings.requestTarget == nil
                              || isLoading)
                } else {
                    Button("调用系统翻译") {
                        errorMessage = nil
                        isPresented = true
                    }
                    .buttonStyle(LumaTextButtonStyle(emphasis: .primary))
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Button("复制结果") { clipboard.copy(output) }
                    .buttonStyle(LumaTextButtonStyle())
                    .disabled(output.isEmpty)
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

private struct CodePluginView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @State private var input = "Luma 原生工具箱"
    @State private var output = ""

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: $input)
                .font(.system(size: 13, design: .monospaced))
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
    }
}

private struct StocksPluginView: View {
    @ObservedObject var store: StockStore
    @State private var query = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    TextField("AAPL / 600115.SS", text: $query)
                        .textFieldStyle(LumaTextFieldStyle())
                        .onSubmit { performQuery() }
                    Button { performQuery() } label: {
                        if store.isLoading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "plus") }
                    }
                    .buttonStyle(LumaIconButtonStyle())
                    .disabled(store.isBusy || query.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !store.records.isEmpty {
                        Button {
                            Task { await store.refreshAll() }
                        } label: {
                            if store.isRefreshingAll {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(LumaIconButtonStyle())
                        .disabled(store.isBusy)
                        .help(store.isRefreshingAll ? "正在全部刷新" : "全部刷新")
                    }
                }
                .padding(12)

                if !store.errorMessage.isEmpty {
                    Text(store.errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                if store.records.isEmpty {
                    ContentUnavailableView("添加股票", systemImage: "plus.circle", description: Text("只查询并保存你输入的股票代码"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(store.records) { stock in
                                Button {
                                    store.select(stock)
                                } label: {
                                    StockListRow(stock: stock, colorTheme: store.colorTheme)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                        .background(
                                            store.selectedSymbol == stock.symbol ? Color.accentColor.opacity(0.14) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("移除记录", role: .destructive) { store.remove(stock) }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                }
            }
            .frame(width: 218)
            .background(Color.primary.opacity(0.025))

            Divider()

            if let stock = store.selected {
                StockDetailView(
                    stock: stock,
                    isLoading: store.isBusy,
                    colorTheme: store.colorTheme,
                    dataSource: store.dataSource
                ) {
                    Task { await store.refreshSelected() }
                }
                .id(stock.symbol)
            } else {
                ContentUnavailableView("还没有行情记录", systemImage: "chart.line.uptrend.xyaxis", description: Text("支持 A 股、港股和美股代码"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func performQuery() {
        let value = query
        Task {
            await store.query(value)
            if store.errorMessage.isEmpty { query = "" }
        }
    }
}

private struct StockListRow: View {
    let stock: StockSnapshot
    let colorTheme: StockColorTheme

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(stock.symbol).font(.system(.body, design: .rounded).weight(.semibold))
                Text(stock.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(stock.price.formatted(.number.precision(.fractionLength(2...3))))
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                Text(String(format: "%+.2f%%", stock.changePercent))
                    .font(.caption2)
                    .foregroundStyle(colorTheme.color(isRising: stock.isRising))
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct StockDetailView: View {
    let stock: StockSnapshot
    let isLoading: Bool
    let colorTheme: StockColorTheme
    let dataSource: StockDataSource
    let refresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stock.symbol).font(.title2.bold())
                        Text(stock.name).font(.caption).foregroundStyle(.secondary)
                        Text("\(stock.marketName) · \(stock.currency)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(stock.price.formatted(.number.precision(.fractionLength(2...3))))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(String(format: "%+.2f  %+.2f%%", stock.change, stock.changePercent))
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(colorTheme.color(isRising: stock.isRising))
                    }
                }

                StockChart(points: stock.points, rising: stock.isRising, colorTheme: colorTheme)
                    .frame(height: 150)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StockMetric(title: "今开", value: stock.open)
                    StockMetric(title: "最高", value: stock.high)
                    StockMetric(title: "最低", value: stock.low)
                    StockMetric(title: "昨收", value: stock.previousClose)
                    StockMetric(title: "成交量", text: stock.volume.formatted(.number.notation(.compactName)))
                    StockMetric(title: "数据时间", text: stock.quoteTime.isEmpty ? "—" : stock.quoteTime)
                }

                HStack {
                    Text("\(dataSource.title) · 仅新增和手动刷新时请求")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: refresh) { Label("刷新", systemImage: "arrow.clockwise") }
                        .buttonStyle(LumaTextButtonStyle())
                        .disabled(isLoading)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StockMetric: View {
    let title: String
    let text: String

    init(title: String, value: Double) {
        self.title = title
        self.text = value.formatted(.number.precision(.fractionLength(2...3)))
    }

    init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(text).font(.system(.caption, design: .monospaced).weight(.medium)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StockChart: View {
    let points: [StockPoint]
    let rising: Bool
    let colorTheme: StockColorTheme

    var body: some View {
        GeometryReader { geometry in
            if points.count < 2 {
                ContentUnavailableView("暂无走势数据", systemImage: "chart.xyaxis.line")
            } else {
                let values = points.map(\.close)
                let minimum = values.min() ?? 0
                let maximum = values.max() ?? 1
                let spread = max(maximum - minimum, 0.0001)
                let path = Path { path in
                    for (index, point) in points.enumerated() {
                        let x = (geometry.size.width - 20) * CGFloat(index) / CGFloat(points.count - 1) + 10
                        let ratio = (point.close - minimum) / spread
                        let y = geometry.size.height - 10 - (geometry.size.height - 20) * CGFloat(ratio)
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035))
                    path.stroke(
                        colorTheme.color(isRising: rising),
                        style: StrokeStyle(lineWidth: 2, lineJoin: .round)
                    )
                }
            }
        }
    }
}
