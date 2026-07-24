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

    // Captured from the user's chosen position on a 1920 x 1255 visible frame.
    private static let defaultHorizontalRatio: CGFloat = 567.0 / 1920.0
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
            x: visibleFrame.minX + visibleFrame.width * Self.defaultHorizontalRatio,
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

enum LauncherPanelDismissalPolicy {
    static func shouldDismissOnResignKey(
        isPresentingSheet: Bool,
        hasAttachedSheet: Bool
    ) -> Bool {
        !isPresentingSheet && !hasAttachedSheet
    }
}
