import AppKit

enum LauncherWindowHeightContext: Hashable {
    case search
    case results
    case settings
    case plugin(String)
}

struct LauncherWindowPlacement {
    // Captured from the user's chosen position on a 1920 x 1255 visible frame.
    private static let defaultHorizontalRatio: CGFloat = 567.0 / 1920.0
    private static let defaultTopRatio: CGFloat = 1034.0 / 1255.0

    private(set) var rememberedTopLeft: NSPoint?
    private(set) var rememberedHeights: [LauncherWindowHeightContext: CGFloat] = [:]

    mutating func remember(frame: NSRect) {
        rememberedTopLeft = NSPoint(x: frame.minX, y: frame.maxY)
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
            x: visibleFrame.minX + visibleFrame.width * Self.defaultHorizontalRatio,
            y: visibleFrame.minY + visibleFrame.height * Self.defaultTopRatio
        )
        let topLeft = rememberedTopLeft ?? NSPoint(
            x: min(max(proposedDefaultTopLeft.x, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(proposedDefaultTopLeft.y, visibleFrame.minY + resolvedHeight), visibleFrame.maxY)
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

enum LauncherPanelDismissalPolicy {
    static func shouldDismissOnResignKey(
        isPresentingSheet: Bool,
        hasAttachedSheet: Bool
    ) -> Bool {
        !isPresentingSheet && !hasAttachedSheet
    }
}
