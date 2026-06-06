import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    var email = ""
    var password = ""
    var isSignUp = false
    var isLoading = false
    var errorMessage: String?
    var emailError: String?
    var passwordError: String?

    private let authService: AuthService
    private let coordinator: AppCoordinator
    private let haptics: HapticManager
    private let crashReporter: CrashReporting

    init(container: DependencyContainer, coordinator: AppCoordinator) {
        authService = container.authService
        haptics = container.haptics
        crashReporter = container.crashReporter
        self.coordinator = coordinator
    }

    var primaryButtonTitle: String {
        isSignUp ? L10n.string("auth.signup") : L10n.string("auth.signin")
    }

    func submitEmail() {
        guard validateFields() else { return }
        haptics.primaryTap()

        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            do {
                _ = try await authService.signInWithEmail(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                coordinator.signedIn()
            } catch {
                crashReporter.record(error: error)
                errorMessage = ErrorMessageMapper.message(for: error)
            }
        }
    }

    func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            do {
                let authorization = try result.get()
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    throw APIError.invalidRequest
                }

                _ = try await authService.signInWithApple(credential: credential)
                coordinator.signedIn()
            } catch {
                crashReporter.record(error: error)
                errorMessage = ErrorMessageMapper.message(for: error)
            }
        }
    }

    private func validateFields() -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        emailError = nil
        passwordError = nil

        if !normalizedEmail.contains("@") || !normalizedEmail.contains(".") {
            emailError = L10n.string("auth.email.invalid")
        }

        if password.count < 8 {
            passwordError = L10n.string("auth.password.invalid")
        }

        return emailError == nil && passwordError == nil
    }
}
