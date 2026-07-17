import SwiftUI

/// Email sign in / sign up gate shown before the main app.
struct AuthView: View {
    @ObservedObject var viewModel: SceneMeViewModel

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Create Account"

        var id: String { rawValue }
    }

    @State private var mode: Mode = .signIn
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var socialProvider: SocialProvider?
    @FocusState private var focusedField: Field?

    private enum SocialProvider {
        case apple
        case google
    }

    private var isGoogleConfigured: Bool {
        Secrets.googleClientID != nil
    }

    private enum Field {
        case name, email, password
    }

    private var isFormValid: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        return trimmedEmail.contains("@") && trimmedEmail.contains(".") && password.count >= 8
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                logo
                    .padding(.top, 70)

                socialButtons

                dividerLabel

                modeSwitcher

                VStack(spacing: 14) {
                    if mode == .signUp {
                        field(title: "Your name (optional)") {
                            TextField("", text: $fullName, prompt: prompt("Alex"))
                                .textContentType(.name)
                                .focused($focusedField, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .email }
                        }
                    }

                    field(title: "Email") {
                        TextField("", text: $email, prompt: prompt("you@example.com"))
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                    }

                    field(title: "Password") {
                        SecureField("", text: $password, prompt: prompt("At least 8 characters"))
                            .textContentType(mode == .signUp ? .newPassword : .password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { submit() }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.42))
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                submitButton

                Text(mode == .signIn
                     ? "New here? Switch to Create Account above."
                     : "Your photos stay private and can be deleted anytime.")
                    .font(.system(size: 12))
                    .foregroundStyle(SceneMeTheme.faintText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 18) {
                    Link("Privacy Policy", destination: Secrets.privacyPolicyURL)
                    Link("Terms of Use", destination: Secrets.termsOfUseURL)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SceneMeTheme.subtleText)
                .padding(.top, 4)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(SceneMeTheme.ink.ignoresSafeArea())
        .onChange(of: mode) { _, _ in
            withAnimation { errorMessage = nil }
        }
    }

    private var dividerLabel: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(SceneMeTheme.hairline)
                .frame(height: 1)

            Text("OR USE EMAIL")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(SceneMeTheme.faintText)

            Rectangle()
                .fill(SceneMeTheme.hairline)
                .frame(height: 1)
        }
    }

    private var socialButtons: some View {
        VStack(spacing: 12) {
            socialButton(
                title: "Continue with Apple",
                systemImage: "apple.logo",
                background: Color.white,
                foreground: Color.black.opacity(0.88),
                isLoading: socialProvider == .apple
            ) {
                signInWithApple()
            }

            if isGoogleConfigured {
                socialButton(
                    title: "Continue with Google",
                    systemImage: "g.circle.fill",
                    background: SceneMeTheme.panel,
                    foreground: SceneMeTheme.text,
                    isLoading: socialProvider == .google
                ) {
                    signInWithGoogle()
                }
            }
        }
    }

    private func socialButton(
        title: String,
        systemImage: String,
        background: Color,
        foreground: Color,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(foreground)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }

                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.4)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(background)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(SceneMeTheme.hairline, lineWidth: background == .white ? 0 : 1)
            }
            .opacity(isSubmitting || socialProvider != nil ? 0.72 : 1)
        }
        .buttonStyle(SceneMePressButtonStyle())
        .disabled(isSubmitting || socialProvider != nil)
    }

    private var logo: some View {
        VStack(spacing: 12) {
            (
                Text("Scene")
                    .foregroundStyle(SceneMeTheme.text)
                +
                Text("Me")
                    .foregroundStyle(SceneMeTheme.gold)
            )
            .font(.system(size: 40, weight: .regular, design: .serif))

            Text("Place yourself anywhere.")
                .font(.system(size: 14))
                .foregroundStyle(SceneMeTheme.subtleText)
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases) { item in
                let isSelected = mode == item

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        mode = item
                    }
                } label: {
                    Text(item.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(isSelected ? Color.black.opacity(0.88) : SceneMeTheme.subtleText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(isSelected ? SceneMeTheme.gold : SceneMeTheme.panel)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(isSelected ? Color.clear : SceneMeTheme.hairline, lineWidth: 1)
                        }
                }
                .buttonStyle(SceneMePressButtonStyle())
            }
        }
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(2.2)
                .foregroundStyle(SceneMeTheme.subtleText)

            content()
                .font(.system(size: 15))
                .foregroundStyle(SceneMeTheme.text)
                .padding(14)
                .background(SceneMeTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SceneMeTheme.cardRadius - 6, style: .continuous)
                        .stroke(SceneMeTheme.hairline, lineWidth: 1)
                }
        }
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(SceneMeTheme.faintText)
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 10) {
                if isSubmitting {
                    ProgressView()
                        .tint(Color.black.opacity(0.7))
                } else {
                    Image(systemName: mode == .signIn ? "arrow.right.circle.fill" : "sparkles")
                        .font(.system(size: 14, weight: .bold))
                }

                Text(mode == .signIn ? "SIGN IN" : "CREATE ACCOUNT")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(2)
            }
            .foregroundStyle(Color.black.opacity(0.88))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [SceneMeTheme.goldBright, SceneMeTheme.gold],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(isFormValid && !isSubmitting ? 1 : 0.4)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(SceneMePressButtonStyle())
        .disabled(!isFormValid || isSubmitting || socialProvider != nil)
    }

    private func submit() {
        guard isFormValid, !isSubmitting, socialProvider == nil else { return }

        focusedField = nil
        isSubmitting = true
        withAnimation { errorMessage = nil }

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let currentMode = mode

        Task {
            do {
                if currentMode == .signIn {
                    try await viewModel.signIn(email: trimmedEmail, password: password)
                } else {
                    try await viewModel.signUp(email: trimmedEmail, password: password, fullName: fullName)
                }
            } catch {
                withAnimation {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
                }
            }
            isSubmitting = false
        }
    }

    private func signInWithApple() {
        guard socialProvider == nil, !isSubmitting else { return }
        socialProvider = .apple
        withAnimation { errorMessage = nil }

        Task {
            do {
                try await viewModel.signInWithApple()
            } catch SocialAuthError.cancelled {
                // User dismissed the sheet.
            } catch {
                withAnimation {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "Apple sign in failed."
                }
            }
            socialProvider = nil
        }
    }

    private func signInWithGoogle() {
        guard socialProvider == nil, !isSubmitting else { return }
        socialProvider = .google
        withAnimation { errorMessage = nil }

        Task {
            do {
                try await viewModel.signInWithGoogle()
            } catch {
                withAnimation {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "Google sign in failed."
                }
            }
            socialProvider = nil
        }
    }
}
