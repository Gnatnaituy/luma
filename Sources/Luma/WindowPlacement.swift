import AppKit

enum LauncherWindowHeightContext: Hashable {
    case search
    case results
    case settings
    case plugin(String)
}

struct LauncherWindowPlacement {
    private struct ScreenKey: Hashable {
        let minX: CGFloat
        let minY: CGFloat
        let width: CGFloat
        let height: CGFloat

        init(_ visibleFrame: NSRect) {
            minX = visibleFrame.minX
            minY = visibleFrame.minY
            width = visibleFrame.width
            height = visibleFrame.height
        }
    }

    // 首次出现（本次运行内用户还没挪过窗口）时的默认位置：横向严格居中，纵向沿用
    // 用户在 1920 x 1255 可视区域上选定的高度比例。
    private static let defaultTopRatio: CGFloat = 1034.0 / 1255.0

    private var rememberedTopLeftOffsets: [ScreenKey: NSPoint] = [:]
    private(set) var rememberedHeights: [LauncherWindowHeightContext: CGFloat] = [:]

    mutating func remember(frame: NSRect, visibleFrame: NSRect) {
        rememberedTopLeftOffsets[ScreenKey(visibleFrame)] = NSPoint(
            x: frame.minX - visibleFrame.minX,
            y: frame.maxY - visibleFrame.minY
        )
    }

    mutating func rememberHeight(_ height: CGFloat, for context: LauncherWindowHeightContext) {
        guard height.isFinite, height > 0 else { return }
        rememberedHeights[context] = height
    }

    func frame(
        width: CGFloat,
        height: CGFloat,
        heightContext: LauncherWindowHeightContext,
        minimumHeight: CGFloat = 0,
        visibleFrame: NSRect
    ) -> NSRect {
        let resolvedHeight = min(
            max(rememberedHeights[heightContext] ?? height, minimumHeight),
            visibleFrame.height
        )
        let proposedDefaultTopLeft = NSPoint(
            x: visibleFrame.minX + (visibleFrame.width - width) / 2,
            y: visibleFrame.minY + visibleFrame.height * Self.defaultTopRatio
        )
        let rememberedOffset = rememberedTopLeftOffsets[ScreenKey(visibleFrame)]
        let proposedTopLeft = rememberedOffset.map {
            NSPoint(x: visibleFrame.minX + $0.x, y: visibleFrame.minY + $0.y)
        } ?? proposedDefaultTopLeft
        let topLeft = NSPoint(
            x: min(
                max(proposedTopLeft.x, visibleFrame.minX),
                max(visibleFrame.minX, visibleFrame.maxX - width)
            ),
            y: min(
                max(proposedTopLeft.y, visibleFrame.minY + resolvedHeight),
                visibleFrame.maxY
            )
        )
        return NSRect(
            x: topLeft.x,
            y: topLeft.y - resolvedHeight,
            width: width,
            height: resolvedHeight
        )
    }
}

enum LauncherPanelAppearance {
    static func hideWindowControls(in window: NSWindow) {
        let controls: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for type in controls {
            window.standardWindowButton(type)?.isHidden = true
        }
    }
}

/// 面板尺寸请求去重：一次界面切换会连续产生多个等价请求（搜索词、选中插件与
/// 设置开关各自发布一次），重复应用会让同一次动画被打断并来回弹跳。
struct LauncherPanelSizing {
    private var lastRequestedFrame: NSRect?

    mutating func shouldApply(_ frame: NSRect) -> Bool {
        guard frame != lastRequestedFrame else { return false }
        lastRequestedFrame = frame
        return true
    }
}

/// 当前页面需要的面板目标尺寸；窗口与用户缩放都以此为准。
struct LauncherPanelTarget {
    /// 窗口 frame 尺寸（含标题栏等装饰）。
    let frame: NSRect
    /// 用户缩放时的最小 frame 高度。
    let minimumHeight: CGFloat
}

extension LauncherWindowPlacement {
    /// `LauncherModel` 的高度是内容可用高度（安全区），窗口 frame 还要算上标题栏装饰，
    /// 否则 AppKit 会把 frame 顶高一个标题栏高度，动画末尾就会跳一下。
    @MainActor
    func target(
        for model: LauncherModel,
        visibleFrame: NSRect,
        decorationHeight: CGFloat = 0
    ) -> LauncherPanelTarget {
        let contentHeight = model.preferredWindowHeight
        let height = contentHeight + decorationHeight
        let minimumHeight = (model.presentation == .search ? contentHeight : 280) + decorationHeight
        return LauncherPanelTarget(
            frame: frame(
                width: LumaChromeMetrics.panelWidth,
                height: height,
                heightContext: model.windowHeightContext,
                minimumHeight: minimumHeight,
                visibleFrame: visibleFrame
            ),
            minimumHeight: minimumHeight
        )
    }
}

/// 窗口 frame 与内容安全区之间的高度差（标题栏）。测试环境或已隐藏标题栏时为 0。
@MainActor
enum LauncherPanelDecoration {
    static func height(of panel: NSWindow) -> CGFloat {
        max(0, panel.frame.height - panel.contentLayoutRect.height)
    }
}

enum LauncherPanelDismissalPolicy {
    static func shouldDismissOnResignKey(
        isPresentingSheet: Bool,
        hasAttachedSheet: Bool,
        hasModalWindow: Bool = false
    ) -> Bool {
        !isPresentingSheet && !hasAttachedSheet && !hasModalWindow
    }
}
