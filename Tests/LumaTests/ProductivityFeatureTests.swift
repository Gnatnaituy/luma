import Foundation
import Testing

@testable import Luma

@Suite(.serialized)
struct ProductivityFeatureTests {
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
