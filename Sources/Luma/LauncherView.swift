import AppKit
import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var stocks: StockStore
    @ObservedObject var weather: WeatherStore
    @ObservedObject var applicationSettings: ApplicationSettings
    @ObservedObject var shortcutSettings: ShortcutSettings
    @ObservedObject var pluginSettings: PluginSettings
    @ObservedObject var aiSettings: AISettings
    @ObservedObject var translationSettings: TranslationSettings
    let pasteClipboardEntry: (ClipboardEntry) -> Void
    let arrangeWindow: (WindowLayout) -> Void
    let dismiss: () -> Void
    @State private var escapeMonitor: Any?

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
        .onAppear(perform: installEscapeMonitor)
        .onDisappear(perform: removeEscapeMonitor)
        .environment(\.locale, applicationSettings.language.locale)
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let commandModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            guard event.keyCode == 53,
                  event.modifierFlags.intersection(commandModifiers).isEmpty,
                  LauncherKeyboardRouting.handlesEscape(for: model.presentation) else { return event }
            DispatchQueue.main.async {
                model.returnToSearch()
            }
            return nil
        }
    }

    private func removeEscapeMonitor() {
        guard let escapeMonitor else { return }
        NSEvent.removeMonitor(escapeMonitor)
        self.escapeMonitor = nil
    }

    private var header: some View {
        HStack(spacing: 10) {
            if model.presentation == .plugin || model.presentation == .settings {
                Button(action: model.returnToSearch) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(LumaIconButtonStyle(size: 32, cornerRadius: 8))
                .help(L10n.text("返回搜索", "Back to Search"))
            } else {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .scaleEffect(1.25)
                    .accessibilityLabel("Luma")
            }

            LauncherSearchField(
                text: $model.query,
                focusRequest: model.focusRequest,
                onSubmit: model.activateSelected,
                onMove: model.moveSelection,
                onActions: model.toggleActions,
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
            .help(L10n.text("配置", "Settings"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch model.presentation {
        case .results:
            SearchResultsView(model: model)
        case .plugin:
            if let plugin = model.selectedPlugin {
                PluginDetailView(
                    plugin: plugin,
                    clipboard: clipboard,
                    stocks: stocks,
                    weather: weather,
                    translationSettings: translationSettings,
                    selectedText: model.selectedText,
                    arrangeWindow: arrangeWindow,
                    pasteClipboardEntry: pasteClipboardEntry
                )
            }
        case .settings:
            SettingsView(
                applicationSettings: applicationSettings,
                shortcuts: shortcutSettings,
                plugins: pluginSettings,
                stocks: stocks,
                weather: weather,
                clipboard: clipboard,
                aiSettings: aiSettings,
                translationSettings: translationSettings
            )
        case .search:
            RecentItemsView(
                model: model,
                displayMode: applicationSettings.recentSearchDisplayMode
            )
        }
    }
}

enum LauncherKeyboardRouting {
    static func handlesEscape(for presentation: LauncherPresentation) -> Bool {
        presentation == .plugin || presentation == .settings
    }
}

struct RecentItemsView: View {
    @ObservedObject var model: LauncherModel
    let displayMode: RecentSearchDisplayMode

    @ViewBuilder
    var body: some View {
        switch displayMode {
        case .vertical:
            verticalContent
        case .horizontal:
            horizontalContent
        }
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("最近使用", "Recently Used"))
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

    private var horizontalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            RecentHorizontalSection(
                title: L10n.text("插件", "Plugins"),
                items: model.horizontalRecentItems(of: .plugin),
                action: activate
            )
            RecentHorizontalSection(
                title: L10n.text("应用", "Applications"),
                items: model.horizontalRecentItems(of: .application),
                action: activate
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func activate(_ item: RecentUsageItem) {
        if let plugin = item.plugin {
            model.openPlugin(plugin)
        } else if let application = item.application {
            model.openApplication(application)
        }
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
                    Text(item.plugin?.title ?? item.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(item.plugin?.subtitle ?? item.subtitle)
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

private struct RecentHorizontalSection: View {
    let title: String
    let items: [RecentUsageItem]
    let action: (RecentUsageItem) -> Void

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(
                .fixed(LauncherModel.horizontalRecentItemWidth),
                spacing: LauncherModel.horizontalRecentItemSpacing
            ),
            count: LauncherModel.horizontalRecentPerRow
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            LazyVGrid(
                columns: columns,
                alignment: .leading,
                spacing: LauncherModel.horizontalRecentItemSpacing
            ) {
                if items.isEmpty {
                    Text(L10n.text("暂无最近使用", "No Recent Items"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(
                            width: LauncherModel.horizontalRecentItemWidth,
                            height: LauncherModel.horizontalRecentItemHeight
                        )
                } else {
                    ForEach(items) { item in
                        RecentHorizontalItem(item: item) {
                            action(item)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RecentHorizontalItem: View {
    let item: RecentUsageItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                icon
                Text(item.plugin?.title ?? item.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(
                width: LauncherModel.horizontalRecentItemWidth,
                height: LauncherModel.horizontalRecentItemHeight
            )
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(item.plugin?.title ?? item.title)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("搜索结果", "Search Results")).font(.title2.bold())
                Spacer()
                Text(L10n.text("→ 操作", "→ Actions"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(model.searchResults.enumerated()), id: \.element.id) { index, result in
                        UnifiedResultRow(
                            result: result,
                            isSelected: model.selectedResult == index,
                            action: { model.activate(result) }
                        )
                        .lumaContentTransition()
                    }

                    if model.searchResults.isEmpty {
                        ContentUnavailableView(
                            L10n.text("没有匹配的结果", "No Matching Results"),
                            systemImage: "magnifyingglass",
                            description: Text(L10n.text(
                                "可搜索插件、App、文件或输入算式",
                                "Search plugins, apps, files, or enter an expression"
                            ))
                        )
                        .padding(.top, 60)
                    }
                }
            }
            if model.isShowingActions {
                HStack(spacing: 8) {
                    Button { model.activateSelected() } label: {
                        Label(L10n.text("打开", "Open"), systemImage: "return")
                    }
                        .buttonStyle(LumaTextButtonStyle())
                    Button { model.copySelectedValue() } label: {
                        Label(L10n.text("复制", "Copy"), systemImage: "doc.on.doc")
                    }
                        .buttonStyle(LumaTextButtonStyle())
                    Button { model.revealSelectedInFinder() } label: {
                        Label(L10n.text("在 Finder 中显示", "Show in Finder"), systemImage: "folder")
                    }
                        .buttonStyle(LumaTextButtonStyle())
                    Spacer()
                    Text(L10n.text("再次按 → 收起", "Press → again to collapse"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(24)
        .animation(LumaMotion.standard, value: model.isShowingActions)
    }

}

private struct UnifiedResultRow: View {
    let result: LauncherSearchResult
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon
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
            .animation(LumaMotion.quick, value: isSelected)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L10n.text("打开", "Open"), action: action)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch result {
        case .application(let app):
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().scaledToFit().frame(width: 42, height: 42)
        case .file(let file):
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable().scaledToFit().frame(width: 42, height: 42)
        default:
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var title: String {
        switch result {
        case .calculation(let value): value
        case .plugin(let plugin): plugin.title
        case .application(let app): app.name
        case .file(let file): file.name
        }
    }

    private var subtitle: String {
        switch result {
        case .calculation: L10n.text("计算结果 · 回车复制", "Calculation · Press Return to copy")
        case .plugin(let plugin): plugin.subtitle
        case .application(let app): app.bundleIdentifier ?? L10n.text("macOS 应用程序", "macOS Application")
        case .file(let file): file.url.deletingLastPathComponent().path
        }
    }

    private var symbol: String {
        switch result {
        case .calculation: "equal.circle.fill"
        case .plugin(let plugin): plugin.symbol
        case .application: "app"
        case .file: "doc"
        }
    }

    private var tint: Color {
        switch result {
        case .calculation: .purple
        case .plugin(let plugin): plugin.tint
        case .application: .blue
        case .file: .gray
        }
    }
}
