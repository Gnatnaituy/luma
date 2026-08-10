import Combine
import Foundation

enum RecentSearchDisplayMode: String, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal: L10n.text("横向", "Horizontal")
        case .vertical: L10n.text("竖向", "Vertical")
        }
    }
}

@MainActor
final class ApplicationSettings: ObservableObject {
    @Published private(set) var showsStatusBarIcon: Bool
    @Published private(set) var recentSearchDisplayMode: RecentSearchDisplayMode
    @Published private(set) var language: AppLanguage
    @Published private(set) var launchesAtLogin: Bool
    @Published private(set) var loginItemError = ""

    var applyHandler: ((Bool) -> Void)?
    var languageApplyHandler: ((AppLanguage) -> Void)?

    private let defaults: UserDefaults
    private let statusBarIconStorageKey = "Luma.showsStatusBarIcon"
    private let recentSearchDisplayModeStorageKey = "Luma.recentSearchDisplayMode"

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
        L10n.activate(language)
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
