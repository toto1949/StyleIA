import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @Bindable var viewModel: AuthViewModel

    var body: some View {
        ZStack(alignment: .top) {
            DesignSystem.Colors.primary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        StyleAIIllustrationView()
                            .frame(width: 124, height: 124)

                        Text(L10n.string("auth.title"))
                            .font(Typography.displayMedium)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)

                        Text(L10n.string("auth.subtitle"))
                            .font(Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, DesignSystem.Spacing.xxl)

                    VStack(spacing: DesignSystem.Spacing.lg) {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            viewModel.handleAppleResult(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous))

                        divider

                        VStack(spacing: DesignSystem.Spacing.md) {
                            inputField(
                                title: L10n.string("auth.email"),
                                text: $viewModel.email,
                                error: viewModel.emailError,
                                keyboard: .emailAddress,
                                isSecure: false
                            )

                            inputField(
                                title: L10n.string("auth.password"),
                                text: $viewModel.password,
                                error: viewModel.passwordError,
                                keyboard: .default,
                                isSecure: true
                            )
                        }

                        PrimaryButton(
                            title: viewModel.primaryButtonTitle,
                            isLoading: viewModel.isLoading,
                            isDisabled: viewModel.email.isEmpty || viewModel.password.isEmpty
                        ) {
                            viewModel.submitEmail()
                        }

                        Button {
                            withAnimation(DesignSystem.Animations.easeOut) {
                                viewModel.isSignUp.toggle()
                            }
                        } label: {
                            Text(viewModel.isSignUp ? L10n.string("auth.toggle.signin") : L10n.string("auth.toggle.signup"))
                                .font(Typography.bodySmall)
                                .foregroundStyle(DesignSystem.Colors.accent)
                        }
                        .buttonStyle(PressScaleButtonStyle())
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .background(DesignSystem.Colors.surface.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.large, style: .continuous))
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                }
                .padding(.bottom, DesignSystem.Spacing.xl)
            }

            if let message = viewModel.errorMessage {
                ErrorBanner(message: message) {
                    withAnimation {
                        viewModel.errorMessage = nil
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
        }
    }

    private var divider: some View {
        HStack {
            Rectangle()
                .fill(DesignSystem.Colors.textSecondary.opacity(0.35))
                .frame(height: 1)
            Text(L10n.string("auth.or"))
                .font(Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Rectangle()
                .fill(DesignSystem.Colors.textSecondary.opacity(0.35))
                .frame(height: 1)
        }
    }

    private func inputField(
        title: String,
        text: Binding<String>,
        error: String?,
        keyboard: UIKeyboardType,
        isSecure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Group {
                if isSecure {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .font(Typography.body)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.primary.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium, style: .continuous)
                    .stroke(error == nil ? .clear : DesignSystem.Colors.error, lineWidth: 1)
            }

            if let error {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.error)
            }
        }
    }
}

#Preview {
    AuthView(viewModel: AuthViewModel(container: PreviewData.container, coordinator: PreviewData.coordinator))
}
