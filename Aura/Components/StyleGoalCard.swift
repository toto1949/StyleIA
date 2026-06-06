import SwiftUI

struct StyleGoalCard: View {
    let goal: StyleGoal
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text(goal.emoji)
                    .font(.system(size: 32))
                Text(goal.label)
                    .font(Typography.bodySmall)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 118, height: 104)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous)
                    .stroke(isSelected ? DesignSystem.Colors.accent : .clear, lineWidth: 2.5)
            }
            .scaleEffect(isSelected ? 1.05 : 1)
            .designShadow(isSelected ? DesignSystem.Shadows.card : DesignSystem.Shadows.subtle)
            .animation(DesignSystem.Animations.spring, value: isSelected)
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

#Preview {
    HStack {
        StyleGoalCard(goal: .casual, isSelected: true, action: {})
        StyleGoalCard(goal: .luxury, isSelected: false, action: {})
    }
    .padding()
    .background(DesignSystem.Colors.primary)
}
