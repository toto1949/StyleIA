import Foundation

enum SceneMeAPIError: Error, LocalizedError {
    case missingPhoto
    case invalidResponse
    case unauthorized
    case backendUnreachable(URL)
    case failed(String)
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingPhoto:
            return "Upload a photo first to generate your scene."
        case .invalidResponse:
            return "Something went wrong on our end. Please try again."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .backendUnreachable(let url):
            #if DEBUG
            return "Could not reach the backend at \(url.absoluteString). Make sure the backend is running and your iPhone is on the same Wi-Fi."
            #else
            return "Couldn't connect to SceneMe. Check your internet connection and try again."
            #endif
        case .failed(let message):
            return message
        case .timedOut:
            return "Scene generation timed out. Please try again."
        case .cancelled:
            return "Generation was cancelled."
        }
    }
}

/// Thin HTTP client for the SceneMe backend: auth, scenes, uploads, scene jobs.
struct APIService {

    let baseURL: URL
    var session: URLSession = .shared

    init?() {
        guard let url = Secrets.backendAPIBaseURL else {
            return nil
        }
        baseURL = url
    }

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    private struct AuthRequest: Encodable {
        let email: String
        let password: String
        let mode: String
        let fullName: String
    }

    private struct AppleAuthRequest: Encodable {
        let identityToken: String
        let authorizationCode: String
        let fullName: String
    }

    private struct GoogleAuthRequest: Encodable {
        let identityToken: String
        let fullName: String
    }

    struct AuthResponse: Decodable {
        let userId: String
        let email: String
        let fullName: String
        let accessToken: String
        let accessTokenExpiresIn: Int?
        let refreshToken: String?
    }

    struct EmptyBody: Encodable {}

    /// Server-verified account feature access. Unlike StoreKit entitlements,
    /// complimentary App Review access is tied to the authenticated SceneMe user.
    struct AccountStatus: Decodable {
        struct Subscription: Decodable {
            let tier: String
            let status: String
            let expiresAt: String?
            let gracePeriodExpiresAt: String?
            let environment: String?
            let isReviewAccess: Bool?
            let productId: String?
        }

        let subscription: Subscription
    }

    func fetchAccountStatus(token: String) async throws -> AccountStatus {
        try await get("me", token: token)
    }


    struct ImprovedSceneTemplate: Decodable {
        let name: String
        let description: String
        let outfit: String
    }

    struct AccountState: Decodable {
        typealias Subscription = AccountStatus.Subscription

        struct Usage: Decodable {
            let month: String
            let imageGenerations: Int
            let videoGenerations: Int
        }

        struct Credits: Decodable {
            let balance: Int
            let grantsNeverExpire: Bool
            let starterCredits: Int
            let creatorMonthlyCredits: Int
            let proMonthlyCredits: Int
            let latestGrantAt: String?
        }

        let subscription: Subscription
        let credits: Credits
        let usage: Usage
    }

    private struct ImproveSceneTemplateRequest: Encodable {
        let name: String
        let description: String
        let outfit: String
    }

    func signIn(email: String, password: String) async throws -> AuthResponse {
        try await post(
            "auth/email",
            body: AuthRequest(email: email, password: password, mode: "signin", fullName: ""),
            token: nil
        )
    }

    func signUp(email: String, password: String, fullName: String) async throws -> AuthResponse {
        try await post(
            "auth/email",
            body: AuthRequest(email: email, password: password, mode: "signup", fullName: fullName),
            token: nil
        )
    }

    func signInWithApple(identityToken: String, authorizationCode: String, fullName: String) async throws -> AuthResponse {
        try await post(
            "auth/apple",
            body: AppleAuthRequest(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: fullName
            ),
            token: nil
        )
    }

    func signInWithGoogle(identityToken: String, fullName: String) async throws -> AuthResponse {
        try await post(
            "auth/google",
            body: GoogleAuthRequest(identityToken: identityToken, fullName: fullName),
            token: nil
        )
    }

    func refreshSession(refreshToken: String) async throws -> AuthResponse {
        struct Request: Encodable { let refreshToken: String }
        return try await post("auth/refresh", body: Request(refreshToken: refreshToken), token: nil)
    }

    func signOut(refreshToken: String) async throws {
        struct Request: Encodable { let refreshToken: String }
        struct Response: Decodable { let success: Bool }
        let _: Response = try await post("auth/logout", body: Request(refreshToken: refreshToken), token: nil)
    }

    func deleteAccount(token: String) async throws {
        try await delete("account", token: token)
    }

    func fetchScenes() async throws -> [SceneTemplate] {
        let payload: ScenesPayload = try await get("scenes", token: nil)
        return payload.scenes
    }

    func fetchAccountState(token: String) async throws -> AccountState {
        try await get("me", token: token)
    }

    func syncSubscription(transactionID: String, token: String) async throws -> AccountState.Subscription {
        struct Request: Encodable { let transactionId: String }
        return try await post(
            "subscriptions/sync",
            body: Request(transactionId: transactionID),
            token: token,
            appStoreTransactionID: transactionID
        )
    }

    func improveSceneTemplate(
        name: String,
        description: String,
        outfit: String,
        token: String,
        appStoreTransactionID: String?
    ) async throws -> ImprovedSceneTemplate {
        try await post(
            "templates/improve",
            body: ImproveSceneTemplateRequest(name: name, description: description, outfit: outfit),
            token: token,
            appStoreTransactionID: appStoreTransactionID
        )
    }

    func post<RequestBody: Encodable, ResponseBody: Decodable>(
        _ path: String,
        body: RequestBody,
        token: String?,
        appStoreTransactionID: String? = nil,
        idempotencyKey: String? = nil
    ) async throws -> ResponseBody {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let appStoreTransactionID {
            request.setValue(appStoreTransactionID, forHTTPHeaderField: "X-SceneMe-App-Store-Transaction-ID")
        }
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        request.httpBody = try JSONEncoder().encode(body)

        return try await decode(request)
    }

    func get<ResponseBody: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        token: String?
    ) async throws -> ResponseBody {
        var url = endpoint(path)
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query
            if let resolved = components.url {
                url = resolved
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return try await decode(request)
    }

    func delete(_ path: String, token: String) async throws {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }
        try validate(response: response, data: data)
    }

    func upload(data payload: Data, contentType: String, to url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }
        try validate(response: response, data: data)
    }

    private func decode<ResponseBody: Decodable>(_ request: URLRequest) async throws -> ResponseBody {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }

        try validate(response: response, data: data)
        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SceneMeAPIError.invalidResponse
        }

        guard 200..<300 ~= http.statusCode else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["message"] ?? $0["error"]) as? String }

            // The backend answers exactly "Unauthorized." for expired or invalid
            // tokens; auth endpoints use specific messages (wrong password, etc).
            if http.statusCode == 401, message == nil || message == "Unauthorized." {
                throw SceneMeAPIError.unauthorized
            }

            throw SceneMeAPIError.failed(message ?? "Backend request failed with status \(http.statusCode).")
        }
    }

    private func endpoint(_ path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }
    }

    private func mapTransportError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else {
            return error
        }

        switch urlError.code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut:
            return SceneMeAPIError.backendUnreachable(baseURL)
        default:
            return error
        }
    }
}
