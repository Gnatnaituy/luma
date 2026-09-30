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
        source.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        source.set(0.35, forKey: "Luma.panelTransparency")
        source.set("secret", forKey: "app.luma.launcher.ai-provider")
        let data = try SettingsBackup.export(defaults: source)
        try SettingsBackup.restore(data, defaults: target)
        #expect(target.bool(forKey: "Luma.showsStatusBarIcon"))
        #expect(target.string(forKey: AppLanguage.storageKey) == AppLanguage.english.rawValue)
        let restoredTransparency = (target.object(forKey: "Luma.panelTransparency") as? NSNumber)?.doubleValue
        #expect(restoredTransparency != nil && abs(restoredTransparency! - 0.35) < 0.001)
        #expect(target.object(forKey: "app.luma.launcher.ai-provider") == nil)
    }
}
