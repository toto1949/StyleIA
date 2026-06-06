import SwiftUI

enum DesignSystem {
    enum Colors {
        static let primary = Color("AppPrimary", bundle: .main)
        static let accent = Color("Accent", bundle: .main)
        static let surface = Color("Surface", bundle: .main)
        static let surfaceRaised = Color("SurfaceRaised", bundle: .main)
        static let textPrimary = Color("TextPrimary", bundle: .main)
        static let textSecondary = Color("TextSecondary", bundle: .main)
        static let success = Color("Success", bundle: .main)
        static let error = Color("Error", bundle: .main)
        static let warning = Color("Warning", bundle: .main)
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 20
        static let pill: CGFloat = 999
    }

    enum Shadows {
        static let subtle = ShadowToken(y: 2, blur: 8, opacity: 0.10)
        static let card = ShadowToken(y: 4, blur: 16, opacity: 0.15)
    }

    enum Animations {
        static let spring: Animation = .spring(response: 0.4, dampingFraction: 0.75)
        static let easeOut: Animation = .easeOut(duration: 0.25)
    }
}

struct ShadowToken {
    let y: CGFloat
    let blur: CGFloat
    let opacity: Double
}

extension View {
    func designShadow(_ token: ShadowToken) -> some View {
        shadow(color: .black.opacity(token.opacity), radius: token.blur, x: 0, y: token.y)
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(DesignSystem.Animations.easeOut, value: configuration.isPressed)
    }
}
