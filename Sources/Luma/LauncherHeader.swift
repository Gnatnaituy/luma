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

    @State private var isComposing = false

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

    /// 大标题兼作搜索框：占位符自己画，才能在任何页面、任何焦点状态下都垂直居中。
    ///
    /// AppKit 的 `placeholderAttributedString` 在输入框没有焦点时按基线顶对齐绘制，
    /// 拿到焦点后又由字段编辑器居中绘制，两种状态差 4pt；而且占位符字号（22pt）与
    /// 输入字号（26pt）不同，没有哪个输入框高度能同时让两者居中。
    private var searchField: some View {
        ZStack(alignment: .leading) {
            if query.isEmpty && !isComposing {
                Text(placeholder)
                    .font(.system(size: LumaChromeMetrics.placeholderFontSize, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            LauncherSearchField(
                text: $query,
                focusRequest: focusRequest,
                onSubmit: onSubmit,
                onMove: onMove,
                onHorizontalMove: onHorizontalMove,
                onEscape: onEscape,
                onComposingChange: { isComposing = $0 }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: LumaChromeMetrics.searchFieldHeight)
    }
}
