import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese
    case english

    static let storageKey = "Luma.appLanguage"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simplifiedChinese: "中文"
        case .english: "English"
        }
    }

    var locale: Locale {
        switch self {
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }
}

enum L10n {
    private static let lock = NSLock()
    private static var activeLanguage = UserDefaults.standard
        .string(forKey: AppLanguage.storageKey)
        .flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese

    static var language: AppLanguage {
        lock.lock()
        defer { lock.unlock() }
        return activeLanguage
    }

    static var locale: Locale { language.locale }

    static func activate(_ language: AppLanguage) {
        lock.lock()
        activeLanguage = language
        lock.unlock()
    }

    static func text(_ simplifiedChinese: String, _ english: String) -> String {
        text(simplifiedChinese, english, language: language)
    }

    static func text(
        _ simplifiedChinese: String,
        _ english: String,
        language: AppLanguage
    ) -> String {
        language == .english ? english : simplifiedChinese
    }
}
