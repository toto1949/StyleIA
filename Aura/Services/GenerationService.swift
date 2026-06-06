import Foundation

struct SubmitGenerationRequest: Encodable {
    let s3Key: String
    let styleGoal: String
    let seed: Int?
}

struct DeleteResponse: Decodable {
    let success: Bool
}

struct GenerationService {
    private let apiService: APIService
    private let webSocketBaseURL: URL
    private let keychain: KeychainHelper
    private let session: URLSession
    private let accessTokenAccount = "styleai.accessToken"

    init(
        apiService: APIService,
        webSocketBaseURL: URL,
        keychain: KeychainHelper,
        session: URLSession = .shared
    ) {
        self.apiService = apiService
        self.webSocketBaseURL = webSocketBaseURL
        self.keychain = keychain
        self.session = session
    }

    func submit(s3Key: String, goal: StyleGoal) async throws -> GenerationJob {
        try await submit(s3Key: s3Key, goal: goal, seed: nil)
    }

    func submit(s3Key: String, goal: StyleGoal, seed: Int?) async throws -> GenerationJob {
        let body = SubmitGenerationRequest(s3Key: s3Key, styleGoal: goal.rawValue, seed: seed)
        let endpoint = try Endpoint.json(path: "/jobs", method: .post, body: body)
        return try await apiService.request(endpoint)
    }

    func observe(jobId: String) -> AsyncStream<JobUpdate> {
        AsyncStream { continuation in
            let task = Task {
                await listen(jobId: jobId, continuation: continuation)
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func cancel(jobId: String) async throws {
        let _: DeleteResponse = try await apiService.request(
            Endpoint(path: "/jobs/\(jobId)", method: .delete)
        )
    }

    private func listen(jobId: String, continuation: AsyncStream<JobUpdate>.Continuation) async {
        guard let token = keychain.retrieve(account: accessTokenAccount) else {
            continuation.yield(JobUpdate(jobId: jobId, payload: .failed(error: "unauthorized")))
            continuation.finish()
            return
        }

        var didReconnect = false

        while !Task.isCancelled {
            guard let url = makeWebSocketURL(jobId: jobId, token: token) else {
                continuation.yield(JobUpdate(jobId: jobId, payload: .failed(error: "invalidRequest")))
                continuation.finish()
                return
            }

            let socket = session.webSocketTask(with: url)
            socket.resume()

            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    if let update = decode(message: message, jobId: jobId) {
                        continuation.yield(update)
                        if update.isTerminal {
                            socket.cancel(with: .normalClosure, reason: nil)
                            continuation.finish()
                            return
                        }
                    }
                }
            } catch {
                socket.cancel(with: .goingAway, reason: nil)
                if didReconnect || Task.isCancelled {
                    continuation.finish()
                    return
                }

                didReconnect = true
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
        }

        continuation.finish()
    }

    private func makeWebSocketURL(jobId: String, token: String) -> URL? {
        var components = URLComponents(url: webSocketBaseURL.appendingPathComponent(jobId), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url
    }

    private func decode(message: URLSessionWebSocketTask.Message, jobId: String) -> JobUpdate? {
        let data: Data
        switch message {
        case .data(let incomingData):
            data = incomingData
        case .string(let string):
            guard let incomingData = string.data(using: .utf8) else {
                return nil
            }
            data = incomingData
        @unknown default:
            return nil
        }

        guard let payload = try? JSONDecoder().decode(JobWebSocketMessage.self, from: data) else {
            return nil
        }

        switch payload.type {
        case "progress":
            return JobUpdate(jobId: jobId, payload: .progress(percent: payload.percent ?? 0))
        case "completed":
            return JobUpdate(jobId: jobId, payload: .completed(resultURLs: payload.resultURLs ?? []))
        case "failed":
            return JobUpdate(jobId: jobId, payload: .failed(error: payload.error ?? "failed"))
        default:
            return nil
        }
    }
}

private extension JobUpdate {
    var isTerminal: Bool {
        switch payload {
        case .completed, .failed:
            true
        case .progress:
            false
        }
    }
}
