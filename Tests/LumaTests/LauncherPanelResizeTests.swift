import AppKit
import SwiftUI
import Testing

@testable import Luma

/// 「从设置页返回时窗口上下抖动」的回归测试。
///
/// 两个原因：
/// 1. `NSHostingView` 默认把 SwiftUI 内容的理想高度写成窗口最小高度，模型高度会被顶高；
/// 2. `LauncherModel` 的高度是内容可用高度（安全区），而窗口 frame 还要算上标题栏装饰。
///    少算这一截时，动画缩到目标高度后会被 AppKit 顶回一个标题栏高度，表现为"抖一下"。
/// 另外一次界面切换会连发三次尺寸请求，重复应用会把弹跳放大。
@Suite(.serialized)
struct LauncherPanelResizeTests {
    @Test
    @MainActor
    func panelContentAreaMatchesTheModelHeight() async throws {
        _ = NSApplication.shared
        let fixture = LauncherPanelFixture()
        defer { fixture.tearDown() }

        let searchHeight = fixture.model.preferredWindowHeight
        fixture.resizeToModelHeight()
        #expect(
            fixture.panel.contentLayoutRect.height == searchHeight,
            "搜索页内容可用高度必须等于模型高度，窗口 frame 需另加标题栏装饰"
        )
        #expect(
            fixture.panel.frame.height == searchHeight + fixture.decorationHeight,
            "窗口 frame 高度 = 模型高度 + 标题栏装饰"
        )

        fixture.model.showSettings()
        fixture.resizeToModelHeight()
        #expect(
            fixture.panel.contentLayoutRect.height == LauncherModel.defaultExpandedWindowHeight,
            "设置页内容可用高度必须等于模型高度"
        )

        fixture.model.returnToSearch()
        fixture.resizeToModelHeight()
        #expect(
            fixture.panel.contentLayoutRect.height == searchHeight,
            "从设置页返回后内容可用高度必须回到模型高度"
        )
    }

    @Test
    @MainActor
    func panelTargetIncludesTheWindowDecoration() async throws {
        _ = NSApplication.shared
        let fixture = LauncherPanelFixture()
        defer { fixture.tearDown() }

        let modelHeight = fixture.model.preferredWindowHeight
        let target = fixture.placement.target(
            for: fixture.model,
            visibleFrame: fixture.visibleFrame,
            decorationHeight: 32
        )
        #expect(
            target.frame.height == modelHeight + 32
                && target.minimumHeight == modelHeight + 32,
            "标题栏装饰必须计入目标 frame 与最小高度，否则动画末尾会被顶高"
        )
    }

    @Test
    @MainActor
    func returningFromSettingsDoesNotBounceTheWindow() async throws {
        _ = NSApplication.shared
        let fixture = LauncherPanelFixture()
        defer { fixture.tearDown() }

        fixture.model.showSettings()
        fixture.resizeToModelHeight()

        // 窗口必须可见，AppKit 才会真正执行尺寸动画（不可见时 setFrame 直接生效）。
        fixture.panel.orderFrontRegardless()
        let recorder = PanelFrameRecorder(panel: fixture.panel)
        fixture.model.returnToSearch()
        // 复刻修复前一次界面切换发出的三次等价请求：高度被内容顶高时，重复应用
        // 会把同一次动画打断成上下弹跳。
        fixture.resizeToModelHeightRepeatedly(3, settle: 0.8)
        recorder.stop()
        fixture.panel.orderOut(nil)

        #expect(
            recorder.reversals == 0,
            "返回搜索页的动画不得出现高度方向反转，实测高度序列：\(recorder.heights)"
        )
    }

    @Test
    @MainActor
    func onePresentationChangeRequestsOnePanelResize() async throws {
        _ = NSApplication.shared
        let fixture = LauncherPanelFixture()
        defer { fixture.tearDown() }

        var sizing = LauncherPanelSizing()
        var appliedHeights: [CGFloat] = []

        // 与 AppDelegate.observePresentation 一致：搜索词、选中插件与设置开关各自发布一次。
        func applyPresentationChange(_ change: () -> Void) {
            change()
            for _ in 0..<3 {
                let target = fixture.placement.target(
                    for: fixture.model,
                    visibleFrame: fixture.visibleFrame
                )
                if sizing.shouldApply(target.frame) {
                    appliedHeights.append(target.frame.height)
                }
            }
        }

        applyPresentationChange { fixture.model.showSettings() }
        applyPresentationChange { fixture.model.returnToSearch() }

        #expect(
            appliedHeights == [
                LauncherModel.defaultExpandedWindowHeight,
                fixture.model.preferredWindowHeight
            ],
            "每次界面切换只应用一次尺寸请求，重复请求必须被合并"
        )
    }
}

/// 记录窗口动画期间的高度序列，用于判断是否出现上下弹跳。
@MainActor
private final class PanelFrameRecorder {
    private(set) var heights: [CGFloat] = []
    private var observers: [NSObjectProtocol] = []

    init(panel: NSWindow) {
        let record: (Notification) -> Void = { [weak self] _ in
            self?.heights.append(panel.frame.height)
        }
        observers = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: panel, queue: .main, using: record
            ),
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: panel, queue: .main, using: record
            )
        ]
    }

    /// 连续高度变化的方向反转次数：一次平滑的放大或缩小应为 0。
    var reversals: Int {
        var count = 0
        for index in 2..<max(2, heights.count) where index < heights.count {
            let previous = heights[index - 1] - heights[index - 2]
            let current = heights[index] - heights[index - 1]
            if previous * current < 0 { count += 1 }
        }
        return count
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}

/// 真实面板 + 真实 SwiftUI 内容，用于验证窗口几何。
@MainActor
private final class LauncherPanelFixture {
    let model: LauncherModel
    let panel: LauncherPanel
    let placement = LauncherWindowPlacement()
    let visibleFrame: NSRect
    private var sizing = LauncherPanelSizing()
    private let suiteName: String

    init() {
        suiteName = "app.luma.panel-resize-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let pluginSettings = PluginSettings(defaults: defaults)
        let clipboard = ClipboardMonitor(entries: [])
        model = LauncherModel(
            clipboard: clipboard,
            pluginSettings: pluginSettings,
            installedApps: InstalledAppIndex(applications: []),
            recentUsage: RecentUsageStore(defaults: defaults),
            fileSearch: FileSearchIndex()
        )
        let applicationSettings = ApplicationSettings(defaults: defaults)
        let shortcutSettings = ShortcutSettings(defaults: defaults)
        let stocks = StockStore(defaults: defaults)
        let weather = WeatherStore(defaults: defaults)
        let aiSettings = AISettings(defaults: defaults, secrets: InMemoryAISecretStore())
        let translationSettings = TranslationSettings(aiSettings: aiSettings, defaults: defaults)
        let twoFactor = TwoFactorStore(defaults: defaults, secrets: InMemoryTwoFactorSecretStore())

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
            pasteClipboardEntry: { _ in },
            arrangeWindow: { _ in },
            dismiss: {}
        )

        visibleFrame = (NSScreen.main ?? NSScreen.screens.first)!.visibleFrame
        panel = LauncherPanelFactory.make(rootView: content, height: model.preferredWindowHeight)
    }

    /// 复刻 AppDelegate.resizePanel 的尺寸应用顺序，含请求合并。
    func resizeToModelHeight(animated: Bool = false, settle: TimeInterval = 0.3) {
        applyModelHeight(animated: animated, coalescing: true)
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
    }

    /// 不做请求合并，连续应用多次；用于复现修复前一次界面切换的请求风暴。
    func resizeToModelHeightRepeatedly(_ times: Int, settle: TimeInterval) {
        for _ in 0..<times {
            applyModelHeight(animated: true, coalescing: false)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
    }

    private func applyModelHeight(animated: Bool, coalescing: Bool) {
        let target = placement.target(
            for: model,
            visibleFrame: visibleFrame,
            decorationHeight: decorationHeight
        )
        panel.minSize = NSSize(width: LumaChromeMetrics.panelWidth, height: target.minimumHeight)
        panel.maxSize = NSSize(width: LumaChromeMetrics.panelWidth, height: visibleFrame.height)
        if coalescing, !sizing.shouldApply(target.frame) { return }
        if !coalescing { _ = sizing.shouldApply(target.frame) }
        panel.setFrame(target.frame, display: true, animate: animated)
    }

    /// 与 AppDelegate.resizePanel 一致：frame 高度要补上标题栏装饰。
    var decorationHeight: CGFloat {
        LauncherPanelDecoration.height(of: panel)
    }

    func tearDown() {
        panel.orderOut(nil)
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}
