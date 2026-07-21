import Combine
import Foundation

struct PluginConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var keywords: [String]
}

final class PluginSettings: ObservableObject {
    @Published private(set) var configurations: [String: PluginConfiguration]

    private let defaults: UserDefaults
    private let storageKey = "Luma.pluginConfigurations"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: PluginConfiguration].self, from: data) {
            configurations = saved
        } else {
            configurations = [:]
        }

        for plugin in Plugin.allCases where configurations[plugin.rawValue] == nil {
            configurations[plugin.rawValue] = PluginConfiguration(
                isEnabled: true,
                keywords: plugin.keywords
            )
        }
    }

    var enabledPlugins: [Plugin] {
        Plugin.allCases.filter(isEnabled)
    }

    func configuration(for plugin: Plugin) -> PluginConfiguration {
        configurations[plugin.rawValue] ?? PluginConfiguration(
            isEnabled: true,
            keywords: plugin.keywords
        )
    }

    func isEnabled(_ plugin: Plugin) -> Bool {
        configuration(for: plugin).isEnabled
    }

    func keywords(for plugin: Plugin) -> [String] {
        configuration(for: plugin).keywords
    }

    func setEnabled(_ enabled: Bool, for plugin: Plugin) {
        var configuration = configuration(for: plugin)
        guard configuration.isEnabled != enabled else { return }
        configuration.isEnabled = enabled
        configurations[plugin.rawValue] = configuration
        persist()
    }

    @discardableResult
    func addKeyword(to plugin: Plugin) -> Int {
        var configuration = configuration(for: plugin)
        configuration.keywords.append("")
        configurations[plugin.rawValue] = configuration
        persist()
        return configuration.keywords.count - 1
    }

    func updateKeyword(for plugin: Plugin, at index: Int, value: String) {
        var configuration = configuration(for: plugin)
        guard configuration.keywords.indices.contains(index) else { return }
        configuration.keywords[index] = value
        configurations[plugin.rawValue] = configuration
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
