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
    @ObservedObject var twoFactor: TwoFactorStore
    let selectedText: String
    let arrangeWindow: (WindowLayout) -> Void
    let pasteClipboardEntry: (ClipboardEntry) -> Void
    let dismiss: () -> Void

    @ViewBuilder
    var body: some View {
        switch plugin {
        case .clipboard: ClipboardPluginView(clipboard: clipboard, onPaste: pasteClipboardEntry)
        case .calculator: CalculatorPluginView()
        case .password: PasswordPluginView(clipboard: clipboard)
        case .twoFactor: TwoFactorPluginView(store: twoFactor, clipboard: clipboard, dismiss: dismiss)
        case .translate: TranslationPluginView(clipboard: clipboard, settings: translationSettings, preferredInput: selectedText)
        case .code: CodePluginView(clipboard: clipboard)
        case .stocks: StocksPluginView(store: stocks)
        case .weather: WeatherPluginView(store: weather)
        case .calendar: CalendarPluginView()
        case .windows: WindowManagementPluginView(arrange: arrangeWindow)
        }
    }
}
struct ClipboardPluginView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    let onPaste: (ClipboardEntry) -> Void
    @State private var filter: ClipboardFilter
    @State private var searchText = ""
    @State private var effectiveSearchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectionState = ClipboardSelectionState()
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
        clipboard.filteredEntries(filter, matching: effectiveSearchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(L10n.text("搜索剪贴板内容", "Search Clipboard"), text: $searchText)
                .textFieldStyle(LumaTextFieldStyle(height: 32))
                .focused($isSearchFocused)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ClipboardFilter.allCases) { item in
                            Button { changeFilter(to: item) } label: {
                                Text(item.title)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(filter == item ? Color.accentColor : LumaTone.hoverFill, in: Capsule())
                                    .foregroundStyle(filter == item ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(L10n.text(
                    "最近 \(clipboard.entries.count) 条",
                    "Latest \(clipboard.entries.count)"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()

                Button(L10n.text("清空未收藏", "Clear Unfavorited"), role: .destructive) {
                    clipboard.clearHistory()
                }
                    .buttonStyle(LumaTextButtonStyle(emphasis: .destructive, height: 28))
                    .disabled(!clipboard.entries.contains { !$0.isFavorite })
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

            if clipboard.entries.isEmpty {
                ContentUnavailableView(
                    L10n.text("还没有剪贴板记录", "No Clipboard History"),
                    systemImage: "clipboard",
                    description: Text(L10n.text(
                        "复制文本、图片、文件或链接后会自动持久化到本机",
                        "Copied text, images, files, and links are stored locally"
                    ))
                )
            } else if visibleEntries.isEmpty {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        L10n.text("该分类暂无记录", "No Items in This Category"),
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text(L10n.text(
                            "切换到其他类型查看剪贴板历史",
                            "Choose another type to browse clipboard history"
                        ))
                    )
                } else {
                    ContentUnavailableView(
                        L10n.text("没有匹配的剪贴板记录", "No Matching Clipboard Items"),
                        systemImage: "magnifyingglass",
                        description: Text(L10n.text(
                            "尝试其他关键词或切换内容类型",
                            "Try another keyword or content type"
                        ))
                    )
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(visibleEntries) { entry in
                                ClipboardEntryRow(
                                    entry: entry,
                                    clipboard: clipboard,
                                    previewSize: clipboard.imagePreviewSize,
                                    isSelected: selectionState.selectedID == entry.id,
                                    onSelect: { selectionState.select(entry.id) },
                                    onPaste: onPaste
                                )
                                    .padding(.horizontal, 14)
                                    .id(entry.id)
                            }
                        }
                        .padding(.vertical, 10)
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
            resetSelectionAndScrollToTop()
            installKeyboardMonitor()
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onDisappear(perform: removeKeyboardMonitor)
        .task(id: searchText) {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            effectiveSearchText = searchText
            await Task.yield()
            resetSelectionAndScrollToTop()
        }
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
        let wasValid = selectionState.ensureValid(in: visibleEntries)
        guard !wasValid else { return }
        resetNavigationTracking()
        if scrollToTop, let firstEntryID = visibleEntries.first?.id {
            requestScroll(to: firstEntryID, edge: .top)
        }
    }

    private func moveSelection(_ delta: Int) {
        let entries = visibleEntries
        guard !entries.isEmpty else {
            selectionState.reset()
            resetNavigationTracking()
            return
        }
        let previousIndex = selectionState.selectedID.flatMap { selectedID in
            entries.firstIndex(where: { $0.id == selectedID })
        }
        let nextID = selectionState.move(in: entries, delta: delta)

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
        changeFilter(to: ClipboardKeyboardNavigation.movedFilter(current: filter, delta: delta))
    }

    private func pasteSelection() {
        guard let selectedEntryID = selectionState.selectedID,
              let entry = visibleEntries.first(where: { $0.id == selectedEntryID }) else { return }
        onPaste(entry)
    }

    private func changeFilter(to newFilter: ClipboardFilter) {
        guard filter != newFilter else { return }
        filter = newFilter
        DispatchQueue.main.async {
            resetSelectionAndScrollToTop()
        }
    }

    private func resetSelectionAndScrollToTop() {
        selectionState.reset()
        resetNavigationTracking()
        guard let firstEntryID = visibleEntries.first?.id else { return }
        requestScroll(to: firstEntryID, edge: .top)
    }

    private func resetNavigationTracking() {
        navigationDirection = 0
        navigationStepsSinceScroll = 0
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

struct ClipboardSelectionState {
    private(set) var selectedID: UUID?

    init(selectedID: UUID? = nil) {
        self.selectedID = selectedID
    }

    mutating func reset() {
        selectedID = nil
    }

    mutating func select(_ id: UUID) {
        selectedID = id
    }

    @discardableResult
    mutating func ensureValid(in entries: [ClipboardEntry]) -> Bool {
        guard let selectedID else { return true }
        guard entries.contains(where: { $0.id == selectedID }) else {
            reset()
            return false
        }
        return true
    }

    @discardableResult
    mutating func move(in entries: [ClipboardEntry], delta: Int) -> UUID? {
        selectedID = ClipboardKeyboardNavigation.movedSelection(
            current: selectedID,
            entries: entries,
            delta: delta
        )
        return selectedID
    }
}

struct ClipboardEntryRow: View {
    /// 图片条目的预览度量：缩略图维持行高，大图限制高度，避免竖版截图把列表撑得太长。
    static let thumbnailSize = CGSize(width: 72, height: 56)
    static let thumbnailSourceDimension: CGFloat = 144
    static let expandedPreviewMaxHeight: CGFloat = 340
    static let expandedSourceDimension: CGFloat = 1_280

    let entry: ClipboardEntry
    @ObservedObject var clipboard: ClipboardMonitor
    let previewSize: ClipboardImagePreviewSize
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: (ClipboardEntry) -> Void
    @State private var isImageExpanded: Bool
    @State private var isHovering = false

    init(
        entry: ClipboardEntry,
        clipboard: ClipboardMonitor,
        previewSize: ClipboardImagePreviewSize = .large,
        isSelected: Bool = false,
        initiallyExpanded: Bool? = nil,
        onSelect: @escaping () -> Void = {},
        onPaste: @escaping (ClipboardEntry) -> Void = { _ in }
    ) {
        self.entry = entry
        self.clipboard = clipboard
        self.previewSize = previewSize
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onPaste = onPaste
        _isImageExpanded = State(
            initialValue: initiallyExpanded ?? previewSize.expandsImagesByDefault
        )
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
                            // 用 Text 的 format 重载而不是 `Date.formatted()`：后者固定按系统
                            // locale 排版，中文界面下会显示成英文日期。
                            Text(entry.copiedAt, format: .dateTime.year().month().day().hour().minute())
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture(count: 1)
                        .onEnded(onSelect)
                )
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded { onPaste(entry) }
                )

                actionButtons
            }

            if let storedImage = imagePayload {
                if isImageExpanded {
                    expandedPreview(for: storedImage)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isImageExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isImageExpanded ? "chevron.up" : "chevron.down")
                        Text(isImageExpanded
                            ? L10n.text("收起图片", "Collapse Image")
                            : L10n.text("展开图片", "Expand Image"))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isImageExpanded ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(LumaTextButtonStyle(height: 30))
                .help(isImageExpanded
                    ? L10n.text("收起图片", "Collapse Image")
                    : L10n.text("展开图片", "Expand Image"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(cardFill, in: RoundedRectangle(cornerRadius: LumaRadius.card, style: .continuous))
        .overlay {
            if isSelected {
                LumaRimStroke(cornerRadius: LumaRadius.card, isProminent: true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: LumaRadius.card, style: .continuous))
        .animation(LumaMotion.quick, value: isSelected)
        .onHover { isHovering = $0 }
        .onChange(of: previewSize) { _, size in
            // 设置变化后已经建好的行也要跟着切换默认形态。
            isImageExpanded = size.expandsImagesByDefault
        }
    }

    /// 卡片底色负责把相邻条目分开：选中 > 悬停 > 静息。
    private var cardFill: Color {
        if isSelected { return LumaTone.selectionFill }
        return isHovering ? LumaTone.hoverFill : LumaTone.cardFill
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if entry.kind == .link || entry.kind == .file {
                Button { openEntry() } label: {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(LumaIconButtonStyle())
                .help(L10n.text("打开", "Open"))
            }

            Button { clipboard.toggleFavorite(entry) } label: {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(entry.isFavorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(LumaIconButtonStyle())
            .help(entry.isFavorite
                ? L10n.text("取消收藏", "Remove Favorite")
                : L10n.text("收藏", "Favorite"))

            Button { clipboard.copy(entry) } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(LumaIconButtonStyle())
            .help(L10n.text("复制", "Copy"))

            Button(role: .destructive) { clipboard.remove(entry) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(LumaIconButtonStyle())
            .help(L10n.text("删除", "Delete"))
        }
        .frame(height: 28, alignment: .top)
        .fixedSize()
    }

    private var imagePayload: ClipboardImage? {
        guard case .image(let storedImage) = entry.payload else { return nil }
        return storedImage
    }

    /// 大图的显示尺寸：按原始比例塞进「高度上限」框，超宽截图再受宽度上限约束。
    /// 直接算出具体尺寸，容器、描边和点击区域才都贴着图片本身。
    static func expandedPreviewSize(for image: NSImage) -> CGSize {
        let maximumWidth: CGFloat = 560
        let ratio = image.size.width / max(image.size.height, 1)
        guard ratio.isFinite, ratio > 0 else {
            return CGSize(width: maximumWidth, height: expandedPreviewMaxHeight)
        }
        let width = min(maximumWidth, expandedPreviewMaxHeight * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    @ViewBuilder
    private func expandedPreview(for storedImage: ClipboardImage) -> some View {
        if let image = storedImage.thumbnail(maxDimension: Self.expandedSourceDimension) {
            let size = Self.expandedPreviewSize(for: image)
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(LumaTone.hairline, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .onTapGesture { openImageInPreview(storedImage) }
                .help(L10n.text(
                    "在 macOS Preview 中按原始尺寸查看",
                    "View at full size in macOS Preview"
                ))
                .accessibilityLabel(L10n.text(
                    "在 macOS Preview 中按原始尺寸查看",
                    "View at full size in macOS Preview"
                ))
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch entry.payload {
        case .image(let storedImage):
            if let image = storedImage.thumbnail(maxDimension: Self.thumbnailSourceDimension) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    Button { openImageInPreview(storedImage) } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(LumaIconButtonStyle())
                    .padding(4)
                    .help(L10n.text("使用 macOS Preview 查看", "View in macOS Preview"))
                    .accessibilityLabel(L10n.text("使用 macOS Preview 查看", "View in macOS Preview"))
                }
                .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
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
