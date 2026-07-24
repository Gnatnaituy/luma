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
    @ObservedObject var quicklinks: QuicklinkStore
    @ObservedObject var snippets: SnippetStore
    @ObservedObject var calendar: CalendarStore
    let selectedText: String
    let arrangeWindow: (WindowLayout) -> Void
    let pasteClipboardEntry: (ClipboardEntry) -> Void

    @ViewBuilder
    var body: some View {
        switch plugin {
        case .clipboard: ClipboardPluginView(clipboard: clipboard, onPaste: pasteClipboardEntry)
        case .calculator: CalculatorPluginView()
        case .json: JSONPluginView(clipboard: clipboard)
        case .password: PasswordPluginView(clipboard: clipboard)
        case .translate: TranslationPluginView(clipboard: clipboard, settings: translationSettings, preferredInput: selectedText)
        case .code: CodePluginView(clipboard: clipboard)
        case .stocks: StocksPluginView(store: stocks)
        case .weather: WeatherPluginView(store: weather)
        case .quicklinks: QuicklinksPluginView(store: quicklinks)
        case .snippets: SnippetsPluginView(store: snippets, clipboard: clipboard)
        case .calendar: CalendarPluginView(store: calendar)
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
            TextField("搜索剪贴板内容", text: $searchText)
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
                                ClipboardEntryRow(
                                    entry: entry,
                                    clipboard: clipboard,
                                    onSelect: { selectionState.select(entry.id) },
                                    onPaste: onPaste
                                )
                                    .padding(.horizontal, 24)
                                    .background {
                                        if selectionState.selectedID == entry.id {
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
    let entry: ClipboardEntry
    @ObservedObject var clipboard: ClipboardMonitor
    let onSelect: () -> Void
    let onPaste: (ClipboardEntry) -> Void
    @State private var isImageExpanded: Bool

    init(
        entry: ClipboardEntry,
        clipboard: ClipboardMonitor,
        initiallyExpanded: Bool = false,
        onSelect: @escaping () -> Void = {},
        onPaste: @escaping (ClipboardEntry) -> Void = { _ in }
    ) {
        self.entry = entry
        self.clipboard = clipboard
        self.onSelect = onSelect
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
            if let image = storedImage.thumbnail(maxDimension: 144) {
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
