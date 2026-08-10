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
    private let launcherSession = LauncherSession()
    private var isUserResizingPanel = false
    private var isShowingPastePermissionAlert = false
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationIcon()
        NSApp.setActivationPolicy(.accessory)
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

        let panel = LauncherPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 920,
                height: model.preferredWindowHeight(
                    recentDisplayMode: applicationSettings.recentSearchDisplayMode
                )
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
        panel.minSize = NSSize(width: 920, height: 58)
        panel.maxSize = NSSize(width: 920, height: 1_200)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: content)
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
        resizePanel(
            to: model.preferredWindowHeight(
                recentDisplayMode: applicationSettings.recentSearchDisplayMode
            ),
            animated: false
        )
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
        Publishers.CombineLatest3(model.$query, model.$selectedPlugin, model.$isShowingSettings)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                guard let self else { return }
                self.resizePanel(
                    to: self.model.preferredWindowHeight(
                        recentDisplayMode: self.applicationSettings.recentSearchDisplayMode
                    ),
                    animated: self.panel?.isVisible == true
                )
            }
            .store(in: &cancellables)

        applicationSettings.$recentSearchDisplayMode
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                guard let self else { return }
                self.resizePanel(
                    to: self.model.preferredWindowHeight(recentDisplayMode: mode),
                    animated: self.panel?.isVisible == true
                )
            }
            .store(in: &cancellables)
    }

    private func resizePanel(to height: CGFloat, animated: Bool) {
        guard let panel,
              let screen = launcherSession.presentationScreen ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        let width: CGFloat = 920
        let minimumHeight = model.presentation == .search ? height : 280
        panel.minSize = NSSize(width: width, height: minimumHeight)
        panel.maxSize = NSSize(width: width, height: screen.visibleFrame.height)
        let frame = windowPlacement.frame(
            width: width,
            height: height,
            heightContext: model.windowHeightContext,
            minimumHeight: minimumHeight,
            visibleFrame: screen.visibleFrame
        )
        panel.setFrame(frame, display: true, animate: animated)
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
                  hasAttachedSheet: panel.attachedSheet != nil
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
