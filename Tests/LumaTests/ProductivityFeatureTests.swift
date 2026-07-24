import Foundation
import Testing

@testable import Luma

@Suite(.serialized)
struct ProductivityFeatureTests {
    @Test
    @MainActor
    func quicklinksResolvePlaceholdersAndPersist() throws {
        let name = "app.luma.productivity.quicklinks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let store = QuicklinkStore(defaults: defaults)
        store.add(
            name: "GitHub 搜索",
            template: "https://github.com/search?q={query}",
            keyword: "gh"
        )
        let match = try #require(store.matches("gh native swift").first)
        #expect(match.0.name == "GitHub 搜索")
        #expect(match.1 == "native swift")
        #expect(
            match.0.resolved(query: match.1, clipboard: "", selectedText: "")?.absoluteString
                == "https://github.com/search?q=native%20swift"
        )
        #expect(QuicklinkStore(defaults: defaults).items.count == 1)
    }

    @Test
    @MainActor
    func snippetsSearchContentAndPersist() {
        let name = "app.luma.productivity.snippets." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let store = SnippetStore(defaults: defaults)
        store.add(name: "地址", content: "Shanghai Pudong", keyword: "addr")
        #expect(store.search("Pudong").first?.name == "地址")
        #expect(store.search("addr").first?.content == "Shanghai Pudong")
        #expect(SnippetStore(defaults: defaults).items.count == 1)
    }

    @Test
    func backupRoundTripExcludesSecrets() throws {
        let sourceName = "app.luma.productivity.backup.source." + UUID().uuidString
        let targetName = "app.luma.productivity.backup.target." + UUID().uuidString
        let source = UserDefaults(suiteName: sourceName)!
        let target = UserDefaults(suiteName: targetName)!
        defer {
            source.removePersistentDomain(forName: sourceName)
            target.removePersistentDomain(forName: targetName)
        }
        source.set(true, forKey: "Luma.showsStatusBarIcon")
        source.set("secret", forKey: "app.luma.launcher.ai-provider")
        let data = try SettingsBackup.export(defaults: source)
        try SettingsBackup.restore(data, defaults: target)
        #expect(target.bool(forKey: "Luma.showsStatusBarIcon"))
        #expect(target.object(forKey: "app.luma.launcher.ai-provider") == nil)
    }
}
