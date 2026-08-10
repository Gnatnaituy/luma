import SwiftUI

enum LumaButtonEmphasis {
    case regular
    case primary
    case destructive
}

struct LumaIconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 7

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(width: size, height: size)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.10 : 0.045),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(LumaMotion.press, value: configuration.isPressed)
    }
}

struct LumaTextButtonStyle: ButtonStyle {
    var emphasis: LumaButtonEmphasis = .regular
    var height: CGFloat = 30

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .frame(minHeight: height)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(LumaMotion.press, value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch emphasis {
        case .regular:
            Color.primary.opacity(isPressed ? 0.10 : 0.045)
        case .primary:
            Color.accentColor.opacity(isPressed ? 0.78 : 1)
        case .destructive:
            Color.red.opacity(isPressed ? 0.14 : 0.07)
        }
    }

    private var foregroundColor: Color {
        switch emphasis {
        case .regular: .primary
        case .primary: .white
        case .destructive: .red.opacity(0.85)
        }
    }
}

struct LumaTextFieldStyle: TextFieldStyle {
    var height: CGFloat = 30

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(minHeight: height)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}

struct LumaSelectionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                title,
                systemImage: isSelected ? "checkmark.circle.fill" : "circle"
            )
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(LumaMotion.quick, value: isSelected)
    }
}

struct LumaFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = layout(
            subviews: subviews,
            maxWidth: proposal.width ?? .infinity
        )
        return CGSize(
            width: proposal.width ?? result.size.width,
            height: result.size.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(subviews: subviews, maxWidth: bounds.width)
        for (index, item) in result.items.enumerated() {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + item.origin.x,
                    y: bounds.minY + item.origin.y
                ),
                proposal: ProposedViewSize(item.size)
            )
        }
    }

    private func layout(
        subviews: Subviews,
        maxWidth: CGFloat
    ) -> (items: [(origin: CGPoint, size: CGSize)], size: CGSize) {
        var items: [(origin: CGPoint, size: CGSize)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            items.append((CGPoint(x: x, y: y), size))
            contentWidth = max(contentWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
        }

        return (
            items,
            CGSize(width: contentWidth, height: items.isEmpty ? 0 : y + rowHeight)
        )
    }
}

struct LumaMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let values: [Value]
    let title: (Value) -> String

    private var selectedTitle: String {
        guard let value = values.first(where: { $0 == selection }) else {
            return L10n.text("请选择", "Select")
        }
        return title(value)
    }

    var body: some View {
        Menu {
            ForEach(values, id: \.self) { value in
                Button {
                    selection = value
                } label: {
                    if value == selection {
                        Label(title(value), systemImage: "checkmark")
                    } else {
                        Text(title(value))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.leading, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct LumaToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                configuration.label
            }
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(configuration.isOn ? Color.accentColor : Color.primary)
            .padding(.horizontal, 11)
            .frame(minHeight: 30)
            .background(
                configuration.isOn ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .animation(LumaMotion.quick, value: configuration.isOn)
    }
}
