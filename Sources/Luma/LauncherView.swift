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
                .help("返回搜索")
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
            SearchResultsView(model: model)
        case .plugin:
            if let plugin = model.selectedPlugin {
                PluginDetailView(
                    plugin: plugin,
                    clipboard: clipboard,
                    stocks: stocks,
                    weather: weather,
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

    private var horizontalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            RecentHorizontalSection(
                title: "插件",
                items: model.horizontalRecentItems(of: .plugin),
                action: activate
            )
            RecentHorizontalSection(
                title: "应用",
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

private struct RecentHorizontalSection: View {
    let title: String
    let items: [RecentUsageItem]
    let action: (RecentUsageItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    if items.isEmpty {
                        Text("暂无最近使用")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(height: 66)
                    } else {
                        ForEach(items) { item in
                            RecentHorizontalItem(item: item) {
                                action(item)
                            }
                        }
                    }
                }
            }
            .scrollClipDisabled()
            .frame(height: 66)
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
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 72, height: 66)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(item.title)
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

                    if model.filteredPlugins.isEmpty,
                       model.filteredApplications.isEmpty,
                       model.instantCalculation == nil {
                        ContentUnavailableView(
                            "没有匹配的结果",
                            systemImage: "magnifyingglass",
                            description: Text("可搜索插件、App 或输入算式")
                        )
                        .padding(.top, 60)
                    }
                }
            }
        }
        .padding(24)
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
