import Foundation

let AuthExpiredNotification = Notification.Name("StyleAI.AuthExpiredNotification")

enum APIError: Error, Equatable {
    case unauthorized
    case notFound
    case serverError(message: String?)
    case networkError
    case decodingFailed
    case invalidRequest
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

struct Endpoint {
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]
    let body: Data?
    let headers: [String: String]
    let requiresAuth: Bool

    init(
        path: String,
        method: HTTPMethod,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        headers: [String: String] = [:],
        requiresAuth: Bool = true
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.body = body
        self.headers = headers
        self.requiresAuth = requiresAuth
    }

    static func json<T: Encodable>(
        path: String,
        method: HTTPMethod,
        body: T,
        requiresAuth: Bool = true,
        encoder: JSONEncoder = APIService.makeEncoder()
    ) throws -> Endpoint {
        Endpoint(
            path: path,
            method: method,
            body: try encoder.encode(body),
            headers: ["Content-Type": "application/json"],
            requiresAuth: requiresAuth
        )
    }
}

struct APIService {
    private let baseURL: URL
    private let session: URLSession
    private let keychain: KeychainHelper
    private let accessTokenAccount = "styleai.accessToken"

    init(
        baseURL: URL,
        session: URLSession = .shared,
        keychain: KeychainHelper
    ) {
        self.baseURL = baseURL
        self.session = session
        self.keychain = keychain
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            if let date = ISO8601DateFormatter.api.date(from: string) {
                return date
            }

            if let date = ISO8601DateFormatter.apiNoFractions.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date string"
            )
        }
        return decoder
    }

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        try await withTaskCancellationHandler {
            let request = try makeRequest(for: endpoint)
            let data: Data
            let response: URLResponse

            do {
                (data, response) = try await session.data(for: request)
            } catch {
                if error is CancellationError {
                    throw error
                }
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    throw CancellationError()
                }
                throw APIError.networkError
            }

            return try handle(data: data, response: response)
        } onCancel: {
        }
    }

    private func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        let trimmedPath = endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(trimmedPath),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidRequest
        }

        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.timeoutInterval = 30

        for (field, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        if endpoint.requiresAuth {
            guard let token = keychain.retrieve(account: accessTokenAccount), !token.isEmpty else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func handle<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try Self.makeDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decodingFailed
            }
        case 401:
            keychain.clear(account: accessTokenAccount)
            NotificationCenter.default.post(name: AuthExpiredNotification, object: nil)
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 500...599:
            let message = try? Self.makeDecoder().decode(APIErrorResponse.self, from: data).message
            throw APIError.serverError(message: message)
        default:
            let message = try? Self.makeDecoder().decode(APIErrorResponse.self, from: data).message
            throw APIError.serverError(message: message)
        }
    }
}

private struct APIErrorResponse: Decodable {
    let message: String?
}

private extension ISO8601DateFormatter {
    static let api: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let apiNoFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
