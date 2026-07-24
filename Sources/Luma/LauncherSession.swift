import AppKit

@MainActor
final class LauncherSession {
    private(set) var target: FocusedWindowTarget?
    private(set) var presentationScreen: NSScreen?

    func captureBeforePresentation(panel: NSPanel?) {
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let target = FocusedWindowTarget.capture(application: app)
            self.target = target
            presentationScreen = FocusedDisplayResolver.screen(
                for: app,
                focusedWindowBounds: target.windowBounds
            ) ?? FocusedDisplayResolver.screenAtMouse() ?? panel?.screen
        } else {
            presentationScreen = FocusedDisplayResolver.screenAtMouse()
                ?? panel?.screen
                ?? NSScreen.main
        }
    }

    func updateScreen(for panel: NSWindow) {
        presentationScreen = FocusedDisplayResolver.screen(containing: panel.frame)
    }

    func paste(
        entry: ClipboardEntry,
        clipboard: ClipboardMonitor,
        panel: NSPanel?,
        permissionDenied: () -> Void
    ) {
        guard let target, !target.application.isTerminated else {
            NSSound.beep()
            return
        }
        clipboard.copy(entry)
        guard ClipboardPasteShortcut.requestEventPostingAccess() else {
            permissionDenied()
            return
        }
        panel?.orderOut(nil)
        target.application.activate()
        postPasteWhenFrontmost(target, remainingAttempts: 12)
    }

    func arrange(_ layout: WindowLayout, panel: NSPanel?) {
        guard let target, let screen = presentationScreen ?? NSScreen.main else { return }
        panel?.orderOut(nil)
        target.apply(layout: layout, on: screen)
    }

    private func postPasteWhenFrontmost(_ target: FocusedWindowTarget, remainingAttempts: Int) {
        let app = target.application
        guard !app.isTerminated else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            target.restoreWindowFocus()
            if !ClipboardPasteShortcut.postToFrontmostApplication() { NSSound.beep() }
            return
        }
        guard remainingAttempts > 0 else {
            if !ClipboardPasteShortcut.post(to: app.processIdentifier) { NSSound.beep() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.postPasteWhenFrontmost(target, remainingAttempts: remainingAttempts - 1)
        }
    }
}
