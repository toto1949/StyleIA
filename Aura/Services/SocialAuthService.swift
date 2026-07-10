import AuthenticationServices
import Foundation
import GoogleSignIn
import UIKit

enum SocialAuthError: LocalizedError {
    case cancelled
    case missingIdentityToken
    case googleNotConfigured
    case missingPresenter

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign in was cancelled."
        case .missingIdentityToken:
            return "Could not read your sign-in token. Please try again."
        case .googleNotConfigured:
            return "Google Sign-In is not configured yet."
        case .missingPresenter:
            return "Could not present Google Sign-In."
        }
    }
}

struct AppleSignInCredential {
    let identityToken: String
    let fullName: String
}

/// Handles Sign in with Apple and Google on device, returning tokens for the backend.
@MainActor
final class SocialAuthService: NSObject {
    static let shared = SocialAuthService()

    private var appleContinuation: CheckedContinuation<AppleSignInCredential, Error>?

    private override init() {
        super.init()
    }

    func configureGoogleIfNeeded() {
        guard let clientID = Secrets.googleClientID else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    func handleGoogleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    func signInWithApple() async throws -> AppleSignInCredential {
        try await withCheckedThrowingContinuation { continuation in
            appleContinuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func signInWithGoogle() async throws -> String {
        guard Secrets.googleClientID != nil else {
            throw SocialAuthError.googleNotConfigured
        }

        configureGoogleIfNeeded()

        guard let presenter = Self.topViewController() else {
            throw SocialAuthError.missingPresenter
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let token = result.user.idToken?.tokenString else {
            throw SocialAuthError.missingIdentityToken
        }
        return token
    }

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController

        if let navigation = root as? UINavigationController {
            return topViewController(base: navigation.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(base: presented)
        }
        return root
    }
}

extension SocialAuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                appleContinuation?.resume(throwing: SocialAuthError.missingIdentityToken)
                appleContinuation = nil
                return
            }

            guard
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                appleContinuation?.resume(throwing: SocialAuthError.missingIdentityToken)
                appleContinuation = nil
                return
            }

            let fullName = [
                credential.fullName?.givenName,
                credential.fullName?.familyName
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

            appleContinuation?.resume(returning: AppleSignInCredential(
                identityToken: identityToken,
                fullName: fullName
            ))
            appleContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            if (error as? ASAuthorizationError)?.code == .canceled {
                appleContinuation?.resume(throwing: SocialAuthError.cancelled)
            } else {
                appleContinuation?.resume(throwing: error)
            }
            appleContinuation = nil
        }
    }
}

extension SocialAuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? UIWindow()
        }
    }
}
