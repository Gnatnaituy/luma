import Combine
import Foundation
import Security

enum AIAPIFormat: String, CaseIterable, Codable, Identifiable {
    case openAIChatCompletions
    case anthropicMessages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAIChatCompletions: "OpenAI Chat Completions (/chat/completions)"
        case .anthropicMessages: "Anthropic Messages (/v1/messages)"
        }
    }
}

struct AIModelConfiguration: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var contextWindow: Int

    init(id: UUID = UUID(), name: String, contextWindow: Int = 128_000) {
        self.id = id
        self.name = name
        self.contextWindow = contextWindow
    }
}

struct AIProviderConfiguration: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var baseURL: String
    var apiFormat: AIAPIFormat
    var isEnabled: Bool
    var models: [AIModelConfiguration]
}

protocol AISecretStoring {
    func value(for providerID: UUID) -> String
    @discardableResult func setValue(_ value: String, for providerID: UUID) -> Bool
    @discardableResult func removeValue(for providerID: UUID) -> Bool
}

final class KeychainAISecretStore: AISecretStoring {
    private let service = "app.luma.launcher.ai-provider"

    func value(for providerID: UUID) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    func setValue(_ value: String, for providerID: UUID) -> Bool {
        if value.isEmpty { return removeValue(for: providerID) }
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID.uuidString
        ]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = key
        item[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func removeValue(for providerID: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID.uuidString
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

final class InMemoryAISecretStore: AISecretStoring {
    private var values: [UUID: String] = [:]

    func value(for providerID: UUID) -> String { values[providerID] ?? "" }
    func setValue(_ value: String, for providerID: UUID) -> Bool {
        values[providerID] = value
        return true
    }
    func removeValue(for providerID: UUID) -> Bool {
        values[providerID] = nil
        return true
    }
}

final class AISettings: ObservableObject {
    @Published private(set) var providers: [AIProviderConfiguration]
    @Published var selectedProviderID: UUID? {
        didSet { defaults.set(selectedProviderID?.uuidString, forKey: selectedProviderKey) }
    }

    private let defaults: UserDefaults
    private let secrets: AISecretStoring
    private let providersKey = "luma.ai.providers.v1"
    private let selectedProviderKey = "luma.ai.selected-provider.v1"

    init(defaults: UserDefaults = .standard, secrets: AISecretStoring = KeychainAISecretStore()) {
        self.defaults = defaults
        self.secrets = secrets
        if let data = defaults.data(forKey: providersKey),
           let saved = try? JSONDecoder().decode([AIProviderConfiguration].self, from: data) {
            providers = saved
        } else {
            providers = Self.defaultProviders
        }
        let savedSelection = defaults.string(forKey: selectedProviderKey).flatMap(UUID.init(uuidString:))
        selectedProviderID = savedSelection.flatMap { selected in
            providers.contains(where: { $0.id == selected }) ? selected : nil
        } ?? providers.first?.id
    }

    var selectedProvider: AIProviderConfiguration? {
        provider(id: selectedProviderID)
    }

    var enabledProviders: [AIProviderConfiguration] {
        providers.filter(\.isEnabled)
    }

    func provider(id: UUID?) -> AIProviderConfiguration? {
        guard let id else { return nil }
        return providers.first(where: { $0.id == id })
    }

    func apiKey(for providerID: UUID) -> String {
        secrets.value(for: providerID)
    }

    func setAPIKey(_ value: String, for providerID: UUID) {
        _ = secrets.setValue(value, for: providerID)
        objectWillChange.send()
    }

    @discardableResult
    func addProvider() -> UUID {
        let provider = AIProviderConfiguration(
            id: UUID(),
            name: L10n.text("新供应商", "New Provider"),
            baseURL: "https://api.example.com/v1",
            apiFormat: .openAIChatCompletions,
            isEnabled: false,
            models: [AIModelConfiguration(name: "model-name")]
        )
        providers.append(provider)
        selectedProviderID = provider.id
        save()
        return provider.id
    }

    func removeProvider(id: UUID) {
        providers.removeAll { $0.id == id }
        _ = secrets.removeValue(for: id)
        if selectedProviderID == id { selectedProviderID = providers.first?.id }
        save()
    }

    func updateProvider(id: UUID, _ update: (inout AIProviderConfiguration) -> Void) {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        update(&providers[index])
        save()
    }

    @discardableResult
    func addModel(to providerID: UUID) -> UUID? {
        let model = AIModelConfiguration(name: "model-name")
        updateProvider(id: providerID) { $0.models.append(model) }
        return model.id
    }

    func updateModel(providerID: UUID, modelID: UUID, _ update: (inout AIModelConfiguration) -> Void) {
        updateProvider(id: providerID) { provider in
            guard let index = provider.models.firstIndex(where: { $0.id == modelID }) else { return }
            update(&provider.models[index])
        }
    }

    func removeModel(providerID: UUID, modelID: UUID) {
        updateProvider(id: providerID) { $0.models.removeAll { $0.id == modelID } }
    }

    func target(providerID: UUID?, modelID: UUID?) -> AIRequestTarget? {
        guard let provider = provider(id: providerID), provider.isEnabled,
              let model = provider.models.first(where: { $0.id == modelID }),
              !provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let key = apiKey(for: provider.id)
        guard !key.isEmpty else { return nil }
        return AIRequestTarget(provider: provider, model: model, apiKey: key)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(providers) {
            defaults.set(data, forKey: providersKey)
        }
    }

    static let deepSeekProviderID = UUID(uuidString: "6A92EB65-D105-4DB0-A66C-8ED48915DF01")!
    static let byteDanceProviderID = UUID(uuidString: "6A92EB65-D105-4DB0-A66C-8ED48915DF02")!

    static let defaultProviders: [AIProviderConfiguration] = [
        AIProviderConfiguration(
            id: deepSeekProviderID,
            name: "DeepSeek",
            baseURL: "https://api.deepseek.com/anthropic",
            apiFormat: .anthropicMessages,
            isEnabled: false,
            models: [
                AIModelConfiguration(name: "deepseek-v4-pro", contextWindow: 1_000_000),
                AIModelConfiguration(name: "deepseek-v4-flash", contextWindow: 1_000_000)
            ]
        ),
        AIProviderConfiguration(
            id: byteDanceProviderID,
            name: "ByteDance",
            baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            apiFormat: .openAIChatCompletions,
            isEnabled: false,
            models: [AIModelConfiguration(name: "doubao-seed-2-0-lite-260215", contextWindow: 256_000)]
        )
    ]
}

enum TranslationBackend: String, CaseIterable, Codable, Identifiable {
    case apple
    case ai

    var id: String { rawValue }
    var title: String {
        self == .apple
            ? L10n.text("Apple 系统翻译", "Apple Translation")
            : L10n.text("AI 模型翻译", "AI Model")
    }
}

final class TranslationSettings: ObservableObject {
    @Published private(set) var backend: TranslationBackend
    @Published private(set) var providerID: UUID?
    @Published private(set) var modelID: UUID?

    let aiSettings: AISettings
    private let defaults: UserDefaults
    private let backendKey = "luma.translation.backend.v1"
    private let providerKey = "luma.translation.provider.v1"
    private let modelKey = "luma.translation.model.v1"
    private var cancellable: AnyCancellable?

    init(aiSettings: AISettings, defaults: UserDefaults = .standard) {
        self.aiSettings = aiSettings
        self.defaults = defaults
        backend = TranslationBackend(rawValue: defaults.string(forKey: backendKey) ?? "") ?? .apple
        providerID = defaults.string(forKey: providerKey).flatMap(UUID.init(uuidString:))
        modelID = defaults.string(forKey: modelKey).flatMap(UUID.init(uuidString:))
        normalizeSelection()
        cancellable = aiSettings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.normalizeSelection()
                self?.objectWillChange.send()
            }
        }
    }

    var selectedProvider: AIProviderConfiguration? { aiSettings.provider(id: providerID) }
    var selectedModel: AIModelConfiguration? {
        selectedProvider?.models.first(where: { $0.id == modelID })
    }
    var requestTarget: AIRequestTarget? { aiSettings.target(providerID: providerID, modelID: modelID) }

    func setBackend(_ value: TranslationBackend) {
        backend = value
        defaults.set(value.rawValue, forKey: backendKey)
    }

    func setProvider(_ id: UUID?) {
        providerID = id
        modelID = aiSettings.provider(id: id)?.models.first?.id
        persistSelection()
    }

    func setModel(_ id: UUID?) {
        modelID = id
        persistSelection()
    }

    private func normalizeSelection() {
        let enabled = aiSettings.enabledProviders
        if !enabled.contains(where: { $0.id == providerID }) {
            providerID = enabled.first?.id
        }
        if let provider = aiSettings.provider(id: providerID),
           !provider.models.contains(where: { $0.id == modelID }) {
            modelID = provider.models.first?.id
        }
        persistSelection()
    }

    private func persistSelection() {
        defaults.set(providerID?.uuidString, forKey: providerKey)
        defaults.set(modelID?.uuidString, forKey: modelKey)
    }
}
