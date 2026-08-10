import SwiftUI

struct AIManagementView: View {
    @ObservedObject var settings: AISettings
    @State private var revealsAPIKey = false
    @State private var connectionState: ConnectionState = .idle

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            providerSidebar
            Divider()
            providerDetail
        }
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1)))
        .onChange(of: settings.selectedProviderID) {
            revealsAPIKey = false
            connectionState = .idle
        }
    }

    private var providerSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("供应商", "Providers"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 12)

            ForEach(settings.providers) { provider in
                Button {
                    settings.selectedProviderID = provider.id
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "shippingbox")
                            .foregroundStyle(provider.isEnabled ? Color.accentColor : Color.secondary)
                        Text(provider.name.isEmpty ? L10n.text("未命名供应商", "Unnamed Provider") : provider.name)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Circle()
                            .fill(provider.isEnabled ? Color.green : Color.secondary.opacity(0.35))
                            .frame(width: 7, height: 7)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        settings.selectedProviderID == provider.id
                            ? Color.accentColor.opacity(0.11)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                _ = settings.addProvider()
            } label: {
                Label(L10n.text("添加供应商", "Add Provider"), systemImage: "plus")
            }
            .buttonStyle(LumaTextButtonStyle())
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 175, alignment: .topLeading)
    }

    @ViewBuilder
    private var providerDetail: some View {
        if let provider = settings.selectedProvider {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    TextField(L10n.text("供应商名称", "Provider Name"), text: providerBinding(provider.id, \.name))
                        .textFieldStyle(LumaTextFieldStyle(height: 34))
                        .font(.title3.bold())
                    Toggle(L10n.text("启用", "Enable"), isOn: providerBinding(provider.id, \.isEnabled))
                        .toggleStyle(LumaToggleStyle())
                    Button(role: .destructive) {
                        settings.removeProvider(id: provider.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(LumaIconButtonStyle())
                    .help(L10n.text("删除供应商", "Delete Provider"))
                }

                fieldGroup("Base URL") {
                    TextField("https://api.example.com/v1", text: providerBinding(provider.id, \.baseURL))
                        .textFieldStyle(LumaTextFieldStyle())
                }

                fieldGroup(L10n.text("API 格式", "API Format")) {
                    LumaMenuPicker(
                        selection: providerBinding(provider.id, \.apiFormat),
                        values: AIAPIFormat.allCases,
                        title: { $0.title }
                    )
                }

                fieldGroup(L10n.text(
                    "API Key（存储在 macOS 钥匙串）",
                    "API Key (stored in macOS Keychain)"
                )) {
                    HStack(spacing: 8) {
                        Group {
                            if revealsAPIKey {
                                TextField("API Key", text: apiKeyBinding(provider.id))
                            } else {
                                SecureField("API Key", text: apiKeyBinding(provider.id))
                            }
                        }
                        .textFieldStyle(LumaTextFieldStyle())
                        Button {
                            revealsAPIKey.toggle()
                        } label: {
                            Image(systemName: revealsAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(LumaIconButtonStyle())
                        .help(revealsAPIKey
                            ? L10n.text("隐藏 API Key", "Hide API Key")
                            : L10n.text("显示 API Key", "Show API Key"))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("模型列表", "Models"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        ForEach(provider.models) { model in
                            HStack(spacing: 8) {
                                TextField(
                                    L10n.text("模型名称", "Model Name"),
                                    text: modelNameBinding(provider.id, model.id)
                                )
                                    .textFieldStyle(LumaTextFieldStyle())
                                TextField(
                                    L10n.text("上下文", "Context"),
                                    value: modelContextBinding(provider.id, model.id),
                                    format: .number
                                )
                                .textFieldStyle(LumaTextFieldStyle())
                                .frame(width: 92)
                                .help(L10n.text("上下文窗口（tokens）", "Context window (tokens)"))
                                Button(role: .destructive) {
                                    settings.removeModel(providerID: provider.id, modelID: model.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red.opacity(0.8))
                                }
                                .buttonStyle(LumaIconButtonStyle())
                            }
                            .padding(9)
                            if model.id != provider.models.last?.id { Divider() }
                        }
                    }
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1)))

                    HStack {
                        Button {
                            _ = settings.addModel(to: provider.id)
                        } label: {
                            Label(L10n.text("添加模型", "Add Model"), systemImage: "plus")
                        }
                        .buttonStyle(LumaTextButtonStyle(height: 28))

                        Button {
                            testConnection(provider: provider)
                        } label: {
                            if connectionState == .testing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(L10n.text("测试连接", "Test Connection"), systemImage: "bolt.horizontal.circle")
                            }
                        }
                        .buttonStyle(LumaTextButtonStyle(height: 28))
                        .disabled(connectionState == .testing || testTarget(for: provider) == nil)

                        connectionStatus
                        Spacer()
                    }
                    .controlSize(.small)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView(
                L10n.text("还没有 AI 供应商", "No AI Providers"),
                systemImage: "brain.head.profile",
                description: Text(L10n.text(
                    "点击左侧“添加供应商”开始配置",
                    "Click Add Provider on the left to get started"
                ))
            )
            .frame(maxWidth: .infinity, minHeight: 420)
        }
    }

    private func fieldGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func providerBinding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<AIProviderConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { settings.provider(id: id)![keyPath: keyPath] },
            set: { value in settings.updateProvider(id: id) { $0[keyPath: keyPath] = value } }
        )
    }

    private func apiKeyBinding(_ providerID: UUID) -> Binding<String> {
        Binding(
            get: { settings.apiKey(for: providerID) },
            set: { settings.setAPIKey($0, for: providerID) }
        )
    }

    private func modelNameBinding(_ providerID: UUID, _ modelID: UUID) -> Binding<String> {
        Binding(
            get: { settings.provider(id: providerID)?.models.first(where: { $0.id == modelID })?.name ?? "" },
            set: { value in settings.updateModel(providerID: providerID, modelID: modelID) { $0.name = value } }
        )
    }

    private func modelContextBinding(_ providerID: UUID, _ modelID: UUID) -> Binding<Int> {
        Binding(
            get: { settings.provider(id: providerID)?.models.first(where: { $0.id == modelID })?.contextWindow ?? 0 },
            set: { value in
                settings.updateModel(providerID: providerID, modelID: modelID) {
                    $0.contextWindow = max(1, value)
                }
            }
        )
    }

    private func testTarget(for provider: AIProviderConfiguration) -> AIRequestTarget? {
        guard let model = provider.models.first, !provider.baseURL.isEmpty else { return nil }
        let key = settings.apiKey(for: provider.id)
        guard !key.isEmpty else { return nil }
        return AIRequestTarget(provider: provider, model: model, apiKey: key)
    }

    private func testConnection(provider: AIProviderConfiguration) {
        guard let target = testTarget(for: provider) else { return }
        connectionState = .testing
        Task {
            do {
                _ = try await AIService().testConnection(target: target)
                connectionState = .success
            } catch {
                connectionState = .failure(error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch connectionState {
        case .idle, .testing:
            EmptyView()
        case .success:
            Label(L10n.text("连接成功", "Connected"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failure(let message):
            Text(message)
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(2)
        }
    }

    private enum ConnectionState: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }
}

struct TranslationSettingsView: View {
    @ObservedObject var settings: TranslationSettings
    @ObservedObject var aiSettings: AISettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("翻译引擎", "Translation Engine"))
                    .font(.headline)
                HStack(spacing: 8) {
                    ForEach(TranslationBackend.allCases) { backend in
                        LumaSelectionButton(
                            title: backend.title,
                            isSelected: settings.backend == backend,
                            action: { settings.setBackend(backend) }
                        )
                    }
                }
                .frame(maxWidth: 360)
            }

            if settings.backend == .ai {
                VStack(alignment: .leading, spacing: 14) {
                    if aiSettings.enabledProviders.isEmpty {
                        ContentUnavailableView(
                            L10n.text("没有可用的 AI 供应商", "No Available AI Providers"),
                            systemImage: "exclamationmark.triangle",
                            description: Text(L10n.text(
                                "请先在“AI 管理”中填写 API Key、模型并启用供应商",
                                "Add an API key and model in AI settings, then enable the provider"
                            ))
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        formRow(L10n.text("AI 供应商", "AI Provider")) {
                            LumaMenuPicker(
                                selection: providerBinding,
                                values: aiSettings.enabledProviders.map { Optional($0.id) },
                                title: { providerID in
                                    guard let providerID else { return L10n.text("请选择", "Select") }
                                    return aiSettings.enabledProviders
                                        .first(where: { $0.id == providerID })?.name ?? L10n.text("请选择", "Select")
                                }
                            )
                            .frame(maxWidth: 360)
                        }

                        formRow(L10n.text("翻译模型", "Translation Model")) {
                            LumaMenuPicker(
                                selection: modelBinding,
                                values: (settings.selectedProvider?.models ?? []).map { Optional($0.id) },
                                title: { modelID in
                                    guard let modelID else { return L10n.text("请选择", "Select") }
                                    return settings.selectedProvider?.models
                                        .first(where: { $0.id == modelID })?.name ?? L10n.text("请选择", "Select")
                                }
                            )
                            .frame(maxWidth: 360)
                        }

                        HStack(spacing: 7) {
                            Image(systemName: settings.requestTarget == nil ? "exclamationmark.circle" : "checkmark.circle.fill")
                            Text(settings.requestTarget == nil
                                 ? L10n.text(
                                    "当前配置不可用，请检查启用状态、模型和 API Key",
                                    "The configuration is unavailable. Check the provider, model, and API key."
                                 )
                                 : L10n.text(
                                    "翻译插件将使用 \(settings.selectedProvider?.name ?? "") / \(settings.selectedModel?.name ?? "")",
                                    "Translation will use \(settings.selectedProvider?.name ?? "") / \(settings.selectedModel?.name ?? "")"
                                 ))
                        }
                        .font(.caption)
                        .foregroundStyle(settings.requestTarget == nil ? Color.orange : Color.green)
                    }
                }
                .padding(16)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1)))
            } else {
                Label(
                    L10n.text(
                        "使用 macOS 自带 Translation 服务，翻译时会显示系统翻译面板。",
                        "Uses the built-in macOS Translation service and presents the system translation panel."
                    ),
                    systemImage: "apple.logo"
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backendBinding: Binding<TranslationBackend> {
        Binding(get: { settings.backend }, set: settings.setBackend)
    }

    private var providerBinding: Binding<UUID?> {
        Binding(get: { settings.providerID }, set: settings.setProvider)
    }

    private var modelBinding: Binding<UUID?> {
        Binding(get: { settings.modelID }, set: settings.setModel)
    }

    private func formRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Text(label)
                .font(.callout.weight(.medium))
                .frame(width: 90, alignment: .leading)
            content()
            Spacer()
        }
    }
}
