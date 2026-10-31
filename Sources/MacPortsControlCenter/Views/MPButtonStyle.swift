import SwiftUI

/// High-performance, lightweight pure SwiftUI button style.
/// Replaces AppKit-bridged `.buttonStyle(.bordered)`, `.borderedProminent`, and `.borderless`
/// controls which trigger recursive AttributeGraph relayouts during macOS window activation.
public struct MPButtonStyle: ButtonStyle {
    public enum Variant: Equatable {
        case bordered
        case borderedProminent
        case borderless
    }

    public enum Size: Equatable {
        case regular
        case small
        case mini

        public var font: Font {
            switch self {
            case .regular: return .system(size: 12, weight: .medium)
            case .small: return .system(size: 11, weight: .medium)
            case .mini: return .system(size: 10, weight: .medium)
            }
        }

        public var horizontalPadding: CGFloat {
            switch self {
            case .regular: return 12
            case .small: return 8
            case .mini: return 6
            }
        }

        public var verticalPadding: CGFloat {
            switch self {
            case .regular: return 6
            case .small: return 4
            case .mini: return 2
            }
        }
    }

    public var variant: Variant
    public var size: Size?
    public var tint: Color?

    public init(variant: Variant = .bordered, size: Size? = nil, tint: Color? = nil) {
        self.variant = variant
        self.size = size
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        MPButtonBody(configuration: configuration, variant: variant, size: size, tint: tint)
    }

    private struct MPButtonBody: View {
        let configuration: Configuration
        let variant: Variant
        let size: Size?
        let tint: Color?
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var envControlSize

        private var effectiveSize: Size {
            if let size = size {
                return size
            }
            switch envControlSize {
            case .mini: return .mini
            case .small: return .small
            case .regular, .large: return .regular
            @unknown default: return .regular
            }
        }

        var body: some View {
            let isPressed = configuration.isPressed
            let effectiveTint = tint ?? (variant == .borderedProminent ? Color.accentColor : Color.primary)

            configuration.label
                .font(effectiveSize.font)
                .padding(.horizontal, variant == .borderless ? (size?.horizontalPadding ?? 4) : effectiveSize.horizontalPadding)
                .padding(.vertical, variant == .borderless ? (size?.verticalPadding ?? 4) : effectiveSize.verticalPadding)
                .foregroundColor(foregroundColor(isPressed: isPressed, tint: effectiveTint))
                .background(backgroundView(isPressed: isPressed, tint: effectiveTint))
                .cornerRadius(5)
                .contentShape(Rectangle())
                .opacity(isEnabled ? (isPressed ? 0.75 : 1.0) : 0.45)
        }

        @ViewBuilder
        private func backgroundView(isPressed: Bool, tint: Color) -> some View {
            switch variant {
            case .borderedProminent:
                tint.opacity(isPressed ? 0.75 : 0.9)
            case .bordered:
                if let customTint = self.tint {
                    customTint.opacity(isPressed ? 0.22 : 0.12)
                } else {
                    Color.secondary.opacity(isPressed ? 0.22 : 0.12)
                }
            case .borderless:
                if isPressed {
                    Color.secondary.opacity(0.12)
                } else {
                    Color.clear
                }
            }
        }

        private func foregroundColor(isPressed: Bool, tint: Color) -> Color {
            switch variant {
            case .borderedProminent:
                return .white
            case .bordered:
                return self.tint ?? .primary
            case .borderless:
                return self.tint ?? .secondary
            }
        }
    }
}

extension View {
    /// Applies the pure SwiftUI `MPButtonStyle` without AppKit NSButton bridging.
    public func mpButton(
        _ variant: MPButtonStyle.Variant = .bordered,
        size: MPButtonStyle.Size? = nil,
        tint: Color? = nil
    ) -> some View {
        self.buttonStyle(MPButtonStyle(variant: variant, size: size, tint: tint))
    }
}

extension ButtonStyle where Self == MPButtonStyle {
    public static var mpBordered: MPButtonStyle { MPButtonStyle(variant: .bordered) }
    public static var mpBorderedProminent: MPButtonStyle { MPButtonStyle(variant: .borderedProminent) }
    public static var mpBorderless: MPButtonStyle { MPButtonStyle(variant: .borderless) }
}
