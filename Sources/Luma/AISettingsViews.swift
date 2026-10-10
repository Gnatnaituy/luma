import SwiftUI

/// 设置页统一的行结构：左侧标题与说明，右侧控件，行与行之间用 `Divider()` 分隔。
/// 与「剪贴板设置」「两步验证设置」的行保持同一套度量。
struct LumaSettingsRow<Control: View>: View {
    let title: String
    var description: String?
    private let control: Control

    init(
        _ title: String,
        description: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            control
        }
    }
}

/// 设置页里的说明区块：「天气设置 · 无需 API Key」使用的同一种结构。
struct LumaSettingsNote: View {
    let title: String
    let detail: String
    var symbol: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AIManagementView: View {
    @ObservedObject var settings: AISettings
    @State private var revealsAPIKey = false
    @State private var connectionState: ConnectionState = .idle

    /// 展开后的表单列宽：列表整行较宽，控件拉满会显得松散。
    private let formWidth: CGFloat = 520
    /// 展开内容与供应商名称左对齐（图标 34 + 间距 12）。
    private let configurationIndent: CGFloat = 46
    /// 「上下文」列宽度，列标题与输入框共用。
    private let modelContextWidth: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text(
                "点击供应商可展开它的配置；停用的供应商不会出现在翻译设置的可选列表中。",
                "Click a provider to expand its configuration. Disabled providers are hidden from the translation settings."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(settings.providers) { provider in
                    providerBlock(provider)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .background(Color.primary.opacity(provider.isEnabled ? 0.025 : 0.012))
                        .overlay(alignment: .bottom) { Divider() }
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(provider.isEnabled
                                      ? Color.accentColor.opacity(0.72)
                                      : Color.secondary.opacity(0.3))
                                .frame(width: 3)
                                .padding(.vertical, 14)
                        }
                }

                if settings.providers.isEmpty {
                    emptyProviders
                }

                addProviderRow
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: LumaRadius.card, style: .continuous))
            .overlay { LumaRimStroke(cornerRadius: LumaRadius.card) }
        }
        .animation(LumaMotion.quick, value: settings.selectedProviderID)
        .onChange(of: settings.selectedProviderID) {
            revealsAPIKey = false
            connectionState = .idle
        }
    }

    private func isExpanded(_ provider: AIProviderConfiguration) -> Bool {
        settings.selectedProviderID == provider.id
    }

    private func toggleExpansion(_ provider: AIProviderConfiguration) {
        settings.selectedProviderID = isExpanded(provider) ? nil : provider.id
    }

    /// 一行一个供应商，展开后紧接着显示它的配置，与「插件管理」的列表同一种排布。
    private func providerBlock(_ provider: AIProviderConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            providerHeaderRow(provider)

            if isExpanded(provider) {
                providerConfiguration(provider)
                    .padding(.top, 16)
                    .padding(.leading, configurationIndent)
            }
        }
    }

    private func providerHeaderRow(_ provider: AIProviderConfiguration) -> some View {
        HStack(spacing: 12) {
            // 展开区域只覆盖图标与名称，右侧的开关和删除各有自己的点击目标。
            Button {
                toggleExpansion(provider)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(provider.isEnabled ? Color.accentColor : Color.secondary)
                        .frame(width: 34, height: 34)
                        .background(
                            (provider.isEnabled ? Color.accentColor : Color.secondary).opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 8)
                        )

                    Text(provider.name.isEmpty
                         ? L10n.text("未命名供应商", "Unnamed Provider")
                         : provider.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded(provider) ? 90 : 0))

                    Spacer(minLength: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded(provider)
                  ? L10n.text("收起配置", "Collapse")
                  : L10n.text("展开配置", "Expand"))

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
    }

    private func providerConfiguration(_ provider: AIProviderConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            labeledField(L10n.text("供应商名称", "Provider Name")) {
                TextField(
                    L10n.text("供应商名称", "Provider Name"),
                    text: providerBinding(provider.id, \.name)
                )
                .textFieldStyle(LumaTextFieldStyle())
            }

            labeledField("Base URL") {
                TextField("https://api.example.com/v1", text: providerBinding(provider.id, \.baseURL))
                    .textFieldStyle(LumaTextFieldStyle())
            }

            // 协议说明并入标题行，避免多占一行高度；选择器本身只放协议名。
            labeledField(
                L10n.text("API 格式", "API Format") + " · " + provider.apiFormat.detail
            ) {
                LumaMenuPicker(
                    selection: providerBinding(provider.id, \.apiFormat),
                    values: AIAPIFormat.allCases,
                    title: { $0.title }
                )
                .frame(width: 220)
            }

            labeledField(L10n.text(
                "API Key（存储在 macOS 钥匙串）",
                "API Key (stored in the macOS Keychain)"
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

            Divider()

            modelsSection(provider)
        }
        .frame(width: formWidth, alignment: .leading)
    }

    private func modelsSection(_ provider: AIProviderConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                labeledCaption(L10n.text("模型列表", "Models"))
                Spacer(minLength: 12)
                Button {
                    _ = settings.addModel(to: provider.id)
                } label: {
                    Label(L10n.text("添加模型", "Add Model"), systemImage: "plus")
                }
                .buttonStyle(LumaTextButtonStyle(height: 28))
            }

            if !provider.models.isEmpty {
                modelColumnCaptions
            }

            if provider.models.isEmpty {
                emptyModels
            } else {
                VStack(spacing: 0) {
                    ForEach(provider.models) { model in
                        modelRow(provider, model: model)
                        if model.id != provider.models.last?.id {
                            Divider()
                        }
                    }
                }
                .lumaCard(cornerRadius: LumaRadius.control)
            }

            HStack(spacing: 8) {
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
                Spacer(minLength: 0)
            }
        }
    }

    /// 与模型行同宽的列标题，让「模型名称 / 上下文」两列不用占位符也能读懂。
    private var modelColumnCaptions: some View {
        HStack(spacing: 8) {
            labeledCaption(L10n.text("模型名称", "Model Name"))
                .frame(maxWidth: .infinity, alignment: .leading)
            labeledCaption(L10n.text("上下文（tokens）", "Context (tokens)"))
                .frame(width: modelContextWidth, alignment: .leading)
            Color.clear
                .frame(width: LumaChromeMetrics.iconButtonSize, height: 1)
        }
        .padding(.horizontal, 8)
    }

    private func modelRow(_ provider: AIProviderConfiguration, model: AIModelConfiguration) -> some View {
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
            .multilineTextAlignment(.trailing)
            .frame(width: modelContextWidth)
            .help(L10n.text("上下文窗口（tokens）", "Context window (tokens)"))

            Button(role: .destructive) {
                settings.removeModel(providerID: provider.id, modelID: model.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(LumaIconButtonStyle())
            .help(L10n.text("删除模型", "Delete Model"))
        }
        .padding(8)
    }

    private var emptyModels: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
                Text(L10n.text("还没有模型", "No models yet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)
            Spacer()
        }
        .lumaCard(cornerRadius: LumaRadius.control)
    }

    private var emptyProviders: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(L10n.text("还没有 AI 供应商", "No AI Providers"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// 列表最后一行的「添加供应商」，水平居中。
    private var addProviderRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                _ = settings.addProvider()
            } label: {
                Label(L10n.text("添加供应商", "Add Provider"), systemImage: "plus")
            }
            .buttonStyle(LumaTextButtonStyle())
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func labeledCaption(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func labeledField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledCaption(title)
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
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
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
    var openAISettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LumaSettingsRow(
                L10n.text("翻译引擎", "Translation Engine"),
                description: L10n.text(
                    "选择翻译时使用的服务；修改后立即对翻译插件生效。",
                    "Choose the service used for translation. Changes apply to the plugin immediately."
                )
            ) {
                HStack(spacing: 8) {
                    ForEach(TranslationBackend.allCases) { backend in
                        LumaSelectionButton(
                            title: backend.title,
                            isSelected: settings.backend == backend,
                            action: { settings.setBackend(backend) }
                        )
                        .frame(minWidth: 118)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }

            Divider()

            if settings.backend == .ai {
                aiContent
            } else {
                LumaSettingsNote(
                    title: L10n.text("由系统提供", "Provided by the System"),
                    detail: L10n.text(
                        "使用 macOS 自带 Translation 服务，翻译时显示系统翻译面板；无需 API Key 或模型配置。",
                        "Uses the built-in macOS Translation service and presents the system translation panel. No API key or model configuration is required."
                    ),
                    symbol: "apple.logo"
                )
            }
        }
        .settingsCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var aiContent: some View {
        if aiSettings.enabledProviders.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                LumaSettingsNote(
                    title: L10n.text("没有可用的 AI 供应商", "No Available AI Providers"),
                    detail: L10n.text(
                        "翻译插件只会使用已启用的供应商。请先在「AI 管理」中填写 API Key、添加模型并启用供应商。",
                        "The plugin only uses enabled providers. Add an API key and a model in AI settings, then enable the provider."
                    ),
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange
                )
                Button {
                    openAISettings()
                } label: {
                    Label(L10n.text("前往 AI 管理", "Open AI Settings"), systemImage: "brain.head.profile")
                }
                .buttonStyle(LumaTextButtonStyle())
            }
        } else {
            LumaSettingsRow(
                L10n.text("AI 供应商", "AI Provider"),
                description: L10n.text(
                    "只列出已启用的供应商。",
                    "Only enabled providers are listed."
                )
            ) {
                LumaMenuPicker(
                    selection: providerBinding,
                    values: aiSettings.enabledProviders.map { Optional($0.id) },
                    title: { providerID in
                        guard let providerID else { return L10n.text("请选择", "Select") }
                        return aiSettings.enabledProviders
                            .first(where: { $0.id == providerID })?.name ?? L10n.text("请选择", "Select")
                    }
                )
                .frame(width: 190)
            }

            Divider()

            LumaSettingsRow(
                L10n.text("翻译模型", "Translation Model"),
                description: L10n.text(
                    "该供应商用于翻译的模型。",
                    "The model this provider uses for translation."
                )
            ) {
                LumaMenuPicker(
                    selection: modelBinding,
                    values: (settings.selectedProvider?.models ?? []).map { Optional($0.id) },
                    title: { modelID in
                        guard let modelID else { return L10n.text("请选择", "Select") }
                        return settings.selectedProvider?.models
                            .first(where: { $0.id == modelID })?.name ?? L10n.text("请选择", "Select")
                    }
                )
                .frame(width: 190)
            }

            Divider()

            if let target = settings.requestTarget {
                LumaSettingsNote(
                    title: L10n.text("配置可用", "Ready"),
                    detail: L10n.text(
                        "翻译插件将使用 \(target.provider.name) / \(target.model.name)。",
                        "Translation will use \(target.provider.name) / \(target.model.name)."
                    ),
                    symbol: "checkmark.shield.fill",
                    tint: .green
                )
            } else {
                LumaSettingsNote(
                    title: L10n.text("配置不完整", "Configuration Incomplete"),
                    detail: L10n.text(
                        "请检查供应商的启用状态、模型列表与 API Key，三者齐备后翻译插件才可用。",
                        "Check the provider's enabled state, model list, and API key. All three are required."
                    ),
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }
        }
    }

    private var providerBinding: Binding<UUID?> {
        Binding(get: { settings.providerID }, set: { settings.setProvider($0) })
    }

    private var modelBinding: Binding<UUID?> {
        Binding(get: { settings.modelID }, set: { settings.setModel($0) })
    }
}
