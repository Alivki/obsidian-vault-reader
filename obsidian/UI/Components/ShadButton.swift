import SwiftUI

struct ShadButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, outline, ghost, destructive, link }
    enum Size { case sm, md, lg, icon, iconSm }

    var variant: Variant = .primary
    var size: Size = .md
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        ShadButtonBody(configuration: configuration, variant: variant, size: size, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == ShadButtonStyle {
    static func shad(_ variant: ShadButtonStyle.Variant = .primary, size: ShadButtonStyle.Size = .md, fullWidth: Bool = false) -> ShadButtonStyle {
        ShadButtonStyle(variant: variant, size: size, fullWidth: fullWidth)
    }
}

private struct ShadButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: ShadButtonStyle.Variant
    let size: ShadButtonStyle.Size
    let fullWidth: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var height: CGFloat {
        switch size {
        case .sm, .iconSm: 32
        case .md: Shad.isMac ? 34 : 44
        case .icon: Shad.isMac ? 34 : 44
        case .lg: Shad.isMac ? 40 : 50
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .icon, .iconSm: 0
        case .sm: 12
        case .md: 16
        case .lg: 24
        }
    }

    private var cornerRadius: CGFloat { size == .lg && !Shad.isMac ? 12 : Shad.radiusSmall }

    private var isIcon: Bool { size == .icon || size == .iconSm }

    private var foreground: Color {
        switch variant {
        case .primary: Shad.primaryForeground
        case .destructive: .white
        case .secondary, .outline, .ghost, .link: Shad.foreground
        }
    }

    private var background: Color {
        let pressed = configuration.isPressed
        switch variant {
        case .primary: return Shad.primary.opacity(pressed ? 0.8 : hovering ? 0.9 : 1)
        case .destructive: return Shad.destructive.opacity(pressed ? 0.8 : hovering ? 0.9 : 1)
        case .secondary: return Shad.secondary.opacity(pressed ? 0.7 : hovering ? 0.8 : 1)
        case .outline: return hovering || pressed ? Shad.accent : Shad.background
        case .ghost: return hovering || pressed ? Shad.accent : .clear
        case .link: return .clear
        }
    }

    var body: some View {
        configuration.label
            .font(size == .lg && !Shad.isMac ? .system(size: 17, weight: .semibold) : Shad.font(size == .sm ? 13 : 14, .medium))
            .lineLimit(1)
            .underline(variant == .link && hovering)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(width: isIcon ? height : nil, height: height)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(background))
            .overlay {
                if variant == .outline {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Shad.input, lineWidth: 1)
                }
            }
            .shadow(color: (variant == .outline || variant == .primary) ? .black.opacity(0.05) : .clear, radius: 1, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !Shad.isMac ? 0.98 : 1)
            .onHover { hovering = $0 && isEnabled }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
