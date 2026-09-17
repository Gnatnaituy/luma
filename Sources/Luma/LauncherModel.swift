import AppKit
import Combine
import SwiftUI

enum LauncherPresentation: Equatable {
    case search
    case results
    case plugin
    case settings
}

/// 首页「最近使用」网格中的一格，可能来自插件或本机 App。
struct RecentTileItem: Identifiable {
    enum Source: Equatable {
        case plugin(Plugin)
        case application(InstalledApplication)
    }

    let source: Source
    let title: String

    var id: String {
        switch source {
        case .plugin(let plugin): "plugin:\(plugin.id)"
        case .application(let application): "application:\(application.id)"
        }
    }

    var symbol: String? {
        guard case .plugin(let plugin) = source else { return nil }
        return plugin.symbol
    }

    var tint: Color {
        guard case .plugin(let plugin) = source else { return .accentColor }
        return plugin.tint
    }

    var applicationURL: URL? {
        guard case .application(let application) = source else { return nil }
        return application.url
    }

    static func plugin(_ plugin: Plugin) -> RecentTileItem {
        RecentTileItem(source: .plugin(plugin), title: plugin.title)
    }

    static func application(_ application: InstalledApplication) -> RecentTileItem {
        RecentTileItem(source: .application(application), title: application.name)
    }
}

/// 首页网格的一段；平铺布局只有一段且不带标题。
struct RecentTileSection: Identifiable {
    let id: String
    let title: String?
    let items: [RecentTileItem]

    func rows(columns: Int) -> [[RecentTileItem]] {
        guard columns > 0 else { return items.isEmpty ? [] : [items] }
        return stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0..<min($0 + columns, items.count)])
        }
    }
}

enum LauncherSearchResult: Identifiable {
    case calculation(String)
    case plugin(Plugin)
    case application(InstalledApplication)
    case file(IndexedFile)

    var id: String {
        switch self {
        case .calculation(let value): "calculation:\(value)"
        case .plugin(let value): "plugin:\(value.id)"
        case .application(let value): "application:\(value.id)"
        case .file(let value): "file:\(value.id)"
        }
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    static let defaultExpandedWindowHeight: CGFloat = 666

    /// 首屏横向布局下每个分区展示的最近条目上限。
    static let horizontalRecentItemLimit = 15

    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            selectedResult = 0
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedPlugin = nil
                isShowingSettings = false
            }
        }
    }
    @Published var selectedPlugin: Plugin? = nil
    @Published var isShowingSettings = false
    @Published var selectedResult = 0
    @Published var isShowingActions = false
    @Published var recentSelection = 0
    /// 只有键盘导航后才高亮网格选中项，指针操作时保持与系统一致的干净外观。
    @Published private(set) var isRecentSelectionActive = false
    @Published var recentDisplayMode: RecentSearchDisplayMode = .vertical
    @Published private(set) var selectedText = ""
    @Published private(set) var focusRequest = 0

    let clipboard: ClipboardMonitor
    let pluginSettings: PluginSettings
    let installedApps: InstalledAppIndex
    let recentUsage: RecentUsageStore
    let fileSearch: FileSearchIndex
    private let applicationOpener: (URL) -> Bool
    private var cancellables = Set<AnyCancellable>()

    init(
        clipboard: ClipboardMonitor,
        pluginSettings: PluginSettings,
        installedApps: InstalledAppIndex,
        recentUsage: RecentUsageStore = RecentUsageStore(),
        fileSearch: FileSearchIndex,
        applicationOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.clipboard = clipboard
        self.pluginSettings = pluginSettings
        self.installedApps = installedApps
        self.recentUsage = recentUsage
        self.fileSearch = fileSearch
        self.applicationOpener = applicationOpener
        clipboard.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        pluginSettings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        installedApps.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        recentUsage.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        fileSearch.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        $query
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak fileSearch] value in
                Task { @MainActor in fileSearch?.search(value) }
            }
            .store(in: &cancellables)
    }

    var filteredPlugins: [Plugin] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return pluginSettings.enabledPlugins }
        return pluginSettings.enabledPlugins.filter {
            $0.matches(value, keywords: pluginSettings.keywords(for: $0))
        }
    }

    var instantCalculation: String? {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        guard let result = try? ExpressionEvaluator.evaluate(value) else { return nil }
        return ExpressionEvaluator.display(result)
    }

    var filteredApplications: [InstalledApplication] {
        installedApps.search(query)
    }

    var searchResults: [LauncherSearchResult] {
        var results: [LauncherSearchResult] = []
        if let instantCalculation { results.append(.calculation(instantCalculation)) }
        results.append(contentsOf: filteredPlugins.map(LauncherSearchResult.plugin))
        results.append(contentsOf: filteredApplications.map(LauncherSearchResult.application))
        results.append(contentsOf: fileSearch.results.map(LauncherSearchResult.file))
        return results
    }

    private var availableRecentItems: [RecentUsageItem] {
        recentUsage.items.filter { item in
            switch item.kind {
            case .plugin:
                guard let plugin = item.plugin else { return false }
                return self.pluginSettings.isEnabled(plugin)
            case .application:
                guard let application = item.application else { return false }
                return FileManager.default.fileExists(atPath: application.url.path)
            }
        }
    }

    var recentItems: [RecentUsageItem] {
        Array(availableRecentItems.prefix(9))
    }

    func horizontalRecentItems(of kind: RecentUsageKind) -> [RecentUsageItem] {
        Array(
            availableRecentItems.lazy
                .filter { $0.kind == kind }
                .prefix(Self.horizontalRecentItemLimit)
        )
    }

    // MARK: - 首页最近使用

    var recentSections: [RecentTileSection] {
        recentSections(displayMode: recentDisplayMode)
    }

    func recentSections(displayMode: RecentSearchDisplayMode) -> [RecentTileSection] {
        switch displayMode {
        case .vertical:
            return [
                RecentTileSection(
                    id: "recent",
                    title: nil,
                    items: recentItems.map(tileItem(for:))
                )
            ]
        case .horizontal:
            return [
                RecentTileSection(
                    id: "recent.plugins",
                    title: L10n.text("插件", "Plugins"),
                    items: horizontalRecentItems(of: .plugin).map(tileItem(for:))
                ),
                RecentTileSection(
                    id: "recent.applications",
                    title: L10n.text("应用", "Applications"),
                    items: horizontalRecentItems(of: .application).map(tileItem(for:))
                )
            ]
        }
    }

    private func tileItem(for item: RecentUsageItem) -> RecentTileItem {
        if let plugin = item.plugin { return .plugin(plugin) }
        if let application = item.application { return .application(application) }
        return .plugin(.clipboard)
    }

    var recentTileItems: [RecentTileItem] {
        recentSections.flatMap(\.items)
    }

    var recentTileIndexMap: [String: Int] {
        var map: [String: Int] = [:]
        for (index, item) in recentTileItems.enumerated() {
            map[item.id] = index
        }
        return map
    }

    var selectedRecentTileID: String? {
        let items = recentTileItems
        guard items.indices.contains(recentSelection) else { return nil }
        return items[recentSelection].id
    }

    func moveRecentSelection(horizontal: Int, vertical: Int) {
        let count = recentTileItems.count
        guard count > 0 else {
            recentSelection = 0
            isRecentSelectionActive = false
            return
        }
        let columns = LumaGridMetrics.columns
        let current = min(max(0, recentSelection), count - 1)
        let targetRow = min(max(0, current / columns + vertical), (count - 1) / columns)
        let targetColumn = min(max(0, current % columns + horizontal), columns - 1)
        recentSelection = min(targetRow * columns + targetColumn, count - 1)
        isRecentSelectionActive = true
    }

    func activateRecentSelection() {
        guard let id = selectedRecentTileID,
              let item = recentTileItems.first(where: { $0.id == id }) else { return }
        activate(item)
    }

    func activate(_ item: RecentTileItem) {
        switch item.source {
        case .plugin(let plugin):
            openPlugin(plugin)
        case .application(let application):
            openApplication(application)
        }
    }


    var presentation: LauncherPresentation {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .results }
        if isShowingSettings { return .settings }
        if selectedPlugin != nil { return .plugin }
        return .search
    }

    var windowHeightContext: LauncherWindowHeightContext {
        switch presentation {
        case .search:
            return .search
        case .results:
            return .results
        case .settings:
            return .settings
        case .plugin:
            return .plugin(selectedPlugin?.rawValue ?? "unknown")
        }
    }

    var preferredWindowHeight: CGFloat {
        preferredWindowHeight(recentDisplayMode: recentDisplayMode)
    }

    func preferredWindowHeight(recentDisplayMode: RecentSearchDisplayMode) -> CGFloat {
        switch presentation {
        case .search:
            return Self.recentPanelHeight(sections: recentSections(displayMode: recentDisplayMode))
        case .results:
            return 430
        case .plugin, .settings:
            return Self.defaultExpandedWindowHeight
        }
    }

    /// 首页高度：外壳 + 网格（含行间分隔线与分组标题）。
    static func recentPanelHeight(sections: [RecentTileSection]) -> CGFloat {
        var height = LumaChromeMetrics.headerHeight + LumaChromeMetrics.hairline
            + LumaGridMetrics.gridTopPadding
            + LumaGridMetrics.gridBottomPadding

        let visibleSections = sections.filter { !$0.items.isEmpty }
        guard !visibleSections.isEmpty else {
            return height + LumaGridMetrics.emptyStateHeight
        }

        for (index, section) in visibleSections.enumerated() {
            if index > 0 {
                height += LumaChromeMetrics.hairline
            }
            if section.title != nil {
                height += LumaGridMetrics.sectionHeaderHeight + 4
            }
            let rows = LumaGridMetrics.rows(count: section.items.count)
            height += CGFloat(rows) * LumaGridMetrics.rowPitch
                + CGFloat(rows - 1) * LumaChromeMetrics.hairline
        }
        return height
    }

    func prepareForPresentation(query initialQuery: String = "") {
        selectedPlugin = nil
        isShowingSettings = false
        selectedResult = 0
        recentSelection = 0
        isRecentSelectionActive = false
        query = initialQuery
        selectedText = SelectedTextReader.read()
        if openOnlyMatchingPlugin() { return }
        requestSearchFocus()
    }

    @discardableResult
    private func openOnlyMatchingPlugin() -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              instantCalculation == nil,
              filteredApplications.isEmpty,
              filteredPlugins.count == 1,
              let plugin = filteredPlugins.first else { return false }
        openPlugin(plugin)
        return true
    }

    func requestSearchFocus() {
        focusRequest += 1
    }

    func activateSelected() {
        if presentation == .search {
            activateRecentSelection()
            return
        }
        guard searchResults.indices.contains(selectedResult) else { return }
        activate(searchResults[selectedResult])
    }

    func moveSelection(_ delta: Int) {
        if presentation == .search {
            moveRecentSelection(horizontal: 0, vertical: delta)
            return
        }
        let count = searchResults.count
        guard count > 0 else { selectedResult = 0; return }
        selectedResult = (selectedResult + delta + count) % count
        isShowingActions = false
    }

    /// 左右方向键：首屏在网格中横向移动，搜索结果中展开操作栏。返回是否已消费该按键。
    func moveSelectionHorizontally(_ delta: Int) -> Bool {
        if presentation == .search {
            moveRecentSelection(horizontal: delta, vertical: 0)
            return true
        }
        guard delta > 0 else { return false }
        toggleActions()
        return true
    }

    func activate(_ result: LauncherSearchResult) {
        switch result {
        case .calculation(let value): clipboard.copy(value)
        case .plugin(let plugin): openPlugin(plugin)
        case .application(let application): openApplication(application)
        case .file(let file): NSWorkspace.shared.open(file.url); returnToSearch()
        }
    }

    func toggleActions() {
        guard searchResults.indices.contains(selectedResult) else { return }
        isShowingActions.toggle()
    }

    func copySelectedValue() {
        guard searchResults.indices.contains(selectedResult) else { return }
        switch searchResults[selectedResult] {
        case .calculation(let value): clipboard.copy(value)
        case .plugin(let plugin): clipboard.copy(plugin.title)
        case .application(let app): clipboard.copy(app.url.path)
        case .file(let file): clipboard.copy(file.url.path)
        }
    }

    func revealSelectedInFinder() {
        guard searchResults.indices.contains(selectedResult) else { return }
        let url: URL?
        switch searchResults[selectedResult] {
        case .application(let app): url = app.url
        case .file(let file): url = file.url
        default: url = nil
        }
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func openPlugin(_ plugin: Plugin) {
        recentUsage.record(plugin: plugin)
        query = ""
        isShowingSettings = false
        selectedPlugin = plugin
        selectedResult = 0
        isShowingActions = false
    }

    func openApplication(_ application: InstalledApplication) {
        if applicationOpener(application.url) {
            recentUsage.record(application: application)
            returnToSearch()
        }
    }

    func showSettings() {
        query = ""
        selectedPlugin = nil
        isShowingSettings = true
        selectedResult = 0
    }

    func returnToSearch() {
        query = ""
        selectedPlugin = nil
        isShowingSettings = false
        selectedResult = 0
        recentSelection = 0
        isRecentSelectionActive = false
        requestSearchFocus()
    }

    func handleEscape() -> Bool {
        if presentation != .search {
            returnToSearch()
            return true
        }
        return false
    }
}
