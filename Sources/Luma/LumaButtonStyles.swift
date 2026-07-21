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
    }
}

struct LumaTextButtonStyle: ButtonStyle {
    var emphasis: LumaButtonEmphasis = .regular
    var height: CGFloat = 30

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: height)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.42)
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
            .padding(.horizontal, 10)
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
    }
}

struct LumaMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let values: [Value]
    let title: (Value) -> String

    private var selectedTitle: String {
        guard let value = values.first(where: { $0 == selection }) else { return "请选择" }
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
            .foregroundStyle(configuration.isOn ? Color.accentColor : Color.primary)
            .padding(.horizontal, 11)
            .frame(minHeight: 30)
            .background(
                configuration.isOn ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}
