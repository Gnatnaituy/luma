import AppKit
import SwiftUI

#if canImport(Translation)
import Translation
#endif

struct PluginDetailView: View {
    let plugin: Plugin
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var stocks: StockStore
    @ObservedObject var weather: WeatherStore
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
        case .weather: WeatherPluginView(store: weather)
        }
    }
}

struct ClipboardPluginView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    let onPaste: (ClipboardEntry) -> Void
    @State private var filter: ClipboardFilter
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedEntryID: UUID?
    @State private var keyboardMonitor: Any?
    @State private var navigationDirection = 0
    @State private var navigationStepsSinceScroll = 0
    @State private var scrollRequest: ClipboardScrollRequest?

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
        clipboard.filteredEntries(filter, matching: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("搜索剪贴板内容", text: $searchText)
                .textFieldStyle(LumaTextFieldStyle(height: 32))
                .focused($isSearchFocused)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            HStack(spacing: 10) {
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
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("最近 \(clipboard.entries.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()

                Button("清空未收藏", role: .destructive) { clipboard.clearHistory() }
                    .buttonStyle(LumaTextButtonStyle(emphasis: .destructive, height: 28))
                    .disabled(!clipboard.entries.contains { !$0.isFavorite })
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

            if clipboard.entries.isEmpty {
                ContentUnavailableView("还没有剪贴板记录", systemImage: "clipboard", description: Text("复制文本、图片、文件或链接后会自动持久化到本机"))
            } else if visibleEntries.isEmpty {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("该分类暂无记录", systemImage: "line.3.horizontal.decrease.circle", description: Text("切换到其他类型查看剪贴板历史"))
                } else {
                    ContentUnavailableView("没有匹配的剪贴板记录", systemImage: "magnifyingglass", description: Text("尝试其他关键词或切换内容类型"))
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleEntries) { entry in
                                ClipboardEntryRow(entry: entry, clipboard: clipboard, onPaste: onPaste)
                                    .padding(.horizontal, 24)
                                    .background {
                                        if selectedEntryID == entry.id {
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(Color.accentColor.opacity(0.09))
                                                .padding(.horizontal, 18)
                                        }
                                    }
                                    .id(entry.id)
                                Divider().padding(.horizontal, 24)
                            }
                        }
                    }
                    .onChange(of: scrollRequest) { _, request in
                        guard let request else { return }
                        proxy.scrollTo(
                            request.entryID,
                            anchor: request.edge == .top ? .top : .bottom
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            ensureValidSelection()
            installKeyboardMonitor()
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onDisappear(perform: removeKeyboardMonitor)
        .onChange(of: visibleEntries.map(\.id)) { _, _ in
            ensureValidSelection(scrollToTop: true)
        }
    }

    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let commandModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            guard event.modifierFlags.intersection(commandModifiers).isEmpty else { return event }
            switch event.keyCode {
            case 126:
                moveSelection(-1)
            case 125:
                moveSelection(1)
            case 123:
                moveFilter(-1)
            case 124:
                moveFilter(1)
            case 36, 76:
                pasteSelection()
            default:
                return event
            }
            return nil
        }
    }

    private func removeKeyboardMonitor() {
        guard let keyboardMonitor else { return }
        NSEvent.removeMonitor(keyboardMonitor)
        self.keyboardMonitor = nil
    }

    private func ensureValidSelection(scrollToTop: Bool = false) {
        guard !visibleEntries.contains(where: { $0.id == selectedEntryID }) else { return }
        selectedEntryID = visibleEntries.first?.id
        navigationDirection = 0
        navigationStepsSinceScroll = 0
        if scrollToTop, let selectedEntryID {
            requestScroll(to: selectedEntryID, edge: .top)
        }
    }

    private func moveSelection(_ delta: Int) {
        let entries = visibleEntries
        guard !entries.isEmpty else {
            selectedEntryID = nil
            navigationDirection = 0
            navigationStepsSinceScroll = 0
            return
        }
        let previousIndex = selectedEntryID.flatMap { selectedID in
            entries.firstIndex(where: { $0.id == selectedID })
        }
        let nextID = ClipboardKeyboardNavigation.movedSelection(
            current: selectedEntryID,
            entries: entries,
            delta: delta
        )
        selectedEntryID = nextID

        guard let nextID,
              let nextIndex = entries.firstIndex(where: { $0.id == nextID }) else { return }
        let direction = delta.signum()
        if navigationDirection != direction {
            navigationDirection = direction
            navigationStepsSinceScroll = 0
        }
        navigationStepsSinceScroll += 1

        let wrapped = previousIndex.map { index in
            direction > 0 ? nextIndex < index : nextIndex > index
        } ?? false
        if wrapped {
            requestScroll(to: nextID, edge: direction > 0 ? .top : .bottom)
            navigationStepsSinceScroll = 0
            return
        }

        guard navigationStepsSinceScroll >= 3 else { return }
        let lookAheadIndex = min(max(nextIndex + direction * 2, 0), entries.count - 1)
        requestScroll(
            to: entries[lookAheadIndex].id,
            edge: direction > 0 ? .bottom : .top
        )
        navigationStepsSinceScroll = 0
    }

    private func moveFilter(_ delta: Int) {
        filter = ClipboardKeyboardNavigation.movedFilter(current: filter, delta: delta)
        selectedEntryID = clipboard.filteredEntries(filter, matching: searchText).first?.id
        navigationDirection = 0
        navigationStepsSinceScroll = 0
        if let selectedEntryID {
            requestScroll(to: selectedEntryID, edge: .top)
        }
    }

    private func pasteSelection() {
        guard let selectedEntryID,
              let entry = visibleEntries.first(where: { $0.id == selectedEntryID }) else { return }
        onPaste(entry)
    }

    private func requestScroll(to entryID: UUID, edge: ClipboardScrollEdge) {
        scrollRequest = ClipboardScrollRequest(entryID: entryID, edge: edge)
    }

}

private enum ClipboardScrollEdge: Equatable {
    case top
    case bottom
}

private struct ClipboardScrollRequest: Equatable {
    let id = UUID()
    let entryID: UUID
    let edge: ClipboardScrollEdge
}

enum ClipboardKeyboardNavigation {
    static func movedSelection(
        current: UUID?,
        entries: [ClipboardEntry],
        delta: Int
    ) -> UUID? {
        guard !entries.isEmpty else { return nil }
        guard let current,
              let index = entries.firstIndex(where: { $0.id == current }) else {
            return entries.first?.id
        }
        let nextIndex = (index + delta % entries.count + entries.count) % entries.count
        return entries[nextIndex].id
    }

    static func movedFilter(current: ClipboardFilter, delta: Int) -> ClipboardFilter {
        let filters = ClipboardFilter.allCases
        guard let index = filters.firstIndex(of: current), !filters.isEmpty else { return .all }
        let nextIndex = (index + delta % filters.count + filters.count) % filters.count
        return filters[nextIndex]
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
    @FocusState private var isExpressionFocused: Bool

    private var result: Result<Double, Error> {
        Result { try ExpressionEvaluator.evaluate(expression) }
    }

    var body: some View {
        Form {
            Section("表达式") {
                TextField("例如：sqrt(81) + 2^3", text: $expression)
                    .font(.system(size: 22, design: .monospaced))
                    .textFieldStyle(LumaTextFieldStyle(height: 38))
                    .focused($isExpressionFocused)
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
        .onAppear { DispatchQueue.main.async { isExpressionFocused = true } }
    }
}

private struct JSONPluginView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @State private var input = "{\"name\":\"Luma\",\"native\":true,\"plugins\":[\"clipboard\",\"calc\",\"json\"]}"
    @State private var message = ""

    var body: some View {
        VStack(spacing: 12) {
            JSONSyntaxEditor(text: $input, autofocus: true)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))

            HStack {
                Button("格式化") { transform(pretty: true) }
                    .buttonStyle(LumaTextButtonStyle(emphasis: .primary))
                Button("压缩") { transform(pretty: false) }
                    .buttonStyle(LumaTextButtonStyle())
                Button("转义") { escape() }
                    .buttonStyle(LumaTextButtonStyle())
                Button("去转义") { unescape() }
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

    private func escape() {
        do {
            input = try JSONTool.escape(input)
            message = "✓ 已转义"
        } catch {
            message = error.localizedDescription
        }
    }

    private func unescape() {
        do {
            input = try JSONTool.unescape(input)
            message = "✓ 已去转义"
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
    let autofocus: Bool

    init(text: Binding<String>, autofocus: Bool = false) {
        _text = text
        self.autofocus = autofocus
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
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

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
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
            BorderlessTextEditor(text: $input, autofocus: true)
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
                        translateWithAI()
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
                        errorMessage = nil
                        isPresented = true
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

private struct CodePluginView: View {
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

private struct WeatherPluginView: View {
    @ObservedObject var store: WeatherStore
    @State private var query = ""
    @State private var suggestions: [WeatherLocation] = []
    @State private var selectedSuggestionID: Int?
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    TextField("上海 / Tokyo / 10001", text: $query)
                        .textFieldStyle(LumaTextFieldStyle())
                        .focused($isQueryFocused)
                        .onSubmit(performQuery)
                        .onMoveCommand(perform: performSuggestionMove)

                    Button(action: performQuery) {
                        if store.isLoading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "plus") }
                    }
                    .buttonStyle(LumaIconButtonStyle())
                    .disabled(store.isBusy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("添加地点")

                    if !store.records.isEmpty {
                        Button { Task { await store.refreshAll() } } label: {
                            if store.isRefreshingAll { ProgressView().controlSize(.small) }
                            else { Image(systemName: "arrow.clockwise") }
                        }
                        .buttonStyle(LumaIconButtonStyle())
                        .disabled(store.isBusy)
                        .help(store.isRefreshingAll ? "正在全部刷新" : "全部刷新")
                    }
                }
                .padding(12)
                .overlay(alignment: .topLeading) {
                    if isQueryFocused, !suggestions.isEmpty {
                        weatherSuggestionPanel
                            .padding(.horizontal, 12)
                            .offset(y: 48)
                    }
                }
                .zIndex(20)

                if !store.errorMessage.isEmpty {
                    Text(store.errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                if store.records.isEmpty {
                    ContentUnavailableView(
                        "添加地点",
                        systemImage: "location.badge.plus",
                        description: Text("输入城市、地区或邮政编码")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(store.records) { snapshot in
                                Button { store.select(snapshot) } label: {
                                    WeatherListRow(snapshot: snapshot)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                        .background(
                                            store.selectedLocationID == snapshot.id
                                                ? Color.accentColor.opacity(0.14)
                                                : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("移除地点", role: .destructive) { store.remove(snapshot) }
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

            if let snapshot = store.selected {
                WeatherDetailView(snapshot: snapshot, dataSource: store.dataSource, isLoading: store.isBusy) {
                    Task { await store.refreshSelected() }
                }
                .id(snapshot.id)
            } else {
                ContentUnavailableView(
                    "还没有天气记录",
                    systemImage: "cloud.sun",
                    description: Text("从左侧添加一个地点开始")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { DispatchQueue.main.async { isQueryFocused = true } }
        .task(id: query) { await updateSuggestions() }
    }

    private func performQuery() {
        if let selected = suggestions.first(where: { $0.id == selectedSuggestionID }) ?? suggestions.first {
            add(selected)
            return
        }
        let value = query
        Task {
            await store.add(value)
            if store.errorMessage.isEmpty { query = "" }
        }
    }

    private var weatherSuggestionPanel: some View {
        VStack(spacing: 2) {
            ForEach(suggestions) { location in
                Button { add(location) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.blue)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(location.subtitle.isEmpty ? location.timezone : location.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(
                        selectedSuggestionID == location.id ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.12)))
    }

    private func updateSuggestions() async {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else {
            suggestions = []
            selectedSuggestionID = nil
            return
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled else { return }
        do {
            let results = try await OpenMeteoWeatherService().searchLocations(value)
            guard !Task.isCancelled else { return }
            suggestions = results
            selectedSuggestionID = results.first?.id
        } catch {
            guard !Task.isCancelled else { return }
            suggestions = []
            selectedSuggestionID = nil
        }
    }

    private func performSuggestionMove(_ direction: MoveCommandDirection) {
        guard !suggestions.isEmpty, direction == .up || direction == .down else { return }
        let current = suggestions.firstIndex { $0.id == selectedSuggestionID } ?? 0
        let delta = direction == .down ? 1 : -1
        selectedSuggestionID = suggestions[(current + delta + suggestions.count) % suggestions.count].id
    }

    private func add(_ location: WeatherLocation) {
        suggestions = []
        selectedSuggestionID = nil
        query = ""
        Task { await store.add(location) }
    }
}

private struct WeatherListRow: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.location.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Text(snapshot.location.subtitle.isEmpty ? snapshot.location.timezone : snapshot.location.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: WeatherCondition.symbol(
                        for: snapshot.current.weatherCode,
                        isDay: snapshot.current.isDay
                    ))
                    .foregroundStyle(.blue)
                    Text(temperature(snapshot.current.temperature))
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                }
                Text(WeatherCondition.title(for: snapshot.current.weatherCode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func temperature(_ value: Double) -> String { String(format: "%.0f°", value) }
}

private struct WeatherDetailView: View {
    let snapshot: WeatherSnapshot
    let dataSource: WeatherDataSource
    let isLoading: Bool
    let refresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                currentHeader
                metricGrid
                hourlyForecast
                dailyForecast
                footer
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.location.name).font(.title2.bold())
                Text(snapshot.location.subtitle.isEmpty ? snapshot.location.timezone : snapshot.location.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(WeatherCondition.title(for: snapshot.current.weatherCode))
                    .font(.headline)
            }
            Spacer()
            Image(systemName: WeatherCondition.symbol(
                for: snapshot.current.weatherCode,
                isDay: snapshot.current.isDay
            ))
            .symbolRenderingMode(.multicolor)
            .font(.system(size: 42, weight: .medium))
            Text(String(format: "%.0f°", snapshot.current.temperature))
                .font(.system(size: 42, weight: .bold, design: .rounded))
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.10), Color.cyan.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var metricGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            WeatherMetric(title: "体感", value: String(format: "%.0f°", snapshot.current.apparentTemperature), symbol: "thermometer.medium")
            WeatherMetric(title: "湿度", value: "\(snapshot.current.humidity)%", symbol: "humidity.fill")
            WeatherMetric(title: "降水", value: String(format: "%.1f mm", snapshot.current.precipitation), symbol: "drop.fill")
            WeatherMetric(
                title: "风",
                value: "\(WeatherCondition.windDirection(snapshot.current.windDirection)) \(String(format: "%.0f", snapshot.current.windSpeed)) km/h",
                symbol: "wind"
            )
        }
    }

    private var hourlyForecast: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("未来 24 小时").font(.subheadline.weight(.semibold))
            if snapshot.hourly.isEmpty {
                Label("当前数据源暂无逐小时预报", systemImage: "clock.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(snapshot.hourly) { hour in
                            VStack(spacing: 7) {
                                Text(hourLabel(hour.time))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Image(systemName: WeatherCondition.symbol(for: hour.weatherCode))
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 18))
                                    .frame(height: 20)
                                Text(String(format: "%.0f°", hour.temperature))
                                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                                Label(probabilityText(hour.precipitationProbability), systemImage: "drop.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.blue)
                            }
                            .frame(width: 58)
                            .padding(.vertical, 9)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
        }
    }

    private var dailyForecast: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("未来 7 天").font(.subheadline.weight(.semibold))
            ForEach(Array(snapshot.daily.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 10) {
                    Text(index == 0 ? "今天" : weekday(day.date))
                        .font(.caption.weight(.medium))
                        .frame(width: 38, alignment: .leading)
                    Image(systemName: WeatherCondition.symbol(for: day.weatherCode))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 22)
                    Text(WeatherCondition.title(for: day.weatherCode))
                        .font(.caption)
                        .frame(width: 62, alignment: .leading)
                    Label(probabilityText(day.precipitationProbability), systemImage: "drop.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .frame(width: 52, alignment: .leading)
                    Spacer()
                    Text("\(String(format: "%.0f°", day.minimumTemperature))  /  \(String(format: "%.0f°", day.maximumTemperature))")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(index.isMultiple(of: 2) ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                Text("本地刷新 \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                Spacer()
                Text(dataSource.title)
                Button(action: refresh) {
                    if isLoading { ProgressView().controlSize(.small) }
                    else { Label("刷新", systemImage: "arrow.clockwise") }
                }
                .buttonStyle(LumaTextButtonStyle())
                .disabled(isLoading)
            }
            Text("天气数据仅在新增地点或手动刷新时请求。")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func hourLabel(_ value: String) -> String {
        guard let marker = value.lastIndex(of: "T") else { return value }
        return String(value[value.index(after: marker)...].prefix(5))
    }

    private func weekday(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return String(value.suffix(5)) }
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func probabilityText(_ value: Int?) -> String {
        value.map { "\($0)%" } ?? "—"
    }
}

private struct WeatherMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StocksPluginView: View {
    @ObservedObject var store: StockStore
    @State private var query = ""
    @State private var suggestions: [StockSearchResult] = []
    @State private var selectedSuggestionID: String?
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    TextField("代码或名称", text: $query)
                        .textFieldStyle(LumaTextFieldStyle())
                        .focused($isQueryFocused)
                        .onSubmit { performQuery() }
                        .onMoveCommand(perform: performSuggestionMove)
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
                .overlay(alignment: .topLeading) {
                    if isQueryFocused, !suggestions.isEmpty {
                        stockSuggestionPanel
                            .padding(.horizontal, 12)
                            .offset(y: 48)
                    }
                }
                .zIndex(20)

                if !store.errorMessage.isEmpty {
                    Text(store.errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                if store.records.isEmpty {
                    ContentUnavailableView("添加股票", systemImage: "plus.circle", description: Text("输入股票代码或名称搜索"))
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
                    store: store,
                    colorTheme: store.colorTheme
                ) {
                    Task {
                        await store.refreshSelected()
                        if let refreshed = store.selected {
                            await store.loadChart(for: refreshed, period: store.chartPeriod, force: true)
                        }
                    }
                }
                .id(stock.symbol)
            } else {
                ContentUnavailableView("还没有行情记录", systemImage: "chart.line.uptrend.xyaxis", description: Text("支持 A 股、港股和美股代码"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { DispatchQueue.main.async { isQueryFocused = true } }
        .task(id: query) { await updateSuggestions() }
    }

    private func performQuery() {
        if let selected = suggestions.first(where: { $0.id == selectedSuggestionID }) ?? suggestions.first {
            add(selected)
            return
        }
        let value = query
        Task {
            await store.query(value)
            if store.errorMessage.isEmpty { query = "" }
        }
    }

    private var stockSuggestionPanel: some View {
        VStack(spacing: 2) {
            ForEach(suggestions) { suggestion in
                Button { add(suggestion) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(.orange)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.name).font(.caption.weight(.semibold)).lineLimit(1)
                            Text("\(suggestion.symbol) · \(suggestion.market)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(
                        selectedSuggestionID == suggestion.id ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.12)))
    }

    private func updateSuggestions() async {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            suggestions = []
            selectedSuggestionID = nil
            return
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled else { return }
        do {
            let results = try await EastMoneyStockSearchService().search(value)
            guard !Task.isCancelled else { return }
            suggestions = results
            selectedSuggestionID = results.first?.id
        } catch {
            guard !Task.isCancelled else { return }
            suggestions = []
            selectedSuggestionID = nil
        }
    }

    private func performSuggestionMove(_ direction: MoveCommandDirection) {
        guard !suggestions.isEmpty, direction == .up || direction == .down else { return }
        let current = suggestions.firstIndex { $0.id == selectedSuggestionID } ?? 0
        let delta = direction == .down ? 1 : -1
        selectedSuggestionID = suggestions[(current + delta + suggestions.count) % suggestions.count].id
    }

    private func add(_ suggestion: StockSearchResult) {
        suggestions = []
        selectedSuggestionID = nil
        query = ""
        Task { await store.query(suggestion.symbol) }
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
    @ObservedObject var store: StockStore
    let colorTheme: StockColorTheme
    let refresh: () -> Void
    @State private var selectedPeriod: StockChartPeriod = .daily

    private var points: [StockPoint] {
        if store.chartPeriod == selectedPeriod, !store.chartPoints.isEmpty { return store.chartPoints }
        return selectedPeriod == .daily ? stock.points : []
    }

    private var periodChangePercent: Double? {
        guard let first = points.first?.close, first != 0, let last = points.last?.close else { return nil }
        return (last - first) / first * 100
    }

    private var periodHigh: Double? {
        points.compactMap { $0.high ?? $0.close }.max()
    }

    private var periodLow: Double? {
        points.compactMap { $0.low ?? $0.close }.min()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(stock.name).font(.title2.bold())
                        HStack(spacing: 6) {
                            Text(stock.symbol)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                            Text(stock.marketName)
                            Text(stock.currency)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("\(selectedPeriod.title)走势").font(.subheadline.weight(.semibold))
                        Text("\(points.count) 个数据点")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let change = periodChangePercent {
                            Text("区间 \(String(format: "%+.2f%%", change))")
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(colorTheme.color(isRising: change >= 0))
                        }
                    }

                    StockPeriodSelector(selection: $selectedPeriod)

                    ZStack {
                        StockChart(
                            points: points,
                            period: selectedPeriod,
                            rising: (periodChangePercent ?? stock.changePercent) >= 0,
                            colorTheme: colorTheme
                        )
                        .frame(height: 165)
                        if store.isLoadingChart {
                            ProgressView()
                                .controlSize(.small)
                                .padding(10)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    if !store.chartErrorMessage.isEmpty {
                        Text(store.chartErrorMessage)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if selectedPeriod == .intraday, !points.isEmpty {
                        HStack {
                            Text("09:15")
                            Spacer()
                            Text("11:30 / 13:00")
                            Spacer()
                            Text("15:30")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    } else if let first = points.first, let last = points.last {
                        HStack {
                            Text(chartDate(first.date))
                            Spacer()
                            if let low = periodLow, let high = periodHigh {
                                Text("低 \(formatPrice(low))  ·  高 \(formatPrice(high))")
                            }
                            Spacer()
                            Text(chartDate(last.date))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))

                StockDayRange(stock: stock, colorTheme: colorTheme)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    StockMetric(title: "今开", value: stock.open)
                    StockMetric(title: "最高", value: stock.high)
                    StockMetric(title: "最低", value: stock.low)
                    StockMetric(title: "昨收", value: stock.previousClose)
                    StockMetric(title: "成交量", text: stock.volume.formatted(.number.notation(.compactName)))
                    StockMetric(title: "振幅", text: String(format: "%.2f%%", stock.amplitudePercent))
                    StockMetric(title: "开盘涨跌", text: String(format: "%+.2f%%", stock.openChangePercent))
                    StockMetric(
                        title: "区间涨跌",
                        text: periodChangePercent.map { String(format: "%+.2f%%", $0) } ?? "—"
                    )
                }

                HStack(spacing: 8) {
                    Image(systemName: "clock")
                    Text(stock.quoteTime.isEmpty ? "行情时间 —" : "行情时间 \(stock.quoteTime)")
                    Text("·")
                    Text("本地刷新 \(stock.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    Spacer()
                    Text(store.dataSource.title)
                    Button(action: refresh) {
                        if store.isBusy || store.isLoadingChart {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(LumaTextButtonStyle())
                    .disabled(store.isBusy || store.isLoadingChart)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text("行情数据仅在新增股票或手动刷新时请求。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(stock.symbol):\(selectedPeriod.rawValue):\(store.dataSource.rawValue)") {
            await store.loadChart(for: stock, period: selectedPeriod)
        }
    }

    private func formatPrice(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2...3)))
    }

    private func chartDate(_ value: String) -> String {
        if selectedPeriod == .intraday { return String(value.suffix(4)) }
        if selectedPeriod == .fiveDay { return String(value.prefix(8)) }
        return String(value.prefix(10))
    }
}

private struct StockPeriodSelector: View {
    @Binding var selection: StockChartPeriod

    var body: some View {
        HStack(spacing: 4) {
            ForEach(StockChartPeriod.allCases) { period in
                Button {
                    selection = period
                } label: {
                    Text(period.title)
                        .font(.caption.weight(selection == period ? .semibold : .regular))
                        .foregroundStyle(selection == period ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(
                            selection == period ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct StockDayRange: View {
    let stock: StockSnapshot
    let colorTheme: StockColorTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("日内位置").font(.subheadline.weight(.semibold))
                Spacer()
                Text(stock.dayPosition.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(colorTheme.color(isRising: stock.isRising))
            }
            GeometryReader { geometry in
                let position = stock.dayPosition ?? 0.5
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(colorTheme.color(isRising: stock.isRising).opacity(0.65))
                        .frame(width: max(8, width * position))
                    Circle()
                        .fill(colorTheme.color(isRising: stock.isRising))
                        .frame(width: 10, height: 10)
                        .offset(x: min(max(width * position - 5, 0), max(width - 10, 0)))
                }
            }
            .frame(height: 10)
            HStack {
                Text("最低 \(formatPrice(stock.low))")
                Spacer()
                Text("现价 \(formatPrice(stock.price))")
                Spacer()
                Text("最高 \(formatPrice(stock.high))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func formatPrice(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2...3)))
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
    let period: StockChartPeriod
    let rising: Bool
    let colorTheme: StockColorTheme

    var body: some View {
        GeometryReader { geometry in
            if points.count < 2 {
                ContentUnavailableView("暂无走势数据", systemImage: "chart.xyaxis.line")
            } else {
                let renderPoints = period.isCandlestick
                    ? points
                    : StockChartSampler.downsample(points, maximumCount: 360)
                let values = renderPoints.flatMap { point in
                    period.isCandlestick ? [point.high ?? point.close, point.low ?? point.close] : [point.close]
                }
                let minimum = values.min() ?? 0
                let maximum = values.max() ?? 1
                let spread = max(maximum - minimum, 0.0001)
                let leftInset: CGFloat = 10
                let rightInset: CGFloat = 54
                let topInset: CGFloat = 12
                let bottomInset: CGFloat = 12
                let plotWidth = max(1, geometry.size.width - leftInset - rightInset)
                let plotHeight = max(1, geometry.size.height - topInset - bottomInset)
                let xPosition: (Int, StockPoint) -> CGFloat = { index, point in
                    if period == .intraday, let ratio = StockTradingTimeline.ratio(for: point.date) {
                        return leftInset + plotWidth * CGFloat(ratio)
                    }
                    return plotWidth * CGFloat(index) / CGFloat(renderPoints.count - 1) + leftInset
                }
                let path = Path { path in
                    for (index, point) in renderPoints.enumerated() {
                        let x = xPosition(index, point)
                        let ratio = (point.close - minimum) / spread
                        let y = geometry.size.height - bottomInset - plotHeight * CGFloat(ratio)
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                let areaPath = Path { path in
                    let firstX = renderPoints.first.map { xPosition(0, $0) } ?? leftInset
                    path.move(to: CGPoint(x: firstX, y: geometry.size.height - bottomInset))
                    for (index, point) in renderPoints.enumerated() {
                        let x = xPosition(index, point)
                        let ratio = (point.close - minimum) / spread
                        let y = geometry.size.height - bottomInset - plotHeight * CGFloat(ratio)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    let lastIndex = renderPoints.count - 1
                    let lastX = renderPoints.last.map { xPosition(lastIndex, $0) } ?? leftInset
                    path.addLine(to: CGPoint(x: lastX, y: geometry.size.height - bottomInset))
                    path.closeSubpath()
                }
                let lineColor = colorTheme.color(isRising: rising)
                ZStack {
                    ForEach(0..<4, id: \.self) { index in
                        let ratio = Double(index) / 3
                        let y = topInset + plotHeight * CGFloat(index) / 3
                        Path { grid in
                            grid.move(to: CGPoint(x: leftInset, y: y))
                            grid.addLine(to: CGPoint(x: leftInset + plotWidth, y: y))
                        }
                        .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        Text(formatPrice(maximum - spread * ratio))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .position(x: geometry.size.width - rightInset / 2, y: y)
                    }
                    if period == .intraday {
                        ForEach(Array(StockTradingTimeline.gridRatios.enumerated()), id: \.offset) { _, ratio in
                            let x = leftInset + plotWidth * CGFloat(ratio)
                            Path { grid in
                                grid.move(to: CGPoint(x: x, y: topInset))
                                grid.addLine(to: CGPoint(x: x, y: geometry.size.height - bottomInset))
                            }
                            .stroke(Color.primary.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        }
                    }
                    if period.isCandlestick && renderPoints.allSatisfy(\.hasOHLC) {
                        ForEach(renderPoints.indices, id: \.self) { index in
                            let point = renderPoints[index]
                            let open = point.open ?? point.close
                            let high = point.high ?? point.close
                            let low = point.low ?? point.close
                            let x = xPosition(index, point)
                            let openY = geometry.size.height - bottomInset - plotHeight * CGFloat((open - minimum) / spread)
                            let closeY = geometry.size.height - bottomInset - plotHeight * CGFloat((point.close - minimum) / spread)
                            let highY = geometry.size.height - bottomInset - plotHeight * CGFloat((high - minimum) / spread)
                            let lowY = geometry.size.height - bottomInset - plotHeight * CGFloat((low - minimum) / spread)
                            let candleColor = colorTheme.color(isRising: point.close >= open)
                            let candleWidth = max(2, min(8, plotWidth / CGFloat(renderPoints.count) * 0.62))
                            Path { wick in
                                wick.move(to: CGPoint(x: x, y: highY))
                                wick.addLine(to: CGPoint(x: x, y: lowY))
                            }
                            .stroke(candleColor, lineWidth: 1)
                            Rectangle()
                                .fill(candleColor)
                                .frame(width: candleWidth, height: max(1.5, abs(closeY - openY)))
                                .position(x: x, y: (openY + closeY) / 2)
                        }
                    } else {
                        areaPath.fill(
                            LinearGradient(
                                colors: [lineColor.opacity(0.18), lineColor.opacity(0.015)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        path.stroke(
                            lineColor,
                            style: StrokeStyle(lineWidth: 2, lineJoin: .round)
                        )
                    }
                }
            }
        }
    }

    private func formatPrice(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2...3)))
    }
}
