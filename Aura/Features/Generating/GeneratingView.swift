import SwiftUI

struct GeneratingView: View {
    @Bindable var viewModel: GeneratingViewModel

    var body: some View {
        ZStack {
            DesignSystem.Colors.primary
                .ignoresSafeArea()

            VStack(spacing: DesignSystem.Spacing.xl) {
                Spacer()

                GenerationProgress(percent: viewModel.progress)

                Text(viewModel.tips[viewModel.currentTipIndex])
                    .font(Typography.titleMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(DesignSystem.Animations.easeOut, value: viewModel.currentTipIndex)
                    .frame(minHeight: 48)
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                Spacer()

                SecondaryButton(title: L10n.string("generating.cancel")) {
                    viewModel.cancel()
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.lg)
            }
        }
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(true)
        .task {
            viewModel.start()
        }
        .sheet(isPresented: $viewModel.showFailureSheet) {
            VStack(spacing: DesignSystem.Spacing.lg) {
                ErrorBanner(message: viewModel.errorMessage ?? ErrorMessageMapper.generationFailed, onDismiss: {})
                    .allowsHitTesting(false)

                PrimaryButton(title: L10n.string("common.tryAgain")) {
                    viewModel.retry()
                }

                SecondaryButton(title: L10n.string("common.goBack")) {
                    viewModel.goBackAfterFailure()
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.primary.ignoresSafeArea())
            .presentationDetents([.medium])
        }
    }
}

#Preview {
    GeneratingView(
        viewModel: GeneratingViewModel(
            input: GenerationInput(image: PreviewData.sampleImage(color: .systemBlue), styleGoal: .casual),
            container: PreviewData.container,
            coordinator: PreviewData.coordinator
        )
    )
}
