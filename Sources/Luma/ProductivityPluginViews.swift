import AppKit
import SwiftUI

struct WindowManagementPluginView: View {
    let arrange: (WindowLayout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text(
                "排列唤起 Luma 前聚焦的窗口",
                "Arrange the window that was focused before opening Luma"
            ))
            .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                ForEach(WindowLayout.allCases) { layout in
                    Button { arrange(layout) } label: {
                        VStack(spacing: 10) {
                            Image(systemName: layout.symbol).font(.system(size: 30))
                            Text(layout.title).font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 110)
                    }
                    .buttonStyle(LumaTextButtonStyle())
                }
            }
            Label(
                L10n.text(
                    "需要“辅助功能”权限；布局应用在当前聚焦屏幕。",
                    "Accessibility permission is required. Layouts use the currently focused display."
                ),
                systemImage: "info.circle"
            )
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }
}
