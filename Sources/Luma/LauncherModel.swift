import Combine
import AppKit

enum LauncherPresentation: Equatable {
    case search
    case results
    case plugin
    case settings
}

enum LauncherSearchResult: Identifiable {
    case calculation(String)
    case plugin(Plugin)
    case application(InstalledApplication)
    case file(IndexedFile)
    case quicklink(Quicklink, query: String)
    case snippet(Snippet)

    var id: String {
        switch self {
        case .calculation(let value): "calculation:\(value)"
        case .plugin(let value): "plugin:\(value.id)"
        case .application(let value): "application:\(value.id)"
        case .file(let value): "file:\(value.id)"
        case .quicklink(let value, _): "quicklink:\(value.id)"
        case .snippet(let value): "snippet:\(value.id)"
        }
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    static let defaultExpandedWindowHeight: CGFloat = 666
    static let horizontalRecentWindowHeight: CGFloat = 270

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
    @Published private(set) var selectedText = ""
    @Published private(set) var focusRequest = 0

    let clipboard: ClipboardMonitor
    let pluginSettings: PluginSettings
    let installedApps: InstalledAppIndex
    let recentUsage: RecentUsageStore
    let fileSearch: FileSearchIndex
    let quicklinks: QuicklinkStore
    let snippets: SnippetStore
    private let applicationOpener: (URL) -> Bool
    private let textPaster: (String) -> Void
    private var cancellables = Set<AnyCancellable>()

    init(
        clipboard: ClipboardMonitor,
        pluginSettings: PluginSettings,
        installedApps: InstalledAppIndex,
        recentUsage: RecentUsageStore = RecentUsageStore(),
        fileSearch: FileSearchIndex,
        quicklinks: QuicklinkStore,
        snippets: SnippetStore,
        applicationOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        textPaster: @escaping (String) -> Void = { _ in }
    ) {
        self.clipboard = clipboard
        self.pluginSettings = pluginSettings
        self.installedApps = installedApps
        self.recentUsage = recentUsage
        self.fileSearch = fileSearch
        self.quicklinks = quicklinks
        self.snippets = snippets
        self.applicationOpener = applicationOpener
        self.textPaster = textPaster
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
        quicklinks.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        snippets.objectWillChange
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
        results.append(contentsOf: quicklinks.matches(query).map { .quicklink($0.0, query: $0.1) })
        results.append(contentsOf: snippets.search(query).map(LauncherSearchResult.snippet))
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
        Array(availableRecentItems.lazy.filter { $0.kind == kind }.prefix(15))
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
        preferredWindowHeight(recentDisplayMode: .vertical)
    }

    func preferredWindowHeight(recentDisplayMode: RecentSearchDisplayMode) -> CGFloat {
        switch presentation {
        case .search:
            if recentItems.isEmpty { return 58 }
            switch recentDisplayMode {
            case .horizontal:
                return Self.horizontalRecentWindowHeight
            case .vertical:
                return CGFloat(96 + recentItems.count * 52)
            }
        case .results:
            return 430
        case .plugin, .settings:
            return Self.defaultExpandedWindowHeight
        }
    }

    func prepareForPresentation(query initialQuery: String = "") {
        selectedPlugin = nil
        isShowingSettings = false
        selectedResult = 0
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
        guard searchResults.indices.contains(selectedResult) else { return }
        activate(searchResults[selectedResult])
    }

    func moveSelection(_ delta: Int) {
        let count = searchResults.count
        guard count > 0 else { selectedResult = 0; return }
        selectedResult = (selectedResult + delta + count) % count
        isShowingActions = false
    }

    func activate(_ result: LauncherSearchResult) {
        switch result {
        case .calculation(let value): clipboard.copy(value)
        case .plugin(let plugin): openPlugin(plugin)
        case .application(let application): openApplication(application)
        case .file(let file): NSWorkspace.shared.open(file.url); returnToSearch()
        case .quicklink(let item, let query):
            let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
            if let url = item.resolved(query: query, clipboard: clipboardText, selectedText: selectedText) {
                NSWorkspace.shared.open(url)
                returnToSearch()
            }
        case .snippet(let snippet):
            textPaster(snippet.content)
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
        case .quicklink(let link, _): clipboard.copy(link.template)
        case .snippet(let snippet): clipboard.copy(snippet.content)
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
