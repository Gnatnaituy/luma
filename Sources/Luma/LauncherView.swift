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
            LumaHairline()
            content
        }
        .frame(minWidth: 820, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LumaPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: LumaRadius.panel, style: .continuous))
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
        LauncherHeader(
            query: $model.query,
            focusRequest: model.focusRequest,
            showsBackButton: model.presentation == .plugin || model.presentation == .settings,
            isShowingSettings: model.isShowingSettings,
            onSubmit: model.activateSelected,
            onMove: model.moveSelection,
            onHorizontalMove: model.moveSelectionHorizontally,
            onEscape: {
                if !model.handleEscape() { dismiss() }
            },
            onBack: model.returnToSearch,
            onToggleSettings: {
                if model.isShowingSettings { model.returnToSearch() }
                else { model.showSettings() }
            }
        )
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
            RecentItemsView(model: model)
                .transition(LumaMotion.contentTransition)
        }
    }
}

enum LauncherKeyboardRouting {
    static func handlesEscape(for presentation: LauncherPresentation) -> Bool {
        presentation == .plugin || presentation == .settings
    }
}

private struct SearchResultsView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("搜索结果", "Search Results"))
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Text(L10n.text("→ 操作", "→ Actions"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 6) {
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
                .lumaCard(cornerRadius: LumaRadius.card)
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

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "return")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(RoundedRectangle(cornerRadius: LumaRadius.card, style: .continuous))
            .background(
                isSelected ? LumaTone.selectionFill : (isHovering ? LumaTone.hoverFill : Color.clear),
                in: RoundedRectangle(cornerRadius: LumaRadius.card, style: .continuous)
            )
            .overlay {
                if isSelected {
                    LumaRimStroke(cornerRadius: LumaRadius.card)
                }
            }
            .animation(LumaMotion.quick, value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(L10n.text("打开", "Open"), action: action)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch result {
        case .application(let app):
            LumaIconTile(symbol: nil, tint: .accentColor, applicationURL: app.url, size: 40)
        case .file(let file):
            Image(nsImage: LumaAppIconCache.icon(for: file.url))
                .resizable().scaledToFit().frame(width: 40, height: 40)
        default:
            LumaIconTile(symbol: symbol, tint: tint, applicationURL: nil, size: 40)
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
