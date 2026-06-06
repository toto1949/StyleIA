import SwiftUI

struct GenerationProgress: View {
    let percent: Int
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(DesignSystem.Colors.surfaceRaised.opacity(0.55), lineWidth: 18)

            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(percent, 100))) / 100)
                .stroke(
                    AngularGradient(
                        colors: [
                            DesignSystem.Colors.accent,
                            DesignSystem.Colors.warning,
                            DesignSystem.Colors.success,
                            DesignSystem.Colors.accent
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90 + rotation))
                .animation(DesignSystem.Animations.spring, value: percent)

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("\(max(0, min(percent, 100)))%")
                    .font(.system(size: 42, weight: .bold))
                    .monospacedDigit()
                Text(L10n.string("generation.progress"))
                    .font(Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .frame(width: 220, height: 220)
        .onAppear {
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

#Preview {
    GenerationProgress(percent: 64)
        .padding()
        .background(DesignSystem.Colors.primary)
}
