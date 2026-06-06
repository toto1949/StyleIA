import SwiftUI

struct EmptyStateView: View {
    let title: String
    var subtitle: String?
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            StyleAIIllustrationView()
                .frame(width: 150, height: 150)

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text(title)
                    .font(Typography.titleLarge)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(Typography.bodySmall)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let buttonTitle, let action {
                PrimaryButton(title: buttonTitle, action: action)
                    .frame(maxWidth: 280)
            }
        }
        .padding(DesignSystem.Spacing.xl)
    }
}

struct StyleAIIllustrationView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Colors.surfaceRaised)
            Circle()
                .fill(DesignSystem.Colors.accent.opacity(0.22))
                .frame(width: 96, height: 96)
                .offset(x: 18, y: -16)
            RoundedRectangle(cornerRadius: DesignSystem.Radius.large, style: .continuous)
                .fill(DesignSystem.Colors.surface)
                .frame(width: 82, height: 108)
                .rotationEffect(.degrees(-7))
                .overlay {
                    VStack(spacing: 7) {
                        Circle()
                            .fill(DesignSystem.Colors.textPrimary.opacity(0.92))
                            .frame(width: 30, height: 30)
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.pill, style: .continuous)
                            .fill(DesignSystem.Colors.accent)
                            .frame(width: 54, height: 12)
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.pill, style: .continuous)
                            .fill(DesignSystem.Colors.textSecondary)
                            .frame(width: 42, height: 8)
                    }
                }
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.warning)
                .offset(x: -48, y: -42)
        }
    }
}

#Preview {
    EmptyStateView(
        title: L10n.string("history.empty.title"),
        subtitle: L10n.string("history.empty.subtitle"),
        buttonTitle: L10n.string("history.empty.cta"),
        action: {}
    )
    .background(DesignSystem.Colors.primary)
}
