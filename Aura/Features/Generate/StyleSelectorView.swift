import SwiftUI

struct StyleSelectorView: View {
    @Binding var selectedGoal: StyleGoal?
    let onSelect: (StyleGoal) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.md) {
                ForEach(StyleGoal.allCases) { goal in
                    StyleGoalCard(goal: goal, isSelected: selectedGoal == goal) {
                        onSelect(goal)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
    }
}

#Preview {
    @Previewable @State var selected: StyleGoal? = .casual
    StyleSelectorView(selectedGoal: $selected) { selected = $0 }
        .background(DesignSystem.Colors.primary)
}
