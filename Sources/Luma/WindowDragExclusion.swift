import AppKit
import SwiftUI

struct WindowDragExclusion<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> WindowDragExclusionHostingView<Content> {
        WindowDragExclusionHostingView(rootView: content)
    }

    func updateNSView(
        _ nsView: WindowDragExclusionHostingView<Content>,
        context: Context
    ) {
        nsView.rootView = content
    }
}

final class WindowDragExclusionHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}
