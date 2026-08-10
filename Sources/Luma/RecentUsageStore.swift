import Combine
import Foundation

enum RecentUsageKind: String, Codable {
    case plugin
    case application
}

struct RecentUsageItem: Codable, Equatable, Identifiable {
    let kind: RecentUsageKind
    let pluginIdentifier: String?
    let applicationURL: URL?
    let title: String
    let subtitle: String

    var id: String {
        switch kind {
        case .plugin:
            "plugin:\(pluginIdentifier ?? title)"
        case .application:
            "application:\(applicationURL?.standardizedFileURL.path ?? title)"
        }
    }

    var plugin: Plugin? {
        guard let pluginIdentifier else { return nil }
        return Plugin(rawValue: pluginIdentifier)
    }

    var application: InstalledApplication? {
        guard let applicationURL else { return nil }
        return InstalledApplication(
            url: applicationURL,
            name: title,
            bundleIdentifier: ["macOS 应用程序", "macOS Application"].contains(subtitle) ? nil : subtitle
        )
    }

    static func plugin(_ plugin: Plugin) -> RecentUsageItem {
        RecentUsageItem(
            kind: .plugin,
            pluginIdentifier: plugin.rawValue,
            applicationURL: nil,
            title: plugin.title,
            subtitle: plugin.subtitle
        )
    }

    static func application(_ application: InstalledApplication) -> RecentUsageItem {
        RecentUsageItem(
            kind: .application,
            pluginIdentifier: nil,
            applicationURL: application.url,
            title: application.name,
            subtitle: application.bundleIdentifier ?? L10n.text("macOS 应用程序", "macOS Application")
        )
    }
}

final class RecentUsageStore: ObservableObject {
    @Published private(set) var items: [RecentUsageItem]

    private let defaults: UserDefaults
    private let storageKey = "Luma.recentUsage.v1"
    private let maximumItemCountPerKind = 15

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([RecentUsageItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    func record(plugin: Plugin) {
        record(.plugin(plugin))
    }

    func record(application: InstalledApplication) {
        record(.application(application))
    }

    private func record(_ item: RecentUsageItem) {
        var updated = items.filter { $0.id != item.id }
        updated.insert(item, at: 0)
        var counts: [RecentUsageKind: Int] = [:]
        items = updated.filter { candidate in
            let count = counts[candidate.kind, default: 0]
            guard count < maximumItemCountPerKind else { return false }
            counts[candidate.kind] = count + 1
            return true
        }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
