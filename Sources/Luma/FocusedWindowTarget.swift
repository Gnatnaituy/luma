import ApplicationServices
import AppKit

final class FocusedWindowTarget {
    let application: NSRunningApplication
    private let accessibilityApplication: AXUIElement
    private let window: AXUIElement?

    private init(
        application: NSRunningApplication,
        accessibilityApplication: AXUIElement,
        window: AXUIElement?
    ) {
        self.application = application
        self.accessibilityApplication = accessibilityApplication
        self.window = window
    }

    static func capture(application: NSRunningApplication) -> FocusedWindowTarget {
        let accessibilityApplication = AXUIElementCreateApplication(
            application.processIdentifier
        )
        var value: CFTypeRef?
        let window: AXUIElement?
        if AXUIElementCopyAttributeValue(
            accessibilityApplication,
            kAXFocusedWindowAttribute as CFString,
            &value
        ) == .success,
           let value,
           CFGetTypeID(value) == AXUIElementGetTypeID() {
            window = unsafeDowncast(value, to: AXUIElement.self)
        } else {
            window = nil
        }
        return FocusedWindowTarget(
            application: application,
            accessibilityApplication: accessibilityApplication,
            window: window
        )
    }

    var windowBounds: CGRect? {
        guard let window,
              let position = value(of: kAXPositionAttribute, from: window, type: .cgPoint),
              let size = value(of: kAXSizeAttribute, from: window, type: .cgSize) else {
            return nil
        }
        var point = CGPoint.zero
        var windowSize = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point),
              AXValueGetValue(size, .cgSize, &windowSize) else {
            return nil
        }
        return CGRect(origin: point, size: windowSize)
    }

    func restoreWindowFocus() {
        guard let window else { return }
        AXUIElementSetAttributeValue(
            accessibilityApplication,
            kAXFocusedWindowAttribute as CFString,
            window
        )
        AXUIElementSetAttributeValue(
            window,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    func apply(layout: WindowLayout, on screen: NSScreen) {
        guard let window else { return }
        let frame = screen.visibleFrame
        let target: CGRect
        switch layout {
        case .left: target = CGRect(x: frame.minX, y: frame.minY, width: frame.width / 2, height: frame.height)
        case .right: target = CGRect(x: frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height)
        case .maximize: target = frame
        case .center:
            target = CGRect(x: frame.midX - frame.width * 0.35, y: frame.midY - frame.height * 0.35, width: frame.width * 0.7, height: frame.height * 0.7)
        }
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? frame.maxY
        var point = CGPoint(x: target.minX, y: desktopTop - target.maxY)
        var size = target.size
        if let position = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
        if let dimensions = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        }
        application.activate()
        restoreWindowFocus()
    }

    private func value(
        of attribute: String,
        from element: AXUIElement,
        type: AXValueType
    ) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let result = unsafeDowncast(value, to: AXValue.self)
        return AXValueGetType(result) == type ? result : nil
    }
}
