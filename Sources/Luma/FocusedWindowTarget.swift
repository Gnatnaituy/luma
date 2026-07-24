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
