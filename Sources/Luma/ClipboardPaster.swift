import Carbon.HIToolbox
import CoreGraphics

enum ClipboardPasteShortcut {
    static let keyCode = CGKeyCode(kVK_ANSI_V)
    static let eventFlags = CGEventFlags.maskCommand

    static func requestEventPostingAccess() -> Bool {
        CGPreflightPostEventAccess() || CGRequestPostEventAccess()
    }

    static func makeEvents() -> (keyDown: CGEvent, keyUp: CGEvent)? {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode,
                  keyDown: false
              ) else { return nil }
        keyDown.flags = eventFlags
        keyUp.flags = eventFlags
        return (keyDown, keyUp)
    }

    @discardableResult
    static func post(to processIdentifier: pid_t) -> Bool {
        guard let events = makeEvents() else { return false }
        events.keyDown.postToPid(processIdentifier)
        events.keyUp.postToPid(processIdentifier)
        return true
    }

    @discardableResult
    static func postToFrontmostApplication() -> Bool {
        guard let events = makeEvents() else { return false }
        events.keyDown.post(tap: .cghidEventTap)
        events.keyUp.post(tap: .cghidEventTap)
        return true
    }
}
