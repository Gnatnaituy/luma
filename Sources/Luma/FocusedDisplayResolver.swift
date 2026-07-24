import AppKit
import CoreGraphics

enum FocusedDisplayResolver {
    static func screen(
        for application: NSRunningApplication,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        guard let windowBounds = frontmostWindowBounds(
            for: application.processIdentifier
        ), let targetDisplayID = bestDisplayID(
            for: windowBounds,
            displayBounds: Dictionary(
                uniqueKeysWithValues: screens.compactMap { screen in
                    guard let displayID = displayID(for: screen) else { return nil }
                    return (displayID, CGDisplayBounds(displayID))
                }
            )
        ) else {
            return nil
        }
        return screens.first { displayID(for: $0) == targetDisplayID }
    }

    static func screenAtMouse(
        screens: [NSScreen] = NSScreen.screens,
        mouseLocation: NSPoint = NSEvent.mouseLocation
    ) -> NSScreen? {
        screens.first { $0.frame.contains(mouseLocation) }
    }

    static func screen(
        containing windowFrame: NSRect,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        screens.max { lhs, rhs in
            intersectionArea(windowFrame, lhs.frame) < intersectionArea(windowFrame, rhs.frame)
        }
    }

    static func bestDisplayID(
        for windowBounds: CGRect,
        displayBounds: [CGDirectDisplayID: CGRect]
    ) -> CGDirectDisplayID? {
        displayBounds.max { lhs, rhs in
            intersectionArea(windowBounds, lhs.value) < intersectionArea(windowBounds, rhs.value)
        }.flatMap { intersectionArea(windowBounds, $0.value) > 0 ? $0.key : nil }
    }

    private static func frontmostWindowBounds(for processIdentifier: pid_t) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                    == processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(
                      dictionaryRepresentation: boundsDictionary as CFDictionary
                  ),
                  bounds.width > 20,
                  bounds.height > 20 else {
                continue
            }
            return bounds
        }
        return nil
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}
