import AppKit
import SwiftUI

/// 面板顶部工具栏：应用图标（或返回按钮）、搜索框与设置按钮。
/// 版式对齐 macOS 27 应用窗口的工具栏与发丝分隔线。
struct LauncherHeader: View {
    @Binding var query: String
    let focusRequest: Int
    let showsBackButton: Bool
    let isShowingSettings: Bool
    let onSubmit: () -> Void
    let onMove: (Int) -> Void
    let onHorizontalMove: (Int) -> Bool
    let onEscape: () -> Void
    let onBack: () -> Void
    let onToggleSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if showsBackButton {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(LumaIconButtonStyle(
                    size: LumaChromeMetrics.iconButtonSize,
                    cornerRadius: LumaRadius.control
                ))
                .help(L10n.text("返回搜索", "Back to Search"))
            } else {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Luma")
            }

            searchField

            Button(action: onToggleSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isShowingSettings ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(LumaIconButtonStyle(
                size: LumaChromeMetrics.iconButtonSize,
                cornerRadius: LumaRadius.control
            ))
            .help(L10n.text("配置", "Settings"))
        }
        .padding(.horizontal, LumaGridMetrics.horizontalPadding)
        .frame(height: LumaChromeMetrics.headerHeight)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            LauncherSearchField(
                text: $query,
                focusRequest: focusRequest,
                onSubmit: onSubmit,
                onMove: onMove,
                onHorizontalMove: onHorizontalMove,
                onEscape: onEscape
            )
        }
        .padding(.horizontal, 12)
        .frame(height: LumaChromeMetrics.searchFieldHeight)
        .background(
            LumaTone.controlFill,
            in: RoundedRectangle(cornerRadius: LumaChromeMetrics.searchFieldRadius, style: .continuous)
        )
        .overlay {
            LumaRimStroke(cornerRadius: LumaChromeMetrics.searchFieldRadius)
        }
    }
}
