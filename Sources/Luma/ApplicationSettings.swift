import Combine
import Foundation

enum RecentSearchDisplayMode: String, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal: "横向"
        case .vertical: "竖向"
        }
    }
}

@MainActor
final class ApplicationSettings: ObservableObject {
    @Published private(set) var showsStatusBarIcon: Bool
    @Published private(set) var recentSearchDisplayMode: RecentSearchDisplayMode
    @Published private(set) var launchesAtLogin: Bool
    @Published private(set) var loginItemError = ""

    var applyHandler: ((Bool) -> Void)?

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
        launchesAtLogin = LoginItemManager.isEnabled
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
}
