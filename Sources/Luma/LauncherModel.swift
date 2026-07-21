import Combine
import AppKit

enum LauncherPresentation: Equatable {
    case search
    case results
    case plugin
    case settings
}

final class LauncherModel: ObservableObject {
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
    @Published private(set) var focusRequest = 0

    let clipboard: ClipboardMonitor
    let pluginSettings: PluginSettings
    let installedApps: InstalledAppIndex
    let recentUsage: RecentUsageStore
    private let applicationOpener: (URL) -> Bool
    private var cancellables = Set<AnyCancellable>()

    init(
        clipboard: ClipboardMonitor,
        pluginSettings: PluginSettings,
        installedApps: InstalledAppIndex,
        recentUsage: RecentUsageStore = RecentUsageStore(),
        applicationOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.clipboard = clipboard
        self.pluginSettings = pluginSettings
        self.installedApps = installedApps
        self.recentUsage = recentUsage
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

    var recentItems: [RecentUsageItem] {
        Array(recentUsage.items.lazy.filter { item in
            switch item.kind {
            case .plugin:
                guard let plugin = item.plugin else { return false }
                return self.pluginSettings.isEnabled(plugin)
            case .application:
                guard let application = item.application else { return false }
                return FileManager.default.fileExists(atPath: application.url.path)
            }
        }.prefix(9))
    }

    var presentation: LauncherPresentation {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .results }
        if isShowingSettings { return .settings }
        if selectedPlugin != nil { return .plugin }
        return .search
    }

    var preferredWindowHeight: CGFloat {
        switch presentation {
        case .search:
            recentItems.isEmpty ? 58 : CGFloat(96 + recentItems.count * 52)
        case .results: 430
        case .plugin, .settings: 600
        }
    }

    func prepareForPresentation(query initialQuery: String = "") {
        selectedPlugin = nil
        isShowingSettings = false
        selectedResult = 0
        query = initialQuery
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
        let calculation = instantCalculation
        if let calculation, selectedResult == 0 {
            clipboard.copy(calculation)
            return
        }
        let plugins = filteredPlugins
        let offset = calculation == nil ? 0 : 1
        let resultIndex = selectedResult - offset
        if plugins.indices.contains(resultIndex) {
            openPlugin(plugins[resultIndex])
            return
        }
        let applicationIndex = resultIndex - plugins.count
        let applications = filteredApplications
        if applications.indices.contains(applicationIndex) {
            openApplication(applications[applicationIndex])
        }
    }

    func moveSelection(_ delta: Int) {
        let count = filteredPlugins.count + filteredApplications.count + (instantCalculation == nil ? 0 : 1)
        guard count > 0 else { selectedResult = 0; return }
        selectedResult = (selectedResult + delta + count) % count
    }

    func openPlugin(_ plugin: Plugin) {
        recentUsage.record(plugin: plugin)
        query = ""
        isShowingSettings = false
        selectedPlugin = plugin
        selectedResult = 0
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
