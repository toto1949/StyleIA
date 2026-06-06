import SwiftUI

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.Colors.warning)

            Text(message)
                .font(Typography.bodySmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: DesignSystem.Spacing.xs)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(PressScaleButtonStyle())
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous))
        .designShadow(DesignSystem.Shadows.card)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#Preview {
    ErrorBanner(message: L10n.string("error.network"), onDismiss: {})
        .padding()
        .background(DesignSystem.Colors.primary)
}
