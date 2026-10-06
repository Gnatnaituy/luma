import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let clipboard = ClipboardMonitor()
    private let stocks = StockStore()
    private let weather = WeatherStore()
    private let applicationSettings = ApplicationSettings()
    private let shortcutSettings = ShortcutSettings()
    private let pluginSettings = PluginSettings()
    private let aiSettings = AISettings()
    private let twoFactor = TwoFactorStore()
    private lazy var translationSettings = TranslationSettings(aiSettings: aiSettings)
    private let installedApps = InstalledAppIndex()
    private let recentUsage = RecentUsageStore()
    private let fileSearch = FileSearchIndex()
    private lazy var model = LauncherModel(
        clipboard: clipboard,
        pluginSettings: pluginSettings,
        installedApps: installedApps,
        recentUsage: recentUsage,
        fileSearch: fileSearch
    )
    private var panel: LauncherPanel?
    private var statusItem: NSStatusItem?
    private var hotKey: HotKeyManager?
    private var registeredShortcut = GlobalShortcut.default
    private var keywordHotKeys: [UUID: HotKeyManager] = [:]
    private var keywordHotKeyIdentifiers: [UUID: UInt32] = [:]
    private var nextKeywordHotKeyIdentifier: UInt32 = 100
    private var windowPlacement = LauncherWindowPlacement()
    private var panelSizing = LauncherPanelSizing()
    private var panelMinimumHeight: CGFloat = 270
    private let launcherSession = LauncherSession()
    private var isUserResizingPanel = false
    private var isShowingPastePermissionAlert = false
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationIcon()
        NSApp.setActivationPolicy(.accessory)
        model.recentDisplayMode = applicationSettings.recentSearchDisplayMode
        buildPanel()
        applicationSettings.applyHandler = { [weak self] isVisible in
            self?.setStatusItemVisible(isVisible)
        }
        applicationSettings.languageApplyHandler = { [weak self] _ in
            self?.updateStatusMenuTitles()
        }
        setStatusItemVisible(applicationSettings.showsStatusBarIcon)
        clipboard.start()
        installedApps.start()

        shortcutSettings.applyHandler = { [weak self] shortcut in
            self?.replaceHotKey(with: shortcut) ?? false
        }
        shortcutSettings.keywordApplyHandler = { [weak self] id, previous, shortcut in
            self?.replaceKeywordHotKey(id: id, previous: previous, with: shortcut) ?? false
        }
        if !replaceHotKey(with: shortcutSettings.shortcut) {
            if shortcutSettings.shortcut == .default {
                shortcutSettings.reportRegistrationFailure()
            } else {
                shortcutSettings.bind(.default)
            }
        }
        for binding in shortcutSettings.keywordBindings {
            guard let shortcut = binding.shortcut else { continue }
            if !replaceKeywordHotKey(id: binding.id, previous: nil, with: shortcut) {
                shortcutSettings.reportKeywordRegistrationFailure(id: binding.id)
            }
        }
        observePresentation()

        showPanel()
    }

    private func configureApplicationIcon() {
        guard
            let iconURL = Bundle.main.url(forResource: "Luma", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else { return }
        icon.isTemplate = false
        NSApp.applicationIconImage = icon
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboard.stop()
    }

    private func buildPanel() {
        let content = LauncherView(
            model: model,
            clipboard: clipboard,
            stocks: stocks,
            weather: weather,
            applicationSettings: applicationSettings,
            shortcutSettings: shortcutSettings,
            pluginSettings: pluginSettings,
            aiSettings: aiSettings,
            translationSettings: translationSettings,
            twoFactor: twoFactor,
            pasteClipboardEntry: { [weak self] entry in
                self?.pasteClipboardEntry(entry)
            },
            arrangeWindow: { [weak self] layout in
                guard let self else { return }
                self.launcherSession.arrange(layout, panel: self.panel)
            },
            dismiss: { [weak self] in
                self?.panel?.orderOut(nil)
            }
        )

        let panel = LauncherPanelFactory.make(
            rootView: content,
            height: model.preferredWindowHeight(
                recentDisplayMode: applicationSettings.recentSearchDisplayMode
            )
        )
        panel.delegate = self
        self.panel = panel
    }

    private func buildStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = LumaStatusIcon.image
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Luma"

        let menu = NSMenu()
        let show = NSMenuItem(
            title: L10n.text(
                "显示 Luma（\(shortcutSettings.shortcut.displayString)）",
                "Show Luma (\(shortcutSettings.shortcut.displayString))"
            ),
            action: #selector(showFromMenu),
            keyEquivalent: ""
        )
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: L10n.text("退出 Luma", "Quit Luma"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    private func setStatusItemVisible(_ isVisible: Bool) {
        if isVisible {
            buildStatusItem()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    @objc private func showFromMenu() {
        showPanel()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func togglePanel() {
        if panel?.isVisible == true, panel?.isKeyWindow == true {
            panel?.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel(initialQuery: String = "") {
        guard let panel else { return }
        launcherSession.captureBeforePresentation(panel: panel)
        model.prepareForPresentation(query: initialQuery)
        resizePanel(animated: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func pasteClipboardEntry(_ entry: ClipboardEntry) {
        launcherSession.paste(
            entry: entry,
            clipboard: clipboard,
            panel: panel
        ) { [weak self] in
            self?.showPastePermissionAlert()
        }
    }

    private func showPastePermissionAlert() {
        guard let panel, !isShowingPastePermissionAlert else { return }
        isShowingPastePermissionAlert = true
        let alert = NSAlert()
        alert.messageText = L10n.text(
            "需要允许 Luma 发送粘贴快捷键",
            "Allow Luma to send the paste shortcut"
        )
        alert.informativeText = L10n.text(
            "条目已复制到剪贴板。请在“系统设置 → 隐私与安全性 → 辅助功能”中启用 Luma，然后再次双击条目。",
            "The item was copied to the clipboard. Enable Luma in System Settings → Privacy & Security → Accessibility, then double-click the item again."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.text("打开系统设置", "Open System Settings"))
        alert.addButton(withTitle: L10n.text("稍后", "Later"))
        alert.beginSheetModal(for: panel) { [weak self] response in
            self?.isShowingPastePermissionAlert = false
            guard response == .alertFirstButtonReturn,
                  let settingsURL = URL(
                      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                  ) else { return }
            NSWorkspace.shared.open(settingsURL)
        }
    }

    private func observePresentation() {
        // 界面切换与首页数据（最近使用、已安装 App）都会改变目标高度；尺寸请求本身
        // 按目标 frame 去重，因此多路来源不会造成重复动画。
        Publishers.CombineLatest3(model.$query, model.$selectedPlugin, model.$isShowingSettings)
            .map { _ in () }
            .merge(with: model.objectWillChange.map { _ in () })
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.resizePanel(animated: self.panel?.isVisible == true)
            }
            .store(in: &cancellables)

        applicationSettings.$recentSearchDisplayMode
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                guard let self else { return }
                self.model.recentDisplayMode = mode
                self.resizePanel(animated: self.panel?.isVisible == true)
            }
            .store(in: &cancellables)
    }

    private func resizePanel(animated: Bool) {
        guard let panel,
              let screen = launcherSession.presentationScreen ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        let width = LumaChromeMetrics.panelWidth
        let target = windowPlacement.target(
            for: model,
            visibleFrame: screen.visibleFrame,
            decorationHeight: LauncherPanelDecoration.height(of: panel)
        )
        panelMinimumHeight = target.minimumHeight
        panel.minSize = NSSize(width: width, height: target.minimumHeight)
        panel.maxSize = NSSize(width: width, height: screen.visibleFrame.height)
        guard panelSizing.shouldApply(target.frame) else { return }
        applyPanelFrame(panel, frame: target.frame, animated: animated)
    }

    /// 应用面板尺寸。
    ///
    /// 不能用 `NSWindow.setFrame(_:display:animate:)` 的动画分支：它是同步的，会一直
    /// 阻塞主线程直到动画播完。在 Liquid Glass 面板上单次实测约 218 ms，而每次切换页面、
    /// 首次输入或清空搜索都会触发一次，用户感知就是「操作有点卡」。走 `animator()` 代理
    /// 交给 Core Animation 后，同样有 0.2 s 的平滑高度过渡（实测有 11 个中间帧），
    /// 但主线程不再被占用，动画期间输入照常响应。
    private func applyPanelFrame(_ panel: LauncherPanel, frame: NSRect, animated: Bool) {
        guard animated else {
            panel.setFrame(frame, display: true, animate: false)
            return
        }
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.2
        panel.animator().setFrame(frame, display: true)
        NSAnimationContext.endGrouping()
    }

    /// 用户拖动缩放时兜住面板尺寸：宽度固定，高度不低于当前页面所需。
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === panel else { return frameSize }
        let maximumHeight = (
            FocusedDisplayResolver.screen(containing: sender.frame)
                ?? sender.screen
                ?? NSScreen.main
        )?.visibleFrame.height ?? frameSize.height
        return NSSize(
            width: LumaChromeMetrics.panelWidth,
            height: min(max(frameSize.height, panelMinimumHeight), maximumHeight)
        )
    }

    private func replaceHotKey(with shortcut: GlobalShortcut) -> Bool {
        let previousShortcut = registeredShortcut
        hotKey = nil

        if let manager = makeHotKey(for: shortcut) {
            hotKey = manager
            registeredShortcut = shortcut
            updateStatusMenuTitles()
            return true
        }

        hotKey = makeHotKey(for: previousShortcut)
        return false
    }

    private func makeHotKey(for shortcut: GlobalShortcut) -> HotKeyManager? {
        HotKeyManager(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, identifier: 1) { [weak self] in
            self?.togglePanel()
        }
    }

    private func replaceKeywordHotKey(
        id: UUID,
        previous: GlobalShortcut?,
        with shortcut: GlobalShortcut?
    ) -> Bool {
        keywordHotKeys[id] = nil
        guard let shortcut else {
            keywordHotKeyIdentifiers[id] = nil
            return true
        }

        let identifier = keywordHotKeyIdentifier(for: id)
        if let manager = makeKeywordHotKey(id: id, shortcut: shortcut, identifier: identifier) {
            keywordHotKeys[id] = manager
            return true
        }

        if let previous,
           let restored = makeKeywordHotKey(id: id, shortcut: previous, identifier: identifier) {
            keywordHotKeys[id] = restored
        }
        return false
    }

    private func makeKeywordHotKey(
        id: UUID,
        shortcut: GlobalShortcut,
        identifier: UInt32
    ) -> HotKeyManager? {
        HotKeyManager(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.modifiers,
            identifier: identifier
        ) { [weak self] in
            guard let self else { return }
            self.showPanel(initialQuery: self.shortcutSettings.keyword(for: id) ?? "")
        }
    }

    private func keywordHotKeyIdentifier(for id: UUID) -> UInt32 {
        if let existing = keywordHotKeyIdentifiers[id] { return existing }
        let identifier = nextKeywordHotKeyIdentifier
        nextKeywordHotKeyIdentifier += 1
        keywordHotKeyIdentifiers[id] = identifier
        return identifier
    }

    private func updateStatusMenuTitles() {
        statusItem?.menu?.item(at: 0)?.title = L10n.text(
            "显示 Luma（\(registeredShortcut.displayString)）",
            "Show Luma (\(registeredShortcut.displayString))"
        )
        statusItem?.menu?.item(at: 2)?.title = L10n.text("退出 Luma", "Quit Luma")
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel,
              LauncherPanelDismissalPolicy.shouldDismissOnResignKey(
                  isPresentingSheet: isShowingPastePermissionAlert,
                  hasAttachedSheet: panel.attachedSheet != nil,
                  // 文件选择、导出面板等模态窗口会抢走 key，此时不应收起启动器。
                  hasModalWindow: NSApp.modalWindow != nil
              ) else { return }
        panel.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        guard let screen = FocusedDisplayResolver.screen(containing: window.frame) else { return }
        launcherSession.updateScreen(for: window)
        windowPlacement.remember(frame: window.frame, visibleFrame: screen.visibleFrame)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        isUserResizingPanel = NSEvent.pressedMouseButtons & 1 == 1
    }

    func windowDidResize(_ notification: Notification) {
        guard isUserResizingPanel,
              let window = notification.object as? NSWindow,
              window === panel else { return }
        windowPlacement.rememberHeight(window.frame.height, for: model.windowHeightContext)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard isUserResizingPanel,
              let window = notification.object as? NSWindow,
              window === panel else { return }
        windowPlacement.rememberHeight(window.frame.height, for: model.windowHeightContext)
        isUserResizingPanel = false
    }
}

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 创建启动器面板。面板尺寸完全由 `LauncherModel` 计算，所以这里关闭 SwiftUI
/// 内容的尺寸传播：否则内容理想高度会被写成窗口最小高度，把模型高度顶高，
/// 并在动画中反复弹跳（详见 `windowWillResize` 与 `LauncherPanelSizing`）。
enum LauncherPanelFactory {
    static func make<Content: View>(rootView: Content, height: CGFloat) -> LauncherPanel {
        let panel = LauncherPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: LumaChromeMetrics.panelWidth,
                height: height
            ),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Luma"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        LauncherPanelAppearance.hideWindowControls(in: panel)
        panel.minSize = NSSize(width: LumaChromeMetrics.panelWidth, height: 270)
        panel.maxSize = NSSize(width: LumaChromeMetrics.panelWidth, height: 1_200)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        // 立即布局：让标题栏装饰高度可测，窗口起始高度就与 AppKit 的最小高度一致。
        panel.layoutIfNeeded()
        return panel
    }
}
