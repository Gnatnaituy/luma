import Combine
import Foundation

@MainActor
final class ApplicationSettings: ObservableObject {
    @Published private(set) var showsStatusBarIcon: Bool

    var applyHandler: ((Bool) -> Void)?

    private let defaults: UserDefaults
    private let statusBarIconStorageKey = "Luma.showsStatusBarIcon"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: statusBarIconStorageKey) == nil {
            showsStatusBarIcon = true
        } else {
            showsStatusBarIcon = defaults.bool(forKey: statusBarIconStorageKey)
        }
    }

    func setShowsStatusBarIcon(_ isVisible: Bool) {
        guard showsStatusBarIcon != isVisible else { return }
        showsStatusBarIcon = isVisible
        defaults.set(isVisible, forKey: statusBarIconStorageKey)
        applyHandler?(isVisible)
    }
}
