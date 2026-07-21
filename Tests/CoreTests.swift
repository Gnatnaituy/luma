import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI

@main
enum CoreTests {
    @MainActor
    static func main() async throws {
        try expect(ExpressionEvaluator.evaluate("2 + 3 * 4") == 14, "operator precedence")
        try expect(ExpressionEvaluator.evaluate("2 ^ 3 ^ 2") == 512, "right-associative power")
        try expect(ExpressionEvaluator.evaluate("sqrt(81) + abs(-4)") == 13, "functions")

        do {
            _ = try ExpressionEvaluator.evaluate("4 / 0")
            throw TestFailure("division by zero must fail")
        } catch ExpressionError.divisionByZero {
            // Expected.
        }

        let formatted = try JSONTool.format("{\"b\":2,\"a\":1}", pretty: true)
        try expect(formatted.contains("\n"), "pretty JSON")
        try expect(try JSONTool.format("\"Luma\"", pretty: false) == "\"Luma\"", "JSON fragments")

        var highlightedJSON = "{\"name\":\"Luma\",\"native\":true,\"count\":7}"
        let editor = JSONSyntaxEditor(text: Binding(get: { highlightedJSON }, set: { highlightedJSON = $0 }))
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView()
        textView.string = highlightedJSON
        coordinator.applyHighlighting(to: textView)
        let source = highlightedJSON as NSString
        let keyIndex = source.range(of: "name").location
        let stringIndex = source.range(of: "Luma").location
        let literalIndex = source.range(of: "true").location
        let keyColor = textView.textStorage?.attribute(.foregroundColor, at: keyIndex, effectiveRange: nil) as? NSColor
        let stringColor = textView.textStorage?.attribute(.foregroundColor, at: stringIndex, effectiveRange: nil) as? NSColor
        let literalColor = textView.textStorage?.attribute(.foregroundColor, at: literalIndex, effectiveRange: nil) as? NSColor
        try expect(keyColor != nil && stringColor != nil && literalColor != nil, "JSON syntax colors present")
        try expect(keyColor != stringColor && stringColor != literalColor, "JSON syntax token colors differ")

        let encoded = CodeTool.base64Encode("Luma 原生")
        try expect(CodeTool.base64Decode(encoded) == "Luma 原生", "Base64 round trip")
        try expect(
            CodeTool.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "SHA-256"
        )

        let password = PasswordTool.generate(length: 32, uppercase: true, digits: true, symbols: true)
        try expect(password.count == 32, "password length")
        try expect(password.allSatisfy { !$0.isWhitespace }, "password alphabet")
        try expect(PasswordTool.generate(length: 4, uppercase: false, digits: false, symbols: false).count == 6, "password minimum")
        try expect(PasswordTool.generate(length: 99, uppercase: true, digits: true, symbols: true).count == 32, "password maximum")

        try expect(try StockSymbolParser.parse("AAPL").providerCode == "usAAPL", "US stock symbol")
        try expect(try StockSymbolParser.parse("600115.SS").providerCode == "sh600115", "Shanghai stock symbol")
        try expect(try StockSymbolParser.parse("002594").canonical == "002594.SZ", "Shenzhen stock inference")
        try expect(try StockSymbolParser.parse("700.HK").canonical == "00700.HK", "Hong Kong stock padding")

        var quote = Array(repeating: "", count: 48)
        quote[1] = "中国东航"
        quote[2] = "600115"
        quote[3] = "3.51"
        quote[4] = "3.46"
        quote[5] = "3.48"
        quote[6] = "1000"
        quote[30] = "20260720114041"
        quote[31] = "0.05"
        quote[32] = "1.45"
        quote[33] = "3.53"
        quote[34] = "3.45"
        let fixture: [String: Any] = [
            "code": 0,
            "msg": "",
            "data": [
                "sh600115": [
                    "qfqday": [["2026-07-17", "3.46", "3.50"], ["2026-07-20", "3.48", "3.51"]],
                    "qt": quote
                ]
            ]
        ]
        let fixtureData = try JSONSerialization.data(withJSONObject: fixture)
        let stock = try TencentStockService.parse(data: fixtureData, symbol: StockSymbolParser.parse("600115.SS"))
        try expect(stock.name == "中国东航" && stock.points.count == 2, "stock response parsing")
        let savedStock = try JSONDecoder().decode(StockSnapshot.self, from: JSONEncoder().encode(stock))
        try expect(savedStock == stock, "stock query record persistence")
        try expect(
            StockDataSource.allCases.map(\.title) == ["腾讯财经", "东方财富", "新浪财经"],
            "stock settings exposes three selectable data sources"
        )
        try expect(
            !LauncherPanelDismissalPolicy.shouldDismissOnResignKey(
                isPresentingSheet: true,
                hasAttachedSheet: true
            ),
            "launcher remains visible while a sheet is presented"
        )
        try expect(
            LauncherPanelDismissalPolicy.shouldDismissOnResignKey(
                isPresentingSheet: false,
                hasAttachedSheet: false
            ),
            "launcher dismisses after genuinely losing focus"
        )

        let eastMoneyFixture: [String: Any] = [
            "rc": 0,
            "data": [
                "f43": 352, "f44": 353, "f45": 346, "f46": 351, "f47": 177_773_264,
                "f58": "中国东航", "f59": 2, "f60": 351, "f169": 1, "f170": 28,
                "f86": 1_784_534_899
            ]
        ]
        let eastMoneyData = try JSONSerialization.data(withJSONObject: eastMoneyFixture)
        let eastMoneyStock = try EastMoneyStockService.parse(
            data: eastMoneyData,
            symbol: StockSymbolParser.parse("600115.SS")
        )
        try expect(
            eastMoneyStock.name == "中国东航"
                && eastMoneyStock.price == 3.52
                && eastMoneyStock.previousClose == 3.51
                && abs(eastMoneyStock.changePercent - 0.28) < 0.0001,
            "East Money quote parsing respects provider precision"
        )

        let sinaLine = "var hq_str_sh600115=\"中国东航,3.510,3.510,3.520,3.530,3.460,0,0,177773264,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2026-07-20,15:34:59\";"
        let sinaStock = try SinaStockService.parse(
            text: sinaLine,
            symbol: StockSymbolParser.parse("600115.SS")
        )
        try expect(
            sinaStock.name == "中国东航"
                && sinaStock.price == 3.52
                && sinaStock.quoteTime == "2026-07-20 15:34:59",
            "Sina quote parsing supports mainland market responses"
        )

        let stockSuiteName = "app.luma.stock-tests." + UUID().uuidString
        let stockDefaults = UserDefaults(suiteName: stockSuiteName)!
        stockDefaults.removePersistentDomain(forName: stockSuiteName)
        defer { stockDefaults.removePersistentDomain(forName: stockSuiteName) }
        let stockThemeStore = StockStore(records: [], defaults: stockDefaults)
        try expect(stockThemeStore.colorTheme == .greenUpRedDown, "default stock color theme")
        stockThemeStore.setColorTheme(.redUpGreenDown)
        stockThemeStore.setDataSource(.eastMoney)
        let restoredStockTheme = StockStore(records: [], defaults: stockDefaults)
        try expect(
            restoredStockTheme.colorTheme == .redUpGreenDown
                && restoredStockTheme.dataSource == .eastMoney,
            "stock color theme and selected data source persist"
        )

        let secondStock = StockSnapshot(
            symbol: "AAPL",
            providerCode: "usAAPL",
            name: "Apple",
            marketName: "美国",
            currency: "USD",
            price: 210,
            change: -1,
            changePercent: -0.47,
            previousClose: 211,
            open: 211,
            high: 212,
            low: 209,
            volume: 1_000,
            quoteTime: "20260720120000",
            points: [],
            fetchedAt: Date()
        )
        var refreshedSymbols: [String] = []
        var queryLoadingStatesDuringRefresh: [Bool] = []
        var refreshingStockStore: StockStore!
        refreshingStockStore = StockStore(
            records: [stock, secondStock],
            defaults: stockDefaults,
            fetcher: { symbol in
                queryLoadingStatesDuringRefresh.append(refreshingStockStore.isLoading)
                refreshedSymbols.append(symbol.canonical)
                let original = symbol.canonical == stock.symbol ? stock : secondStock
                return StockSnapshot(
                    symbol: original.symbol,
                    providerCode: original.providerCode,
                    name: original.name,
                    marketName: original.marketName,
                    currency: original.currency,
                    price: original.price + 1,
                    change: original.change,
                    changePercent: original.changePercent,
                    previousClose: original.previousClose,
                    open: original.open,
                    high: original.high,
                    low: original.low,
                    volume: original.volume,
                    quoteTime: original.quoteTime,
                    points: original.points,
                    fetchedAt: Date()
                )
            }
        )
        await refreshingStockStore.refreshAll()
        try expect(
            refreshedSymbols == [stock.symbol, secondStock.symbol]
                && refreshingStockStore.records.allSatisfy { snapshot in
                    snapshot.price == (snapshot.symbol == stock.symbol ? stock.price + 1 : secondStock.price + 1)
                },
            "refresh all stocks updates every saved symbol"
        )
        try expect(
            queryLoadingStatesDuringRefresh.allSatisfy { !$0 },
            "refresh all does not activate the add-stock loading state"
        )
        for index in 0..<100 {
            let target = index.isMultiple(of: 2) ? stock : secondStock
            refreshingStockStore.select(target)
            try expect(
                refreshingStockStore.selectedSymbol == target.symbol
                    && refreshingStockStore.selected?.symbol == target.symbol,
                "stock selection remains deterministic during rapid repeated switching"
            )
        }

        let linkEntry = ClipboardEntry(payload: .link(URL(string: "https://example.com")!))
        try expect(linkEntry.kind == .link && linkEntry.title == "https://example.com", "clipboard link classification")
        let fileEntry = ClipboardEntry(payload: .files([URL(fileURLWithPath: "/tmp/Luma.png")]))
        try expect(fileEntry.kind == .file && fileEntry.title == "Luma.png", "clipboard file classification")
        let imageEntry = ClipboardEntry(payload: .image(ClipboardImage(data: Data([0x89, 0x50, 0x4E, 0x47]))))
        try expect(imageEntry.kind == .image, "clipboard image classification")
        let plainEntry = ClipboardEntry(payload: .text("temporary"))
        let clipboard = ClipboardMonitor(entries: [linkEntry, plainEntry])
        clipboard.toggleFavorite(linkEntry)
        try expect(clipboard.filteredEntries(.favorites).count == 1, "clipboard favorites filter")
        clipboard.clearHistory()
        try expect(clipboard.entries == [ClipboardEntry(id: linkEntry.id, payload: linkEntry.payload, copiedAt: linkEntry.copiedAt, isFavorite: true)], "clipboard clear preserves favorites")

        try expect(
            ClipboardPasteShortcut.keyCode == CGKeyCode(kVK_ANSI_V)
                && ClipboardPasteShortcut.eventFlags == .maskCommand,
            "clipboard double-click emits Command-V to the previous application"
        )

        _ = NSApplication.shared
        let layoutClipboard = ClipboardMonitor(entries: [plainEntry, linkEntry])
        let filledTopInset = try topVisualInset(
            ClipboardPluginView(clipboard: layoutClipboard, initialFilter: .all)
        )
        let emptyTopInset = try topVisualInset(
            ClipboardPluginView(clipboard: layoutClipboard, initialFilter: .image)
        )
        try expect(
            abs(filledTopInset - emptyTopInset) <= 2,
            "clipboard category layout stays vertically anchored: filled=\(filledTopInset), empty=\(emptyTopInset)"
        )

        let validPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII=")!
        let expandableImageEntry = ClipboardEntry(payload: .image(ClipboardImage(data: validPNG)))
        let imageClipboard = ClipboardMonitor(entries: [expandableImageEntry])
        let collapsedImageHeight = fittingHeight(
            ClipboardEntryRow(entry: expandableImageEntry, clipboard: imageClipboard),
            width: 650
        )
        let expandedImageHeight = fittingHeight(
            ClipboardEntryRow(entry: expandableImageEntry, clipboard: imageClipboard, initiallyExpanded: true),
            width: 650
        )
        try expect(expandedImageHeight > collapsedImageHeight + 100, "clipboard image expands to page width")

        let pluginSuiteName = "app.luma.plugin-tests." + UUID().uuidString
        let pluginDefaults = UserDefaults(suiteName: pluginSuiteName)!
        pluginDefaults.removePersistentDomain(forName: pluginSuiteName)
        defer { pluginDefaults.removePersistentDomain(forName: pluginSuiteName) }
        let pluginSettings = PluginSettings(defaults: pluginDefaults)
        let nativeBorderlessEditor = BorderlessTextEditor.makeScrollView(text: "Luma", delegate: nil)
        try expect(
            nativeBorderlessEditor.borderType == .noBorder
                && !nativeBorderlessEditor.hasVerticalScroller
                && !nativeBorderlessEditor.hasHorizontalScroller,
            "translation editor exposes only the SwiftUI outer border"
        )
        try expect(
            SettingsSection.allCases.map(\.title) == ["快捷键管理", "插件关键词管理", "剪贴板设置", "AI 管理", "翻译设置", "股票设置"],
            "settings navigation includes clipboard, AI, and translation management"
        )
        try expect(
            Plugin.allCases.allSatisfy { pluginSettings.isEnabled($0) && pluginSettings.keywords(for: $0) == $0.keywords },
            "plugins start enabled with their default keyword lists"
        )

        let aiSuiteName = "app.luma.ai-tests." + UUID().uuidString
        let aiDefaults = UserDefaults(suiteName: aiSuiteName)!
        aiDefaults.removePersistentDomain(forName: aiSuiteName)
        defer { aiDefaults.removePersistentDomain(forName: aiSuiteName) }
        let secretStore = InMemoryAISecretStore()
        let aiSettings = AISettings(defaults: aiDefaults, secrets: secretStore)
        let deepSeekID = AISettings.deepSeekProviderID
        guard let deepSeek = aiSettings.provider(id: deepSeekID),
              let deepSeekModel = deepSeek.models.first else {
            throw TestFailure("default DeepSeek provider exists")
        }
        try expect(
            deepSeek.baseURL == "https://api.deepseek.com/anthropic"
                && deepSeek.apiFormat == .anthropicMessages
                && deepSeek.models.map(\.name) == ["deepseek-v4-pro", "deepseek-v4-flash"],
            "AI management includes the official DeepSeek Anthropic-compatible defaults"
        )
        aiSettings.updateProvider(id: deepSeekID) { $0.isEnabled = true }
        aiSettings.setAPIKey("sk-secret-not-in-defaults", for: deepSeekID)
        try expect(
            !aiDefaults.dictionaryRepresentation().description.contains("sk-secret-not-in-defaults"),
            "AI API keys are excluded from UserDefaults"
        )

        let anthropicTarget = AIRequestTarget(
            provider: aiSettings.provider(id: deepSeekID)!,
            model: deepSeekModel,
            apiKey: "test-key"
        )
        let anthropicRequest = try AIService.makeRequest(
            systemPrompt: "system",
            userPrompt: "hello",
            target: anthropicTarget
        )
        try expect(
            anthropicRequest.url?.absoluteString == "https://api.deepseek.com/anthropic/v1/messages"
                && anthropicRequest.value(forHTTPHeaderField: "x-api-key") == "test-key"
                && anthropicRequest.value(forHTTPHeaderField: "Authorization") == nil,
            "Anthropic-compatible requests use the correct endpoint and authentication"
        )
        let anthropicFixture = Data(#"{"content":[{"type":"text","text":"你好"}]}"#.utf8)
        try expect(
            try AIService.parseResponse(anthropicFixture, format: .anthropicMessages) == "你好",
            "Anthropic response text parsing"
        )

        guard let byteDance = aiSettings.provider(id: AISettings.byteDanceProviderID),
              let byteDanceModel = byteDance.models.first else {
            throw TestFailure("default ByteDance provider exists")
        }
        let openAITarget = AIRequestTarget(provider: byteDance, model: byteDanceModel, apiKey: "ark-key")
        let openAIRequest = try AIService.makeRequest(
            systemPrompt: "system",
            userPrompt: "hello",
            target: openAITarget
        )
        try expect(
            openAIRequest.url?.absoluteString == "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
                && openAIRequest.value(forHTTPHeaderField: "Authorization") == "Bearer ark-key",
            "OpenAI-compatible requests use the Volcano Ark endpoint and bearer authentication"
        )
        let openAIFixture = Data(#"{"choices":[{"message":{"content":"你好"}}]}"#.utf8)
        try expect(
            try AIService.parseResponse(openAIFixture, format: .openAIChatCompletions) == "你好",
            "OpenAI response text parsing"
        )

        let translationSettings = TranslationSettings(aiSettings: aiSettings, defaults: aiDefaults)
        translationSettings.setBackend(.ai)
        translationSettings.setProvider(deepSeekID)
        translationSettings.setModel(deepSeekModel.id)
        let restoredAISettings = AISettings(defaults: aiDefaults, secrets: secretStore)
        let restoredTranslationSettings = TranslationSettings(aiSettings: restoredAISettings, defaults: aiDefaults)
        try expect(
            restoredTranslationSettings.backend == .ai
                && restoredTranslationSettings.providerID == deepSeekID
                && restoredTranslationSettings.modelID == deepSeekModel.id
                && restoredTranslationSettings.requestTarget?.apiKey == "sk-secret-not-in-defaults",
            "translation AI provider and model selection persist"
        )

        let appFixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaAppIndexTests-" + UUID().uuidString, isDirectory: true)
        let fakeSafari = appFixtureRoot.appendingPathComponent("Safari.app", isDirectory: true)
        let fakeUtilities = appFixtureRoot.appendingPathComponent("Utilities", isDirectory: true)
        let fakeTerminal = fakeUtilities.appendingPathComponent("Terminal.app", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeSafari, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeTerminal, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: appFixtureRoot) }
        let scannedApplications = InstalledAppIndex.scan(roots: [appFixtureRoot])
        try expect(
            Set(scannedApplications.map(\.name)) == Set(["Safari", "Terminal"]),
            "installed app index scans top-level and nested macOS apps"
        )
        let installedApps = InstalledAppIndex(applications: scannedApplications)
        let recentSuiteName = "app.luma.recent-tests." + UUID().uuidString
        let recentDefaults = UserDefaults(suiteName: recentSuiteName)!
        recentDefaults.removePersistentDomain(forName: recentSuiteName)
        defer { recentDefaults.removePersistentDomain(forName: recentSuiteName) }
        let recentUsage = RecentUsageStore(defaults: recentDefaults)
        var openedApplicationURL: URL?
        let navigationModel = LauncherModel(
            clipboard: ClipboardMonitor(entries: []),
            pluginSettings: pluginSettings,
            installedApps: installedApps,
            recentUsage: recentUsage,
            applicationOpener: { url in
                openedApplicationURL = url
                return true
            }
        )
        navigationModel.prepareForPresentation()
        try expect(navigationModel.presentation == .search && navigationModel.preferredWindowHeight == 58, "launcher opens a thinner search-only panel")
        navigationModel.query = "json"
        try expect(navigationModel.presentation == .results && navigationModel.preferredWindowHeight == 430, "launcher expands for results")
        navigationModel.activateSelected()
        try expect(navigationModel.presentation == .plugin && navigationModel.selectedPlugin == .json, "search opens a single tool")
        try expect(recentUsage.items.first?.plugin == .json, "opening a plugin records it as recently used")
        navigationModel.returnToSearch()
        try expect(
            navigationModel.recentItems.first?.plugin == .json
                && navigationModel.preferredWindowHeight == CGFloat(96 + navigationModel.recentItems.count * 52),
            "recent plugins appear below the search field and expand the search panel"
        )
        for index in 0..<10 {
            let recentAppURL = appFixtureRoot
                .appendingPathComponent("RecentApp\(index).app", isDirectory: true)
            try FileManager.default.createDirectory(at: recentAppURL, withIntermediateDirectories: true)
            recentUsage.record(
                application: InstalledApplication(
                    url: recentAppURL,
                    name: "Recent App \(index)",
                    bundleIdentifier: "app.luma.recent.\(index)"
                )
            )
        }
        try expect(
            navigationModel.recentItems.count == 9
                && navigationModel.preferredWindowHeight == CGFloat(96 + 9 * 52),
            "search page shows at most nine recent items and fits them without scrolling"
        )
        let recentHosting = NSHostingView(
            rootView: RecentItemsView(model: navigationModel)
                .frame(width: 920, height: navigationModel.preferredWindowHeight - 58)
        )
        recentHosting.layoutSubtreeIfNeeded()
        try expect(!containsScrollView(in: recentHosting), "recent usage fits its content without a scroll container")
        navigationModel.showSettings()
        try expect(navigationModel.presentation == .settings && navigationModel.selectedPlugin == nil, "settings is a secondary page")
        navigationModel.query = "password"
        try expect(navigationModel.presentation == .results && !navigationModel.isShowingSettings, "typing leaves settings for search")

        navigationModel.returnToSearch()
        let searchBridge = LauncherSearchField(
            text: Binding(get: { navigationModel.query }, set: { navigationModel.query = $0 }),
            focusRequest: 0,
            onSubmit: navigationModel.activateSelected,
            onMove: navigationModel.moveSelection,
            onEscape: { _ = navigationModel.handleEscape() }
        )
        let searchCoordinator = searchBridge.makeCoordinator()
        let nativeSearchField = NSSearchField()
        LauncherSearchField.configure(nativeSearchField, coordinator: searchCoordinator)
        try expect(nativeSearchField.target == nil && nativeSearchField.action == nil, "typing does not install an incremental submit action")
        try expect(
            (nativeSearchField.cell as? NSSearchFieldCell)?.searchButtonCell == nil,
            "search field removes the overlapping native magnifier"
        )
        nativeSearchField.stringValue = "json"
        searchCoordinator.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: nativeSearchField)
        )
        try expect(
            navigationModel.query == "json" && navigationModel.presentation == .results && navigationModel.selectedPlugin == nil,
            "typing only displays matching results"
        )
        _ = searchCoordinator.control(
            nativeSearchField,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )
        try expect(
            navigationModel.presentation == .plugin && navigationModel.selectedPlugin == .json,
            "Enter explicitly opens the selected result"
        )
        navigationModel.prepareForPresentation(query: "翻译")
        try expect(
            navigationModel.query.isEmpty && navigationModel.presentation == .plugin && navigationModel.selectedPlugin == .translate,
            "keyword shortcut directly opens its only matching plugin"
        )

        pluginSettings.setEnabled(false, for: .json)
        navigationModel.query = "json"
        try expect(!navigationModel.filteredPlugins.contains(.json), "disabled plugin is removed from search results")
        pluginSettings.setEnabled(true, for: .json)
        pluginSettings.updateKeyword(for: .json, at: 0, value: "amberotter")
        navigationModel.query = "amberotter"
        try expect(navigationModel.filteredPlugins == [.json], "modified default plugin keyword participates in search")
        let customKeywordIndex = pluginSettings.addKeyword(to: .json)
        pluginSettings.updateKeyword(for: .json, at: customKeywordIndex, value: "rainbowfish")
        navigationModel.query = "rainbowfish"
        try expect(navigationModel.filteredPlugins == [.json], "new plugin keyword participates in search")
        pluginSettings.updateKeyword(for: .json, at: customKeywordIndex, value: "structuredfish")
        navigationModel.query = "structuredfish"
        try expect(navigationModel.filteredPlugins == [.json], "modified plugin keyword participates in search")
        let restoredPluginSettings = PluginSettings(defaults: pluginDefaults)
        try expect(
            restoredPluginSettings.isEnabled(.json)
                && restoredPluginSettings.keywords(for: .json).first == "amberotter"
                && restoredPluginSettings.keywords(for: .json).last == "structuredfish",
            "plugin enabled state and keyword edits persist"
        )

        navigationModel.prepareForPresentation(query: "Terminal")
        try expect(
            navigationModel.filteredApplications.map(\.name) == ["Terminal"]
                && navigationModel.filteredPlugins.isEmpty,
            "local macOS apps appear in launcher search results"
        )
        navigationModel.activateSelected()
        try expect(
            openedApplicationURL?.resolvingSymlinksInPath().path == fakeTerminal.resolvingSymlinksInPath().path,
            "Enter launches the selected macOS app"
        )
        try expect(
            recentUsage.items.first?.application?.url.resolvingSymlinksInPath().path
                == fakeTerminal.resolvingSymlinksInPath().path,
            "opening a macOS app moves it to the top of recent usage"
        )
        let restoredRecentUsage = RecentUsageStore(defaults: recentDefaults)
        try expect(
            restoredRecentUsage.items.first?.application?.name == "Terminal"
                && restoredRecentUsage.items.contains(where: { $0.plugin == .json }),
            "recent plugins and apps persist locally"
        )

        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        var windowPlacement = LauncherWindowPlacement()
        let capturedScreenVisibleFrame = NSRect(x: 0, y: 0, width: 1920, height: 1255)
        let capturedDefaultFrame = windowPlacement.frame(
            width: 920,
            height: 58,
            visibleFrame: capturedScreenVisibleFrame
        )
        try expect(
            abs(capturedDefaultFrame.minX - 567) < 1
                && abs(capturedDefaultFrame.maxY - 1034) < 1,
            "launcher defaults to the user-selected current position"
        )
        let defaultWindowFrame = windowPlacement.frame(width: 920, height: 58, visibleFrame: visibleFrame)
        try expect(
            visibleFrame.contains(defaultWindowFrame) && defaultWindowFrame.maxY > visibleFrame.midY,
            "responsive default launcher position stays visible and above center"
        )

        let controlPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 280),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        LauncherPanelAppearance.hideWindowControls(in: controlPanel)
        try expect(
            [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].allSatisfy {
                controlPanel.standardWindowButton($0)?.isHidden == true
            },
            "launcher hides all three title-bar window controls"
        )
        let draggedFrame = NSRect(x: 86, y: 620, width: 920, height: 58)
        windowPlacement.remember(frame: draggedFrame)
        let expandedAtDraggedPosition = windowPlacement.frame(width: 920, height: 600, visibleFrame: visibleFrame)
        try expect(
            expandedAtDraggedPosition.minX == draggedFrame.minX
                && expandedAtDraggedPosition.maxY == draggedFrame.maxY,
            "runtime window position keeps its top-left anchor while expanding"
        )
        let userResizedFrame = NSRect(x: 86, y: 300, width: 920, height: 420)
        windowPlacement.rememberHeight(userResizedFrame.height)
        let reopenedAtRememberedHeight = windowPlacement.frame(width: 920, height: 58, visibleFrame: visibleFrame)
        try expect(
            reopenedAtRememberedHeight.height == userResizedFrame.height,
            "launcher remembers the user-adjusted height during the current run"
        )
        let placementAfterRelaunch = LauncherWindowPlacement()
        try expect(
            placementAfterRelaunch.frame(width: 920, height: 58, visibleFrame: visibleFrame) == defaultWindowFrame,
            "window position resets after relaunch"
        )

        let shortcutSuiteName = "app.luma.shortcut-tests." + UUID().uuidString
        let shortcutDefaults = UserDefaults(suiteName: shortcutSuiteName)!
        shortcutDefaults.removePersistentDomain(forName: shortcutSuiteName)
        defer { shortcutDefaults.removePersistentDomain(forName: shortcutSuiteName) }
        let shortcutSettings = ShortcutSettings(defaults: shortcutDefaults)
        try expect(shortcutSettings.shortcut == .default && shortcutSettings.shortcut.displayString == "⌥ Space", "default global shortcut")
        let customShortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(cmdKey | optionKey)
        )
        shortcutSettings.applyHandler = { _ in false }
        shortcutSettings.bind(customShortcut)
        try expect(shortcutSettings.shortcut == .default && shortcutSettings.errorMessage != nil, "occupied shortcut is rejected")
        shortcutSettings.applyHandler = { _ in true }
        shortcutSettings.bind(customShortcut)
        let restoredShortcutSettings = ShortcutSettings(defaults: shortcutDefaults)
        try expect(restoredShortcutSettings.shortcut == customShortcut && customShortcut.displayString == "⌥⌘J", "shortcut persists")

        shortcutSettings.keywordApplyHandler = { _, _, _ in true }
        let jsonBindingID = shortcutSettings.addKeywordBinding()
        shortcutSettings.updateKeyword(id: jsonBindingID, keyword: "json")
        let jsonShortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: UInt32(controlKey | optionKey)
        )
        shortcutSettings.bindKeywordShortcut(id: jsonBindingID, shortcut: jsonShortcut)
        let clipboardBindingID = shortcutSettings.addKeywordBinding()
        shortcutSettings.updateKeyword(id: clipboardBindingID, keyword: "剪贴板")
        let clipboardShortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(controlKey | optionKey)
        )
        shortcutSettings.bindKeywordShortcut(id: clipboardBindingID, shortcut: clipboardShortcut)
        let restoredKeywordSettings = ShortcutSettings(defaults: shortcutDefaults)
        try expect(
            restoredKeywordSettings.keywordBindings == [
                KeywordShortcutBinding(id: jsonBindingID, keyword: "json", shortcut: jsonShortcut),
                KeywordShortcutBinding(id: clipboardBindingID, keyword: "剪贴板", shortcut: clipboardShortcut)
            ],
            "multiple keyword shortcut bindings persist independently"
        )
        shortcutSettings.keywordApplyHandler = { _, _, _ in false }
        let rejectedShortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(controlKey | optionKey)
        )
        shortcutSettings.bindKeywordShortcut(id: jsonBindingID, shortcut: rejectedShortcut)
        try expect(
            shortcutSettings.keywordBindings.first(where: { $0.id == jsonBindingID })?.shortcut == jsonShortcut
                && shortcutSettings.keywordErrorIDs.contains(jsonBindingID),
            "occupied keyword shortcut keeps its previous binding"
        )

        let testSuiteName = "app.luma.tests." + UUID().uuidString
        let testSettings = UserDefaults(suiteName: testSuiteName)!
        testSettings.removePersistentDomain(forName: testSuiteName)
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaClipboardTests-" + UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: storageDirectory)
            testSettings.removePersistentDomain(forName: testSuiteName)
        }
        let clipboardStorage = ClipboardStorage(directory: storageDirectory)
        let persistedEntries = [
            ClipboardEntry(payload: .text("persistent text")),
            ClipboardEntry(payload: .link(URL(string: "https://openai.com")!), isFavorite: true),
            ClipboardEntry(payload: .files([URL(fileURLWithPath: "/tmp/persistent.txt")])),
            ClipboardEntry(payload: .image(ClipboardImage(data: Data([1, 2, 3, 4]))))
        ]
        clipboardStorage.save(persistedEntries)
        let reloadedEntries = clipboardStorage.load()
        try expect(reloadedEntries.count == 4, "clipboard storage round trip")
        try expect(Set(reloadedEntries.map(\.kind)) == Set(ClipboardKind.allCases), "all clipboard kinds persisted")
        if let persistedImage = reloadedEntries.first(where: { $0.kind == .image }),
           case .image(let imageReference) = persistedImage.payload {
            try expect(imageReference.inlineData == nil && imageReference.fileURL != nil, "persisted image loads lazily")
        } else {
            throw TestFailure("persisted image reference")
        }
        let diskBackedMonitor = ClipboardMonitor(storage: clipboardStorage, settings: testSettings)
        if let fileToRemove = diskBackedMonitor.entries.first(where: { $0.kind == .file }) {
            diskBackedMonitor.remove(fileToRemove)
        }
        diskBackedMonitor.flushPersistence()
        let relaunchedMonitor = ClipboardMonitor(storage: clipboardStorage, settings: testSettings)
        try expect(relaunchedMonitor.entries.count == 3 && !relaunchedMonitor.entries.contains(where: { $0.kind == .file }), "clipboard monitor relaunch persistence")

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: now)!
        let fourMonthsAgo = calendar.date(byAdding: .month, value: -4, to: now)!
        let recentEntry = ClipboardEntry(payload: .text("recent"), copiedAt: twoMonthsAgo)
        let expiredEntry = ClipboardEntry(payload: .text("expired"), copiedAt: fourMonthsAgo)
        let oldFavorite = ClipboardEntry(payload: .text("favorite"), copiedAt: fourMonthsAgo, isFavorite: true)
        let retentionMonitor = ClipboardMonitor(
            entries: [recentEntry, expiredEntry, oldFavorite],
            settings: testSettings,
            retentionPeriod: .threeMonths,
            referenceDate: now
        )
        try expect(retentionMonitor.entries.map(\.title).sorted() == ["favorite", "recent"], "three-month retention with favorite exemption")
        try expect(ClipboardRetentionPeriod.allCases.count == 6, "all retention choices")
        let retentionExpectations: [(ClipboardRetentionPeriod, DateComponents)] = [
            (.threeDays, DateComponents(day: -3)),
            (.sevenDays, DateComponents(day: -7)),
            (.oneMonth, DateComponents(month: -1)),
            (.threeMonths, DateComponents(month: -3)),
            (.sixMonths, DateComponents(month: -6)),
            (.oneYear, DateComponents(year: -1))
        ]
        for (period, components) in retentionExpectations {
            try expect(
                period.cutoffDate(from: now, calendar: calendar) == calendar.date(byAdding: components, to: now),
                "retention cutoff " + period.rawValue
            )
        }

        let defaultRetention = ClipboardMonitor(entries: [], settings: testSettings)
        try expect(defaultRetention.retentionPeriod == .threeMonths, "default clipboard retention")
        defaultRetention.updateRetentionPeriod(.sevenDays, referenceDate: now)
        let restoredSetting = ClipboardMonitor(entries: [], settings: testSettings)
        try expect(restoredSetting.retentionPeriod == .sevenDays, "clipboard retention setting persisted")
        let shortenedRetention = ClipboardMonitor(
            entries: [recentEntry, oldFavorite],
            settings: testSettings,
            retentionPeriod: .threeMonths,
            referenceDate: now
        )
        shortenedRetention.updateRetentionPeriod(.oneMonth, referenceDate: now)
        try expect(shortenedRetention.entries == [oldFavorite], "shorter retention purges immediately")

        print("CORE_TESTS_OK")
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw TestFailure(name) }
    }

    private static func topVisualInset<V: View>(_ view: V) throws -> Int {
        let width = 715
        let height = 423
        let root = view
            .frame(width: CGFloat(width), height: CGFloat(height))
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw TestFailure("clipboard layout bitmap")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        for topInset in 0..<height {
            let y = topInset
            for x in stride(from: 8, to: width - 8, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                if color.alphaComponent > 0.5 && luminance < 0.72 {
                    return topInset
                }
            }
        }
        throw TestFailure("clipboard layout has no visible content")
    }

    private static func fittingHeight<V: View>(_ view: V, width: CGFloat) -> CGFloat {
        let hosting = NSHostingView(rootView: view.frame(width: width))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    private static func containsScrollView(in view: NSView) -> Bool {
        if view is NSScrollView { return true }
        return view.subviews.contains(where: containsScrollView(in:))
    }
}

struct TestFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { "Core test failed: \(message)" }
}
