import SwiftUI

struct LoadingOverlay: View {
    let title: String

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: DesignSystem.Spacing.md) {
                ProgressView()
                    .scaleEffect(1.25)
                    .tint(DesignSystem.Colors.accent)

                Text(title)
                    .font(Typography.titleMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
            .padding(DesignSystem.Spacing.xl)
            .background(DesignSystem.Colors.surface.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.large, style: .continuous))
            .designShadow(DesignSystem.Shadows.card)
        }
    }
}

#Preview {
    LoadingOverlay(title: L10n.string("common.loading"))
}
