import AppKit
import SwiftUI

/// 面板顶部工具栏，对齐 macOS 27「应用程序」视图：左侧图标 + 兼作搜索框的大标题，
/// 右侧省略号按钮。版式与发丝分隔线同样沿用该视图。
struct LauncherHeader: View {
    @Binding var query: String
    let focusRequest: Int
    let placeholder: String
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
                    .frame(
                        width: LumaChromeMetrics.appIconSize,
                        height: LumaChromeMetrics.appIconSize
                    )
                    .accessibilityLabel("Luma")
            }

            searchField

            Button(action: onToggleSettings) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
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
        LauncherSearchField(
            text: $query,
            focusRequest: focusRequest,
            placeholder: placeholder,
            onSubmit: onSubmit,
            onMove: onMove,
            onHorizontalMove: onHorizontalMove,
            onEscape: onEscape
        )
        .frame(maxWidth: .infinity)
        .frame(height: LumaChromeMetrics.searchFieldHeight)
    }
}
