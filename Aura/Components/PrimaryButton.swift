import SwiftUI

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(DesignSystem.Colors.textPrimary)
                }
                Text(title)
                    .font(Typography.titleMedium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .background(isDisabled ? DesignSystem.Colors.textSecondary.opacity(0.35) : DesignSystem.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(isDisabled || isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(DesignSystem.Colors.accent)
                }
                Text(title)
                    .font(Typography.titleMedium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(isDisabled ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.accent)
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous)
                    .stroke(isDisabled ? DesignSystem.Colors.textSecondary.opacity(0.35) : DesignSystem.Colors.accent, lineWidth: 1.5)
            }
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(isDisabled || isLoading)
    }
}

struct DestructiveButton: View {
    let title: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(DesignSystem.Colors.textPrimary)
                }
                Text(title)
                    .font(Typography.titleMedium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .background(isDisabled ? DesignSystem.Colors.textSecondary.opacity(0.35) : DesignSystem.Colors.error)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(isDisabled || isLoading)
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: L10n.string("common.continue"), action: {})
        SecondaryButton(title: L10n.string("common.cancel"), action: {})
        DestructiveButton(title: L10n.string("profile.signOut"), action: {})
    }
    .padding()
    .background(DesignSystem.Colors.primary)
}
