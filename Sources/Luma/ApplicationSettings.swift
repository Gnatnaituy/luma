import Combine
import Foundation

enum RecentSearchDisplayMode: String, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal: L10n.text("分组", "Grouped")
        case .vertical: L10n.text("平铺", "Flat")
        }
    }

    var detail: String {
        switch self {
        case .horizontal: L10n.text("插件与应用各自成组", "Plugins and apps in separate groups")
        case .vertical: L10n.text("最近使用混排成一片网格", "Recent items in one grid")
        }
    }
}

@MainActor
final class ApplicationSettings: ObservableObject {
    @Published private(set) var showsStatusBarIcon: Bool
    @Published private(set) var recentSearchDisplayMode: RecentSearchDisplayMode
    @Published private(set) var language: AppLanguage
    @Published private(set) var launchesAtLogin: Bool
    /// 面板背景透明度，0 为完全不透明、1 为完全透明。
    @Published private(set) var panelTransparency: Double
    @Published private(set) var loginItemError = ""

    var applyHandler: ((Bool) -> Void)?
    var languageApplyHandler: ((AppLanguage) -> Void)?

    private let defaults: UserDefaults
    private let statusBarIconStorageKey = "Luma.showsStatusBarIcon"
    private let recentSearchDisplayModeStorageKey = "Luma.recentSearchDisplayMode"
    private let panelTransparencyStorageKey = "Luma.panelTransparency"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: statusBarIconStorageKey) == nil {
            showsStatusBarIcon = true
        } else {
            showsStatusBarIcon = defaults.bool(forKey: statusBarIconStorageKey)
        }
        recentSearchDisplayMode = defaults
            .string(forKey: recentSearchDisplayModeStorageKey)
            .flatMap(RecentSearchDisplayMode.init(rawValue:)) ?? .vertical
        language = defaults
            .string(forKey: AppLanguage.storageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese
        launchesAtLogin = LoginItemManager.isEnabled
        if let stored = defaults.object(forKey: panelTransparencyStorageKey) as? NSNumber {
            panelTransparency = min(1, max(0, stored.doubleValue))
        } else {
            panelTransparency = 1 - Double(LumaTone.panelTintAlpha)
        }
        L10n.activate(language)
    }

    /// 面板背景的不透明度系数，1 为完全不透明、0 为完全透明背景，供玻璃背景直接使用。
    var panelTintAlpha: CGFloat { CGFloat(1 - panelTransparency) }

    func setPanelTransparency(_ value: Double) {
        let clamped = min(1, max(0, value))
        guard panelTransparency != clamped else { return }
        panelTransparency = clamped
        defaults.set(clamped, forKey: panelTransparencyStorageKey)
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            launchesAtLogin = LoginItemManager.isEnabled
            loginItemError = ""
        } catch {
            launchesAtLogin = LoginItemManager.isEnabled
            loginItemError = error.localizedDescription
        }
    }

    func setShowsStatusBarIcon(_ isVisible: Bool) {
        guard showsStatusBarIcon != isVisible else { return }
        showsStatusBarIcon = isVisible
        defaults.set(isVisible, forKey: statusBarIconStorageKey)
        applyHandler?(isVisible)
    }

    func setRecentSearchDisplayMode(_ mode: RecentSearchDisplayMode) {
        guard recentSearchDisplayMode != mode else { return }
        recentSearchDisplayMode = mode
        defaults.set(mode.rawValue, forKey: recentSearchDisplayModeStorageKey)
    }

    func setLanguage(_ newLanguage: AppLanguage) {
        guard language != newLanguage else { return }
        L10n.activate(newLanguage)
        language = newLanguage
        defaults.set(newLanguage.rawValue, forKey: AppLanguage.storageKey)
        languageApplyHandler?(newLanguage)
    }
}
