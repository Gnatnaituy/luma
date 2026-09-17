import SwiftUI

/// 首页：最近使用的插件与本机 App，以 macOS 27 风格的圆角方形图标网格呈现。
/// 布局沿用「最近搜索展示」设置：平铺为一片网格，分组则按插件与应用分开。
struct RecentItemsView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        let sections = model.recentSections.filter { !$0.items.isEmpty }
        if sections.isEmpty {
            emptyState
        } else {
            grid(sections)
        }
    }

    private func grid(_ sections: [RecentTileSection]) -> some View {
        let indexMap = model.recentTileIndexMap
        return VStack(spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 {
                    LumaHairline()
                        .padding(.horizontal, LumaGridMetrics.horizontalPadding)
                }
                if let title = section.title {
                    sectionHeader(title)
                }
                rows(for: section, indexMap: indexMap)
            }
        }
        .padding(.top, LumaGridMetrics.gridTopPadding)
        .padding(.bottom, LumaGridMetrics.gridBottomPadding)
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LumaGridMetrics.horizontalPadding)
            .frame(height: LumaGridMetrics.sectionHeaderHeight, alignment: .bottom)
            .padding(.bottom, 4)
    }

    private func rows(for section: RecentTileSection, indexMap: [String: Int]) -> some View {
        let rows = section.rows(columns: LumaGridMetrics.columns)
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    LumaHairline()
                        .padding(.horizontal, LumaGridMetrics.horizontalPadding)
                }
                HStack(spacing: LumaGridMetrics.columnSpacing) {
                    ForEach(row) { item in
                        tile(for: item, indexMap: indexMap)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LumaGridMetrics.horizontalPadding)
                .padding(.vertical, LumaGridMetrics.tileVerticalPadding)
            }
        }
    }

    private func tile(for item: RecentTileItem, indexMap: [String: Int]) -> some View {
        RecentItemTile(
            item: item,
            isSelected: model.isRecentSelectionActive
                && model.recentSelection == indexMap[item.id]
        ) {
            model.activate(item)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            L10n.text("暂无最近使用", "No Recent Items"),
            systemImage: "clock",
            description: Text(L10n.text(
                "打开过的插件与 App 会出现在这里",
                "Plugins and apps you open appear here"
            ))
        )
        .frame(maxWidth: .infinity)
        .frame(height: LumaGridMetrics.emptyStateHeight)
    }
}

private struct RecentItemTile: View {
    let item: RecentTileItem
    let isSelected: Bool
    let action: () -> Void

    @StateObject private var hover = LumaHoverState()

    var body: some View {
        Button(action: action) {
            VStack(spacing: LumaGridMetrics.iconLabelSpacing) {
                LumaIconTile(
                    symbol: item.symbol,
                    tint: item.tint,
                    applicationURL: item.applicationURL,
                    size: LumaGridMetrics.iconSize
                )
                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: LumaGridMetrics.labelHeight)
            }
            .frame(width: LumaGridMetrics.tileWidth, height: LumaGridMetrics.tileHeight)
            .background(tileFill, in: RoundedRectangle(cornerRadius: LumaRadius.card, style: .continuous))
            .overlay {
                if isSelected {
                    LumaRimStroke(cornerRadius: LumaRadius.card)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: LumaRadius.card, style: .continuous))
        }
        .buttonStyle(LumaTileButtonStyle())
        .onHover { hover.isHovering = $0 }
        .help(item.title)
        .accessibilityLabel(item.title)
    }

    private var tileFill: Color {
        if isSelected { return LumaTone.selectionFill }
        return hover.isHovering ? LumaTone.hoverFill : .clear
    }
}

final class LumaHoverState: ObservableObject {
    @Published var isHovering = false
}

struct LumaTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(LumaMotion.press, value: configuration.isPressed)
    }
}
