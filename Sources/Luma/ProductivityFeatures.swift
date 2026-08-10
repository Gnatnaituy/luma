import AppKit
import ApplicationServices
import Combine
import Foundation
import ServiceManagement

struct IndexedFile: Equatable, Identifiable {
    let url: URL
    let name: String
    var id: String { url.path }
}

@MainActor
final class FileSearchIndex: ObservableObject {
    @Published private(set) var results: [IndexedFile] = []
    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?

    func search(_ text: String) {
        stop()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { results = []; return }
        let metadataQuery = NSMetadataQuery()
        metadataQuery.searchScopes = [NSMetadataQueryLocalComputerScope]
        metadataQuery.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, value)
        metadataQuery.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: metadataQuery,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self, let metadataQuery = notification.object as? NSMetadataQuery else { return }
                metadataQuery.disableUpdates()
                let files = metadataQuery.results.compactMap { result -> IndexedFile? in
                    guard let item = result as? NSMetadataItem,
                          let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                          !URL(fileURLWithPath: path).lastPathComponent.hasPrefix(".") else { return nil }
                    let url = URL(fileURLWithPath: path)
                    return IndexedFile(url: url, name: url.lastPathComponent)
                }
                self.results = Array(files.prefix(12))
                metadataQuery.stop()
            }
        }
        query = metadataQuery
        metadataQuery.start()
    }

    private func stop() {
        query?.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        query = nil
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

enum SelectedTextReader {
    static func read() -> String {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused as! AXUIElement?,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &focused) == .success
        else { return "" }
        return focused as? String ?? ""
    }
}

enum WindowLayout: String, CaseIterable, Identifiable {
    case left, right, maximize, center
    var id: String { rawValue }
    var title: String {
        switch self { case .left: "左半屏"; case .right: "右半屏"; case .maximize: "最大化"; case .center: "居中" }
    }
    var symbol: String {
        switch self { case .left: "rectangle.lefthalf.filled"; case .right: "rectangle.righthalf.filled"; case .maximize: "rectangle.inset.filled"; case .center: "rectangle.center.inset.filled" }
    }
}

enum LoginItemManager {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

struct LumaBackup: Codable {
    let version: Int
    let exportedAt: Date
    let values: [String: String]
}

enum SettingsBackup {
    static let supportedKeys = [
        "Luma.showsStatusBarIcon", "Luma.recentSearchDisplayMode",
        "Luma.globalShortcut", "Luma.keywordShortcuts", "Luma.pluginConfigurations",
        "Luma.recentUsage.v1",
        "luma.stock.query-records.v1", "luma.stock.color-theme.v1", "luma.stock.data-source.v1",
        "luma.weather.locations.v1", "luma.weather.data-source.v1",
        "luma.clipboard.retention.v1", "luma.clipboard.storage-limit.v1",
        "luma.ai.providers.v1", "luma.ai.selected-provider.v1",
        "luma.translation.backend.v1", "luma.translation.provider.v1", "luma.translation.model.v1"
    ]

    static func export(defaults: UserDefaults = .standard) throws -> Data {
        var values: [String: String] = [:]
        for key in supportedKeys {
            guard let value = defaults.object(forKey: key) else { continue }
            if let data = value as? Data { values[key] = data.base64EncodedString() }
            else if let text = value as? String { values[key] = "text:\(text)" }
            else if let bool = value as? Bool { values[key] = "bool:\(bool)" }
            else if let number = value as? NSNumber { values[key] = "number:\(number.stringValue)" }
        }
        return try JSONEncoder().encode(LumaBackup(version: 1, exportedAt: Date(), values: values))
    }

    static func restore(_ data: Data, defaults: UserDefaults = .standard) throws {
        let backup = try JSONDecoder().decode(LumaBackup.self, from: data)
        guard backup.version == 1 else { return }
        for (key, value) in backup.values where supportedKeys.contains(key) {
            if value.hasPrefix("text:") { defaults.set(String(value.dropFirst(5)), forKey: key) }
            else if value.hasPrefix("bool:") { defaults.set(String(value.dropFirst(5)) == "true", forKey: key) }
            else if value.hasPrefix("number:"), let number = Int(String(value.dropFirst(7))) { defaults.set(number, forKey: key) }
            else if let data = Data(base64Encoded: value) { defaults.set(data, forKey: key) }
        }
    }
}
