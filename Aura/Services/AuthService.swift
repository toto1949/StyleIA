import AuthenticationServices
import Foundation

struct AppleAuthRequest: Encodable {
    let identityToken: String
    let fullName: String
}

struct EmailAuthRequest: Encodable {
    let email: String
    let password: String
}

struct AuthService {
    private let apiService: APIService
    private let keychain: KeychainHelper
    private let accessTokenAccount = "styleai.accessToken"
    private let userIdAccount = "styleai.userId"
    private let defaults: UserDefaults

    init(
        apiService: APIService,
        keychain: KeychainHelper,
        defaults: UserDefaults = .standard
    ) {
        self.apiService = apiService
        self.keychain = keychain
        self.defaults = defaults
    }

    func storeToken(_ token: String) throws {
        try keychain.store(token, account: accessTokenAccount)
    }

    func retrieveToken() -> String? {
        keychain.retrieve(account: accessTokenAccount)
    }

    func clearToken() {
        keychain.clear(account: accessTokenAccount)
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws -> User {
        guard
            let tokenData = credential.identityToken,
            let identityToken = String(data: tokenData, encoding: .utf8)
        else {
            throw APIError.invalidRequest
        }

        let components = credential.fullName
        let fullName = [components?.givenName, components?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")

        let request = AppleAuthRequest(identityToken: identityToken, fullName: fullName)
        let endpoint = try Endpoint.json(path: "/auth/apple", method: .post, body: request, requiresAuth: false)
        let user: User = try await apiService.request(endpoint)
        let email = user.email.isEmpty ? credential.email ?? defaults.string(forKey: "styleai.email") ?? "" : user.email
        let resolvedUser = User(userId: user.userId, email: email, accessToken: user.accessToken)
        try persist(user: resolvedUser)
        return resolvedUser
    }

    func signInWithEmail(email: String, password: String) async throws -> User {
        let request = EmailAuthRequest(email: email, password: password)
        let endpoint = try Endpoint.json(path: "/auth/email", method: .post, body: request, requiresAuth: false)
        let user: User = try await apiService.request(endpoint)
        let resolvedUser = User(userId: user.userId, email: email, accessToken: user.accessToken)
        try persist(user: resolvedUser)
        return resolvedUser
    }

    func currentUser() -> User? {
        guard
            let accessToken = keychain.retrieve(account: accessTokenAccount),
            let userId = keychain.retrieve(account: userIdAccount)
        else {
            return nil
        }

        return User(userId: userId, email: defaults.string(forKey: "styleai.email") ?? "", accessToken: accessToken)
    }

    func signOut() {
        clearToken()
        keychain.clear(account: userIdAccount)
        defaults.removeObject(forKey: "styleai.email")
    }

    private func persist(user: User) throws {
        try storeToken(user.accessToken)
        try keychain.store(user.userId, account: userIdAccount)
        defaults.set(user.email, forKey: "styleai.email")
    }
}
