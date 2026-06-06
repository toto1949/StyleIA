import SwiftUI

struct OnboardingView: View {
    @Bindable var viewModel: OnboardingViewModel
    let coordinator: AppCoordinator

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DesignSystem.Colors.primary
                .ignoresSafeArea()

            VStack(spacing: DesignSystem.Spacing.xl) {
                TabView(selection: $viewModel.currentIndex) {
                    ForEach(viewModel.slides) { slide in
                        VStack(spacing: DesignSystem.Spacing.xl) {
                            Spacer(minLength: DesignSystem.Spacing.xl)

                            StyleAIIllustrationView()
                                .frame(width: 240, height: 240)
                                .scaleEffect(viewModel.currentIndex == slide.id ? 1 : 0.92)
                                .animation(DesignSystem.Animations.spring, value: viewModel.currentIndex)

                            VStack(spacing: DesignSystem.Spacing.md) {
                                Text(slide.title)
                                    .font(Typography.displayLarge)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.82)

                                Text(slide.subtitle)
                                    .font(Typography.body)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(4)
                            }
                            .padding(.horizontal, DesignSystem.Spacing.xl)

                            Spacer()
                        }
                        .tag(slide.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(viewModel.slides) { slide in
                        Capsule()
                            .fill(slide.id == viewModel.currentIndex ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary.opacity(0.35))
                            .frame(width: slide.id == viewModel.currentIndex ? 28 : 8, height: 8)
                            .animation(DesignSystem.Animations.spring, value: viewModel.currentIndex)
                    }
                }

                PrimaryButton(
                    title: viewModel.isLastSlide ? L10n.string("onboarding.cta") : L10n.string("common.continue")
                ) {
                    viewModel.advance {
                        coordinator.completeOnboarding()
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.lg)
            }

            if viewModel.currentIndex == 0 {
                Button(L10n.string("common.skip")) {
                    coordinator.skipOnboarding()
                }
                .font(Typography.titleMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .buttonStyle(PressScaleButtonStyle())
                .padding(DesignSystem.Spacing.lg)
            }
        }
    }
}

#Preview {
    OnboardingView(viewModel: OnboardingViewModel(), coordinator: PreviewData.coordinator)
}
