import AppKit
import SwiftUI

/// 与 macOS 27 系统界面（App 资料库）对齐的设计基线：
/// 大圆角玻璃面板、分层浅色填充、发丝分隔线与圆角方形图标。
enum LumaRadius {
    static let panel: CGFloat = 26
    static let card: CGFloat = 14
    static let control: CGFloat = 10

    /// 系统图标容器的圆角比例，macOS 26 起应用图标为满幅连续圆角。
    static func iconRadius(for size: CGFloat) -> CGFloat { size * 0.235 }
}

enum LumaTone {
    static let hairline = Color.primary.opacity(0.1)
    static let controlFill = Color.primary.opacity(0.05)
    static let controlFillPressed = Color.primary.opacity(0.11)
    static let cardFill = Color.primary.opacity(0.05)
    static let hoverFill = Color.primary.opacity(0.06)
    static let selectionFill = Color.accentColor.opacity(0.16)
    /// 玻璃面板上覆盖的窗口底色，保证内容可读性并与系统窗口观感一致。
    static let panelTintAlpha: CGFloat = 0.4
}

enum LumaChromeMetrics {
    static let panelWidth: CGFloat = 920
    static let headerHeight: CGFloat = 56
    static let searchFieldHeight: CGFloat = 36
    static let searchFieldRadius: CGFloat = 11
    static let iconButtonSize: CGFloat = 30
    static let hairline: CGFloat = 1
}

/// App 资料库网格的度量，视图与窗口高度计算共用同一组常量。
enum LumaGridMetrics {
    static let horizontalPadding: CGFloat = 24
    static let tileWidth: CGFloat = 108
    static let columnSpacing: CGFloat = 14
    static let iconSize: CGFloat = 56
    static let iconLabelSpacing: CGFloat = 8
    static let labelHeight: CGFloat = 15
    static let tileVerticalPadding: CGFloat = 10
    static let gridTopPadding: CGFloat = 12
    static let gridBottomPadding: CGFloat = 18
    static let sectionHeaderHeight: CGFloat = 24

    static var columns: Int {
        let available = LumaChromeMetrics.panelWidth - horizontalPadding * 2
        let count = Int((available + columnSpacing) / (tileWidth + columnSpacing))
        return max(1, count)
    }

    static var tileHeight: CGFloat {
        iconSize + iconLabelSpacing + labelHeight
    }

    /// 单行网格（含分隔线上下留白）在垂直方向占用的高度。
    static var rowPitch: CGFloat {
        tileHeight + tileVerticalPadding * 2
    }

    static let emptyStateHeight: CGFloat = 132

    static func rows(count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (count + columns - 1) / columns
    }
}

struct LumaHairline: View {
    var body: some View {
        Rectangle()
            .fill(LumaTone.hairline)
            .frame(height: LumaChromeMetrics.hairline)
    }
}

/// 连续圆角描边，用于玻璃面板与卡片的高光边缘。
struct LumaRimStroke: View {
    var cornerRadius: CGFloat
    var isProminent: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(isProminent ? 0.16 : 0.1), lineWidth: 1)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

/// macOS 26 起的原生 Liquid Glass，旧系统回退到窗口后置模糊。
struct LumaGlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat = LumaRadius.panel
    var tint: NSColor?

    func makeNSView(context: Context) -> NSView {
        LumaGlassBackgroundView(cornerRadius: cornerRadius, tint: tint)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? LumaGlassBackgroundView else { return }
        view.cornerRadius = cornerRadius
        view.tint = tint
    }
}

final class LumaGlassBackgroundView: NSView {
    var cornerRadius: CGFloat {
        didSet { applyCornerRadius() }
    }
    var tint: NSColor? {
        didSet { applyTint() }
    }

    private let effectView: NSVisualEffectView?

    init(cornerRadius: CGFloat, tint: NSColor?) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        if #available(macOS 26.0, *) {
            effectView = nil
        } else {
            let view = NSVisualEffectView()
            view.material = .popover
            view.blendingMode = .behindWindow
            view.state = .followsWindowActiveState
            effectView = view
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        setupEffectView()
        applyCornerRadius()
        applyTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupEffectView() {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.contentView = NSView()
            glass.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glass)
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: trailingAnchor),
                glass.topAnchor.constraint(equalTo: topAnchor),
                glass.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            glassView = glass
        } else if let effectView {
            effectView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(effectView)
            NSLayoutConstraint.activate([
                effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
                effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
                effectView.topAnchor.constraint(equalTo: topAnchor),
                effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    private var glassView: NSView?

    private func applyCornerRadius() {
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        if #available(macOS 26.0, *) {
            (glassView as? NSGlassEffectView)?.cornerRadius = cornerRadius
        }
    }

    private func applyTint() {
        if #available(macOS 26.0, *) {
            (glassView as? NSGlassEffectView)?.tintColor = tint
        }
    }
}

/// 面板背景：Liquid Glass + 高光边缘。
struct LumaPanelBackground: View {
    var cornerRadius: CGFloat = LumaRadius.panel
    var tintAlpha: CGFloat = LumaTone.panelTintAlpha

    var body: some View {
        LumaGlassBackground(
            cornerRadius: cornerRadius,
            tint: NSColor.windowBackgroundColor.withAlphaComponent(tintAlpha)
        )
        .overlay {
            LumaRimStroke(cornerRadius: cornerRadius, isProminent: true)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// 卡片式容器：浅色填充 + 高光边缘，替代纯色分隔块。
struct LumaCardBackground: ViewModifier {
    var cornerRadius: CGFloat = LumaRadius.card
    var fill: Color = LumaTone.cardFill
    var isProminent: Bool = false

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                LumaRimStroke(cornerRadius: cornerRadius, isProminent: isProminent)
            }
    }
}

extension View {
    func lumaCard(
        cornerRadius: CGFloat = LumaRadius.card,
        fill: Color = LumaTone.cardFill,
        isProminent: Bool = false
    ) -> some View {
        modifier(LumaCardBackground(cornerRadius: cornerRadius, fill: fill, isProminent: isProminent))
    }
}

/// 应用与插件共用的圆角方形图标。
struct LumaIconTile: View {
    let symbol: String?
    let tint: Color
    let applicationURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let applicationURL {
                Image(nsImage: LumaAppIconCache.icon(for: applicationURL))
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                symbolTile
            }
        }
        .frame(width: size, height: size)
    }

    private var symbolTile: some View {
        RoundedRectangle(cornerRadius: LumaRadius.iconRadius(for: size), style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.98), tint.opacity(0.76)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Image(systemName: symbol ?? "square")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: LumaRadius.iconRadius(for: size), style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.16), radius: 2.5, y: 1)
    }
}

enum LumaAppIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 128, height: 128)
        cache.setObject(image, forKey: key)
        return image
    }
}
