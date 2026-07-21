import AppKit
import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var stocks: StockStore
    @ObservedObject var applicationSettings: ApplicationSettings
    @ObservedObject var shortcutSettings: ShortcutSettings
    @ObservedObject var pluginSettings: PluginSettings
    @ObservedObject var aiSettings: AISettings
    @ObservedObject var translationSettings: TranslationSettings
    let pasteClipboardEntry: (ClipboardEntry) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.presentation != .search || !model.recentItems.isEmpty {
                Divider()
                content
            }
        }
        .frame(minWidth: 820, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if model.presentation == .plugin || model.presentation == .settings {
                Button(action: model.returnToSearch) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(LumaIconButtonStyle(size: 32, cornerRadius: 8))
                .help("返回搜索")
            } else {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .scaleEffect(1.22)
                    .shadow(color: Color.black.opacity(0.10), radius: 1, y: 0.5)
                    .frame(width: 32, height: 32)
                    .clipped()
                    .accessibilityLabel("Luma")
            }

            LauncherSearchField(
                text: $model.query,
                focusRequest: model.focusRequest,
                onSubmit: { model.activateSelected(pasteClipboardEntry: pasteClipboardEntry) },
                onMove: model.moveSelection,
                onEscape: {
                    if !model.handleEscape() { dismiss() }
                }
            )
            .padding(.horizontal, 7)
            .frame(height: 34)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }

            Button {
                if model.isShowingSettings { model.returnToSearch() }
                else { model.showSettings() }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.isShowingSettings ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(LumaIconButtonStyle(size: 32, cornerRadius: 8))
            .help("配置")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch model.presentation {
        case .results:
            SearchResultsView(model: model, pasteClipboardEntry: pasteClipboardEntry)
        case .plugin:
            if let plugin = model.selectedPlugin {
                PluginDetailView(
                    plugin: plugin,
                    clipboard: clipboard,
                    stocks: stocks,
                    translationSettings: translationSettings,
                    pasteClipboardEntry: pasteClipboardEntry
                )
            }
        case .settings:
            SettingsView(
                applicationSettings: applicationSettings,
                shortcuts: shortcutSettings,
                plugins: pluginSettings,
                stocks: stocks,
                clipboard: clipboard,
                aiSettings: aiSettings,
                translationSettings: translationSettings
            )
        case .search:
            RecentItemsView(model: model)
        }
    }
}

struct RecentItemsView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近使用")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 4) {
                ForEach(model.recentItems) { item in
                    RecentItemRow(item: item) {
                        if let plugin = item.plugin {
                            model.openPlugin(plugin)
                        } else if let application = item.application {
                            model.openApplication(application)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct RecentItemRow: View {
    let item: RecentUsageItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: item.kind == .plugin ? "arrow.right" : "arrow.up.forward.app")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
        if let plugin = item.plugin {
            Image(systemName: plugin.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(plugin.tint)
                .frame(width: 34, height: 34)
                .background(plugin.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
        } else if let application = item.application {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
        }
    }
}

private struct SearchResultsView: View {
    @ObservedObject var model: LauncherModel
    let pasteClipboardEntry: (ClipboardEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("搜索结果")
                .font(.title2.bold())
            ScrollView {
                LazyVStack(spacing: 8) {
                    if let calculation = model.instantCalculation {
                        ResultRow(
                            symbol: "equal.circle.fill",
                            tint: .purple,
                            title: calculation,
                            subtitle: "计算结果 · 回车复制",
                            isSelected: model.selectedResult == 0,
                            action: { model.clipboard.copy(calculation) }
                        )
                    }

                    ForEach(Array(model.filteredPlugins.enumerated()), id: \.element.id) { index, plugin in
                        let offset = model.instantCalculation == nil ? 0 : 1
                        ResultRow(
                            symbol: plugin.symbol,
                            tint: plugin.tint,
                            title: plugin.title,
                            subtitle: plugin.subtitle,
                            isSelected: model.selectedResult == index + offset,
                            action: { model.openPlugin(plugin) }
                        )
                    }

                    ForEach(Array(model.filteredApplications.enumerated()), id: \.element.id) { index, application in
                        let calculationOffset = model.instantCalculation == nil ? 0 : 1
                        let offset = calculationOffset + model.filteredPlugins.count
                        ApplicationResultRow(
                            application: application,
                            isSelected: model.selectedResult == index + offset,
                            action: { model.openApplication(application) }
                        )
                    }

                    ForEach(Array(model.filteredClipboardEntries.enumerated()), id: \.element.id) { index, entry in
                        let calculationOffset = model.instantCalculation == nil ? 0 : 1
                        let offset = calculationOffset
                            + model.filteredPlugins.count
                            + model.filteredApplications.count
                        ResultRow(
                            symbol: entry.kind.symbol,
                            tint: clipboardTint(for: entry.kind),
                            title: entry.searchDisplayTitle,
                            subtitle: clipboardSubtitle(for: entry),
                            isSelected: model.selectedResult == index + offset,
                            action: { pasteClipboardEntry(entry) }
                        )
                    }

                    if model.filteredPlugins.isEmpty,
                       model.filteredApplications.isEmpty,
                       model.filteredClipboardEntries.isEmpty,
                       model.instantCalculation == nil {
                        ContentUnavailableView(
                            "没有匹配的结果",
                            systemImage: "magnifyingglass",
                            description: Text("可搜索插件、App、剪贴板内容或输入算式")
                        )
                        .padding(.top, 60)
                    }
                }
            }
        }
        .padding(24)
    }

    private func clipboardTint(for kind: ClipboardKind) -> Color {
        switch kind {
        case .text: .indigo
        case .image: .pink
        case .file: .orange
        case .link: .blue
        }
    }

    private func clipboardSubtitle(for entry: ClipboardEntry) -> String {
        let favorite = entry.isFavorite ? " · 收藏" : ""
        return "剪贴板 · \(entry.kind.title)\(favorite) · \(entry.copiedAt.formatted(.dateTime.hour().minute())) · 回车粘贴"
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case application
    case shortcuts
    case pluginKeywords
    case clipboard
    case ai
    case translation
    case stocks

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
        }
    }
}

struct SettingsView: View {
    @ObservedObject var applicationSettings: ApplicationSettings
    @ObservedObject var shortcuts: ShortcutSettings
    @ObservedObject var plugins: PluginSettings
    @ObservedObject var stocks: StockStore
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var aiSettings: AISettings
    @ObservedObject var translationSettings: TranslationSettings
    @State private var selection: SettingsSection = .application

    init(
        applicationSettings: ApplicationSettings,
        shortcuts: ShortcutSettings,
        plugins: PluginSettings,
        stocks: StockStore,
        clipboard: ClipboardMonitor,
        aiSettings: AISettings,
        translationSettings: TranslationSettings,
        initialSelection: SettingsSection = .application
    ) {
        self.applicationSettings = applicationSettings
        self.shortcuts = shortcuts
        self.plugins = plugins
        self.stocks = stocks
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
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var applicationContent: some View {
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
        .settingsCard()
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

private struct ResultRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "return")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct ApplicationResultRow: View {
    let application: InstalledApplication
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(application.name).font(.headline)
                    Text(application.bundleIdentifier ?? "macOS 应用程序")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "return")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "arrow.up.forward.app")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
