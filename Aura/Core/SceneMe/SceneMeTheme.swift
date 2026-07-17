import SwiftUI

/// SceneMe design language: deep black canvas, warm gold accents, serif display type.
enum SceneMeTheme {
    static let ink = Color(hex: 0x050505)
    static let panel = Color(hex: 0x111111)
    static let surface = Color(hex: 0x1A1A1A)
    static let gold = Color(hex: 0xC9A85C)
    static let goldBright = Color(hex: 0xDFC078)
    static let text = Color.white.opacity(0.94)
    static let subtleText = Color.white.opacity(0.48)
    static let faintText = Color.white.opacity(0.26)
    static let hairline = Color.white.opacity(0.09)

    static let cardRadius: CGFloat = 20
    static let innerRadius: CGFloat = 14
}

struct SceneMePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Small gold eyebrow label, e.g. "✦ YOUR WORLD, EXPANDED".
struct SceneMeEyebrow: View {
    let text: String
    var alignment: Alignment = .leading

    var body: some View {
        Text("✦ \(text.uppercased())")
            .font(.system(size: 11, weight: .bold))
            .tracking(2.6)
            .foregroundStyle(SceneMeTheme.gold)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

/// Section header with optional trailing action, e.g. "Featured Scenes   SEE ALL →".
struct SceneMeSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(SceneMeTheme.text)

            Spacer()

            if let actionTitle, let action {
                Button(action: action) {
                    Text("\(actionTitle.uppercased()) →")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(SceneMeTheme.gold)
                        .padding(.vertical, 8)
                        .padding(.leading, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SceneMePressButtonStyle())
            }
        }
    }
}

/// Primary gold capsule CTA used across the app.
struct SceneMeCTAButton: View {
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .bold))
                }
                Text(title.uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .tracking(2)
            }
            .foregroundStyle(Color.black.opacity(0.88))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [SceneMeTheme.goldBright, SceneMeTheme.gold],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
            .shadow(color: SceneMeTheme.gold.opacity(0.3), radius: 14, y: 6)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(SceneMePressButtonStyle())
        .disabled(!isEnabled)
    }
}

/// Secondary dark capsule button.
struct SceneMeSecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.8)
            }
            .foregroundStyle(SceneMeTheme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(SceneMeTheme.panel)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .overlay {
                Capsule().stroke(SceneMeTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(SceneMePressButtonStyle())
    }
}

/// Circular icon button used in toolbars (back, heart, share).
struct SceneMeCircleButton: View {
    let systemImage: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isActive ? SceneMeTheme.gold : SceneMeTheme.text)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.55))
                .clipShape(Circle())
                .contentShape(Circle())
                .overlay {
                    Circle().stroke(SceneMeTheme.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(SceneMePressButtonStyle())
    }
}
