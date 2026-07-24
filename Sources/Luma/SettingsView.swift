import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Identifiable {
    case application
    case shortcuts
    case pluginKeywords
    case clipboard
    case ai
    case translation
    case stocks
    case weather

    var id: String { rawValue }

    var title: String {
        switch self {
        case .application: "应用设置"
        case .shortcuts: "快捷键管理"
        case .pluginKeywords: "插件关键词管理"
        case .clipboard: "剪贴板设置"
        case .ai: "AI 管理"
        case .translation: "翻译设置"
        case .stocks: "股票设置"
        case .weather: "天气设置"
        }
    }

    var subtitle: String {
        switch self {
        case .application: "配置 Luma 的系统集成与显示方式"
        case .shortcuts: "配置全局唤起与关键词快捷键"
        case .pluginKeywords: "控制插件启用状态与搜索关键词"
        case .clipboard: "设置历史记录的本地保存时长"
        case .ai: "管理供应商、API 协议、密钥与模型"
        case .translation: "选择系统翻译或指定 AI 模型"
        case .stocks: "设置行情涨跌颜色主题"
        case .weather: "选择天气预报数据来源"
        }
    }

    var symbol: String {
        switch self {
        case .application: "app.badge"
        case .shortcuts: "keyboard"
        case .pluginKeywords: "text.badge.plus"
        case .clipboard: "clipboard"
        case .ai: "brain.head.profile"
        case .translation: "character.bubble"
        case .stocks: "chart.line.uptrend.xyaxis"
        case .weather: "cloud.sun"
        }
    }
}
struct SettingsView: View {
    @ObservedObject var applicationSettings: ApplicationSettings
    @ObservedObject var shortcuts: ShortcutSettings
    @ObservedObject var plugins: PluginSettings
    @ObservedObject var stocks: StockStore
    @ObservedObject var weather: WeatherStore
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var aiSettings: AISettings
    @ObservedObject var translationSettings: TranslationSettings
    @State private var selection: SettingsSection = .application
    @State private var backupMessage = ""

    init(
        applicationSettings: ApplicationSettings,
        shortcuts: ShortcutSettings,
        plugins: PluginSettings,
        stocks: StockStore,
        weather: WeatherStore,
        clipboard: ClipboardMonitor,
        aiSettings: AISettings,
        translationSettings: TranslationSettings,
        initialSelection: SettingsSection = .application
    ) {
        self.applicationSettings = applicationSettings
        self.shortcuts = shortcuts
        self.plugins = plugins
        self.stocks = stocks
        self.weather = weather
        self.clipboard = clipboard
        self.aiSettings = aiSettings
        self.translationSettings = translationSettings
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("设置")
                .font(.title3.bold())
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 8)

            ForEach(SettingsSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 22)
                        Text(section.title)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(selection == section ? Color.accentColor : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    .background(
                        selection == section ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 180)
        .background(Color.primary.opacity(0.025))
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(selection.title, systemImage: selection.symbol)
                        .font(.title2.bold())
                    Text(selection.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch selection {
                case .application:
                    applicationContent
                case .shortcuts:
                    shortcutContent
                case .pluginKeywords:
                    pluginContent
                case .clipboard:
                    clipboardContent
                case .ai:
                    AIManagementView(settings: aiSettings)
                case .translation:
                    TranslationSettingsView(settings: translationSettings, aiSettings: aiSettings)
                case .stocks:
                    stockContent
                case .weather:
                    weatherContent
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var applicationContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: LumaStatusIcon.image)
                    .renderingMode(.template)
                    .foregroundStyle(Color.primary)
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("状态栏图标")
                        .font(.headline)
                    Text("在 macOS 菜单栏显示 Luma，可快速打开或退出应用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle(
                    "显示",
                    isOn: Binding(
                        get: { applicationSettings.showsStatusBarIcon },
                        set: applicationSettings.setShowsStatusBarIcon
                    )
                )
                .toggleStyle(LumaToggleStyle())
            }

            Divider()

            HStack(spacing: 14) {
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text("登录时启动").font(.headline)
                    Text("登录 macOS 后自动在后台启动 Luma。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("启用", isOn: Binding(
                    get: { applicationSettings.launchesAtLogin },
                    set: applicationSettings.setLaunchesAtLogin
                ))
                .toggleStyle(LumaToggleStyle())
            }

            if !applicationSettings.loginItemError.isEmpty {
                Label(applicationSettings.loginItemError, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }

            Divider()

            HStack(spacing: 14) {
                Image(systemName: "rectangle.grid.1x2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("最近搜索展示")
                        .font(.headline)
                    Text("设置搜索首页中最近使用的插件与应用排列方式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    ForEach(RecentSearchDisplayMode.allCases) { mode in
                        LumaSelectionButton(
                            title: mode.title,
                            isSelected: applicationSettings.recentSearchDisplayMode == mode,
                            action: { applicationSettings.setRecentSearchDisplayMode(mode) }
                        )
                        .frame(width: 90)
                    }
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("配置备份").font(.headline)
                    Text("导出设置、自选项、Quicklinks 与片段；不会导出 AI 密钥。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("导入") { importBackup() }.buttonStyle(LumaTextButtonStyle())
                Button("导出") { exportBackup() }.buttonStyle(LumaTextButtonStyle())
            }
            if !backupMessage.isEmpty {
                Text(backupMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .settingsCard()
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Luma-Backup.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.export().write(to: url, options: .atomic)
            backupMessage = "已导出到 \(url.lastPathComponent)"
        } catch { backupMessage = "导出失败：\(error.localizedDescription)" }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.restore(Data(contentsOf: url))
            backupMessage = "导入完成，重启 Luma 后全部生效"
        } catch { backupMessage = "导入失败：\(error.localizedDescription)" }
    }

    private var shortcutContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            mainShortcutContent
            keywordShortcutContent
        }
    }

    private var mainShortcutContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("主快捷键")
                .font(.headline)

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("打开空白搜索框").font(.headline)
                    Text("点击右侧按钮，然后按下新的组合键。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ShortcutRecorder(shortcut: shortcuts.shortcut, onChange: shortcuts.bind)
                    .frame(width: 190, height: 34)
            }

            Divider()

            Label("快捷键至少需要包含 ⌘、⌥ 或 ⌃，修改后立即生效。", systemImage: "keyboard")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage = shortcuts.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
            }
        }
        .settingsCard()
    }

    private var keywordShortcutContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("关键词快捷键").font(.headline)
                Spacer()
                Button {
                    shortcuts.addKeywordBinding()
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .buttonStyle(LumaTextButtonStyle())
            }

            if shortcuts.keywordBindings.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "keyboard.badge.ellipsis")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("还没有关键词快捷键")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            } else {
                ForEach(shortcuts.keywordBindings) { binding in
                    keywordRow(binding)
                    if binding.id != shortcuts.keywordBindings.last?.id { Divider() }
                }
            }

            Label("唯一命中时直接进入插件；命中多个结果时展示列表供选择。", systemImage: "return")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .settingsCard()
    }

    private var pluginContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("停用的插件不会出现在搜索结果中；关键词均可直接修改或新增。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Plugin.allCases) { plugin in
                pluginRow(plugin)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color.primary.opacity(plugins.isEnabled(plugin) ? 0.025 : 0.012))
                    .overlay(alignment: .bottom) { Divider() }
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(
                                plugins.isEnabled(plugin)
                                    ? plugin.tint.opacity(0.72)
                                    : Color.secondary.opacity(0.3)
                            )
                            .frame(width: 3)
                            .padding(.vertical, 14)
                    }
            }
        }
    }

    private var clipboardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("历史保存时长")
                        .font(.headline)
                    Text("超过时长的未收藏记录会自动从本机清理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                LumaMenuPicker(
                    selection: Binding(
                        get: { clipboard.retentionPeriod },
                        set: { clipboard.updateRetentionPeriod($0) }
                    ),
                    values: ClipboardRetentionPeriod.allCases,
                    title: { $0.title }
                )
                .frame(width: 150)
            }

            Divider()

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("图片存储上限")
                        .font(.headline)
                    Text("达到上限后优先清理最旧的未收藏图片；相同图片只保存一份。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                LumaMenuPicker(
                    selection: Binding(
                        get: { clipboard.storageLimit },
                        set: { clipboard.updateStorageLimit($0) }
                    ),
                    values: ClipboardStorageLimit.allCases,
                    title: { $0.title }
                )
                .frame(width: 150)
            }

            Divider()

            Label("收藏记录不受保存时长限制，只会在手动取消收藏或删除后清理。", systemImage: "star.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label("缩短保存时长会立即清理已经过期的未收藏记录。", systemImage: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .settingsCard()
    }

    private var stockContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("行情数据源")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(StockDataSource.allCases) { source in
                    LumaSelectionButton(
                        title: source.title,
                        isSelected: stocks.dataSource == source,
                        action: { stocks.setDataSource(source) }
                    )
                }
            }

            Text(stocks.dataSource.subtitle + "。切换后请在股票插件中刷新已有记录。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("涨跌颜色")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(StockColorTheme.allCases) { theme in
                    LumaSelectionButton(
                        title: theme.title,
                        isSelected: stocks.colorTheme == theme,
                        action: { stocks.setColorTheme(theme) }
                    )
                }
            }

            Divider()

            HStack(spacing: 10) {
                Text("上涨 +2.35%")
                    .foregroundStyle(stocks.colorTheme.risingColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(stocks.colorTheme.risingColor.opacity(0.1), in: Capsule())
                Text("下跌 -1.28%")
                    .foregroundStyle(stocks.colorTheme.fallingColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(stocks.colorTheme.fallingColor.opacity(0.1), in: Capsule())
            }
            .font(.system(.caption, design: .monospaced).weight(.semibold))

            Text("颜色设置会同时应用到股票列表、涨跌幅和走势图。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .settingsCard()
    }

    private var weatherContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("天气数据源")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(WeatherDataSource.allCases) { source in
                    LumaSelectionButton(
                        title: source.title,
                        isSelected: weather.dataSource == source,
                        action: { weather.setDataSource(source) }
                    )
                }
            }

            Text(weather.dataSource.subtitle + "。切换后请在天气插件中刷新已有地点。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("无需 API Key", systemImage: "checkmark.shield")
                    .font(.subheadline.weight(.semibold))
                Text("自动模式及四个来源均无需密钥；按地点坐标或最近气象站查询，不会在后台自动轮询。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsCard()
    }

    @ViewBuilder
    private func keywordRow(_ binding: KeywordShortcutBinding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TextField(
                    "关键词，例如 json、翻译",
                    text: Binding(
                        get: {
                            shortcuts.keywordBindings.first(where: { $0.id == binding.id })?.keyword ?? ""
                        },
                        set: { shortcuts.updateKeyword(id: binding.id, keyword: $0) }
                    )
                )
                .textFieldStyle(LumaTextFieldStyle())

                ShortcutRecorder(
                    shortcut: binding.shortcut,
                    onChange: { shortcuts.bindKeywordShortcut(id: binding.id, shortcut: $0) }
                )
                .frame(width: 180, height: 34)

                Button(role: .destructive) {
                    shortcuts.removeKeywordBinding(id: binding.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(LumaIconButtonStyle())
                .help("删除")
            }

            if shortcuts.keywordErrorIDs.contains(binding.id) {
                Label("该快捷键已被占用，原绑定保持不变。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func pluginRow(_ plugin: Plugin) -> some View {
        let configuration = plugins.configuration(for: plugin)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: plugin.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(plugin.tint)
                    .frame(width: 34, height: 34)
                    .background(plugin.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.title).font(.subheadline.weight(.semibold))
                    Text(plugin.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Toggle(
                    "启用",
                    isOn: Binding(
                        get: { plugins.isEnabled(plugin) },
                        set: { plugins.setEnabled($0, for: plugin) }
                    )
                )
                .toggleStyle(LumaToggleStyle())
            }

            Text("关键词")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(configuration.keywords.indices, id: \.self) { index in
                    TextField(
                        "关键词",
                        text: Binding(
                            get: {
                                let current = plugins.keywords(for: plugin)
                                return current.indices.contains(index) ? current[index] : ""
                            },
                            set: { plugins.updateKeyword(for: plugin, at: index, value: $0) }
                        )
                    )
                    .textFieldStyle(LumaTextFieldStyle())
                }

                Button {
                    plugins.addKeyword(to: plugin)
                } label: {
                    Label("新增关键词", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LumaTextButtonStyle(height: 28))
            }
        }
        .padding(.leading, 2)
    }
}

private extension View {
    func settingsCard() -> some View {
        padding(.horizontal, 4)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) { Divider() }
    }
}
